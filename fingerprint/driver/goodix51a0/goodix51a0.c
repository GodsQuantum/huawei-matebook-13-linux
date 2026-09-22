/*
 * Goodix GXFP51A0 SPI (TLS-PSK) driver for libfprint
 *
 * Copyright (C) 2026 Benjamin Allègre (https://github.com/Sigfrodr)
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
 *
 * Driver candidate for the GXFP51A0 SPI fingerprint sensor used in Huawei
 * MateBook systems. The chain is: split Milan SPI framing, target-specific
 * ChicagoHS configuration, TLS-PSK, and an 80x64 image path (capture
 * integration still under validation).
 * (six bytes carry four interleaved pixels) calibrated by subtracting a
 * background frame.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <https://www.gnu.org/licenses/>.
 */

#define FP_COMPONENT "goodix51a0"
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <errno.h>
#include <glib/gstdio.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>
#include <unistd.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <linux/spi/spidev.h>
#include <linux/gpio.h>
#include <openssl/crypto.h>

#include "goodix51a0.h"
#include "goodix_sift.h"
#include "goodix_tls.h"

#include "gx51_transport.h"
#include "gx51_target.h"
#include "gx51_factory_pmk.h"
#include "gx51_image.h"
#include "gx51_capture_recipe.h"

G_STATIC_ASSERT (GOODIX_PSK_LEN == GXFP_FACTORY_PMK_LEN);


/* Frames averaged for background and finger: a noise/latency trade-off. */
#define GOODIX_BG_FRAMES     1
#define GOODIX_FINGER_FRAMES 3
/* Finger detection threshold on the standard deviation of the
 * background-minus-frame difference. */
#define GOODIX_FINGER_STD    150.0
/* Headroom above the ~10.6 kB target image record and the 22 kB regression case. */
#define GOODIX_RX_MAX        24000
#define GXFP_PMK_ACQUIRE_ATTEMPTS 4
#define GX_TARGET_ACK_ATTEMPTS 2
#define GX_TARGET_ACK_IRQ_TIMEOUT_MS 100
#define GX_PMK_CACHE_DIR  "/var/lib/fprint"
#define GX_PMK_CACHE_FILE "/var/lib/fprint/.goodix51a0-pmk"

struct _FpiDeviceGoodix51A0
{
  FpDevice parent;

  int           spi_fd;
  int           irq_fd;
  FpiSsm       *task_ssm;

  /* TLS stack. Note the sensor is the client and we are the server. */
  GxTls        *tls;
  gboolean      tls_up;

  guint8        psk[GOODIX_PSK_LEN];
  gboolean      psk_ready;
  gboolean      psk_from_cache;
  struct gxfp_target_calibration target_cal;
  gboolean      have_target_cal;

  /* Reassembly buffer for TLS records, drained by the BIO recv callback. */
  guint8        tls_rx[GOODIX_RX_MAX];
  int           tls_rxlen, tls_rxpos;

  guint16      *bg_frame;    /* averaged background, NULL until calibrated */
  guint         poll_id;     /* finger-detection timeout source */
  int           poll_count;  /* poll iterations, bounded to avoid hanging */
  GPtrArray    *enroll_feats;/* descriptor sets accumulated during enrolment */
  int           fdt_base[GXFP_FDT_ZONE_COUNT]; /* FDT baseline (finger absent) */
  gboolean      have_fdt;    /* is fdt_base populated? */
  int           fdt_abs;     /* per-unit absolute floor, derived from baseline */
  int           timing_scale;/* protocol-delay multiplier in %, grows on desync */
  int           timing_saved;/* last value persisted to disk, to avoid rewrites */
  int           capture_gap_scale; /* capture-step gap %, independent of TLS timing */
  int           capture_gap_saved; /* last capture pacing value persisted to disk */
  guint         capture_clean_streak; /* consecutive complete frames without GET_IMAGE retry */
  gboolean      capture_retry_seen; /* current frame needed a GET_IMAGE/TLS retry */
  gboolean      capture_pacing_suppressed; /* lifecycle loss is not pacing evidence */
  gboolean      capture_recovery_pending; /* transport failed; rebuild between presses */
  gboolean      bg_dirty;    /* background taken with a finger down */
  gboolean      production_ready; /* TLS + fresh background + FDT prepared during open */
  gboolean      warm_valid;       /* TLS/background/FDT retained across fp_device close */
  gint64        warm_sleep_delta_us; /* CLOCK_BOOTTIME-MONOTONIC when warm state was armed */
  gboolean      warm_sleep_clock_valid; /* baseline validity; zero is a legitimate pre-first-suspend value */
  gboolean      force_cold_reset; /* suspend/lifecycle invalidation: never reuse stale sensor state */
};

G_DECLARE_FINAL_TYPE (FpiDeviceGoodix51A0, fpi_device_goodix51a0, FPI,
                      DEVICE_GOODIX51A0, FpDevice)
G_DEFINE_TYPE (FpiDeviceGoodix51A0, fpi_device_goodix51a0, FP_TYPE_DEVICE)

static guint gx_capture_gap_us (FpiDeviceGoodix51A0 *self);
static void gx_capture_transport_desync (FpiDeviceGoodix51A0 *self);
static void gx_capture_pacing_success (FpiDeviceGoodix51A0 *self);

static const FpIdEntry goodix51a0_id_table[] = {
  { .udev_types = FPI_DEVICE_UDEV_SUBTYPE_SPIDEV, .spi_acpi_id = "GXFP51A0" },
  { .udev_types = 0 }
};

/* Fixed startup commands, byte-for-byte as validated against the sensor. */
static const guint8 GX_AMORCE[] = { 0, 5, 0, 0, 0, 0, 0, 0xA5 };
static const guint8 GX_ENABLE[] = { 0x96, 0x03, 0x00, 0x01, 0x00, 0x10 };
static const guint8 GX_REQTLS[] = { 0xd0, 0x03, 0x00, 0x00, 0x00, 0xd7 };
static const guint8 GX_TLS_OK[] = { 0xd4, 0x03, 0x00, 0x00, 0x00, 0xd3 };

#define GX_TLS_IRQ_POLL_MS 20
#define GX_TLS_IRQ_POLLS 200

static gboolean gx_read_fw_version_once (FpiDeviceGoodix51A0 *self,
                                           gchar *out,
                                           gsize cap);
#ifdef GXFP51A0_DEVELOPER
static void gx_dump_capture (FpiDeviceGoodix51A0 *self,
                             const guint16 *px);
#endif

/* ------------------------------------------------------------------ */
/*  SPI transport: one frame is exactly one transfer                   */
/* ------------------------------------------------------------------ */

static gboolean
gx_write_frame (FpiDeviceGoodix51A0 *self, guint8 type,
                const guint8 *body, gsize n)
{
  struct gx51_outer hdr;
  struct spi_ioc_transfer xfer = { 0 };

  if (n == 0 || n > 0xffff ||
      gx51_make_outer (type, n, &hdr) < 0)
    return FALSE;

  xfer.tx_buf = (unsigned long) &hdr;
  xfer.len = sizeof hdr;
  if (ioctl (self->spi_fd, SPI_IOC_MESSAGE (1), &xfer) < 1)
    return FALSE;

  g_usleep (2000);

  memset (&xfer, 0, sizeof xfer);
  xfer.tx_buf = (unsigned long) body;
  xfer.len = n;
  return ioctl (self->spi_fd, SPI_IOC_MESSAGE (1), &xfer) >= 1;
}


/* Reads one frame: a 4-byte header then the body. Returns the body length,
 * or -1 on failure. */
static int
gx_read_frame (FpiDeviceGoodix51A0 *self, guint8 *out_type,
               guint8 *rx, gsize rx_cap)
{
  guint8 hdr[4] = { 0 };
  struct spi_ioc_transfer xfer = { 0 };
  guint16 n;

  if (self->irq_fd < 0 ||
      gx51_wait_irq_gpio48 (self->irq_fd, 1200) < 0)
    return -1;

  xfer.rx_buf = (unsigned long) hdr;
  xfer.len = sizeof hdr;
  if (ioctl (self->spi_fd, SPI_IOC_MESSAGE (1), &xfer) < 1)
    return -1;

  if (hdr[0] == 0xff && hdr[1] == 0xff &&
      hdr[2] == 0xff && hdr[3] == 0xff)
    return -1;

  if ((guint8) (hdr[0] + hdr[1] + hdr[2]) != hdr[3])
    return -1;

  if (hdr[0] != GOODIX_PKT_PLAIN && hdr[0] != GOODIX_PKT_TLS)
    return -1;

  *out_type = hdr[0];
  n = hdr[1] | (hdr[2] << 8);
  if (n == 0 || n > rx_cap)
    return -1;

  for (gsize off = 0; off < n; )
    {
      gsize chunk = gx51_read_chunk_size ((gsize) n - off);

      memset (&xfer, 0, sizeof xfer);
      xfer.rx_buf = (unsigned long) (rx + off);
      xfer.len = (guint32) chunk;
      if (ioctl (self->spi_fd, SPI_IOC_MESSAGE (1), &xfer) < 1)
        return -1;
      off += chunk;
    }

  return n;
}


/* Sends the preamble (A0), then a plaintext command (A0). */
static gboolean
gx_send_plain_raw (FpiDeviceGoodix51A0 *self, const guint8 *body, gsize n)
{
  if (!gx_write_frame (self, GOODIX_PKT_PLAIN, GX_AMORCE, sizeof GX_AMORCE))
    return FALSE;
  g_usleep (8000);
  return gx_write_frame (self, GOODIX_PKT_PLAIN, body, n);
}

/* Sends a cleartext command and drains every plain response. A TLS record
 * arriving instead is stashed for the BIO layer to pick up. */
static gboolean
gx_send_plain_drain (FpiDeviceGoodix51A0 *self, const guint8 *body, gsize n,
                     gboolean *out_ack_seen, gboolean *out_tls_seen)
{
/* IRQ-silence polls, 10 ms apart, that count as silence after a response.
 * This is the dominant cost of a capture: each command in the sequence
 * pays it. Cut it too short and frame boundaries desynchronise, leaving the
 * sensor wedged in a state only a hard reset plus an spidev rebind recovers.
 *
 * Measured over 6 to 8 captures per setting:
 *   6 -> 1319 ms, no failures       (original value)
 *   4 -> 1136 ms, no failures       <- kept
 *   3 -> 1062 ms, no failures
 *   2 -> total failure, sensor wedged
 * We keep 4 rather than 3: shipping the value right next to the cliff would
 * leave no margin for load or temperature variation. */
#ifndef GX_DRAIN_SILENCE
#define GX_DRAIN_SILENCE 4
#endif
#ifndef GX_DRAIN_IRQ_POLL_MS
#define GX_DRAIN_IRQ_POLL_MS 10
#endif
#ifndef GX_GET_IMAGE_ATTEMPTS
#define GX_GET_IMAGE_ATTEMPTS 2
#endif

  static guint8 scratch[GOODIX_RX_MAX];
  int expected_plain_replies = 0;
  int attempts = body[0] == 0x20u ? GX_GET_IMAGE_ATTEMPTS : 1;
  int attempt;

  /* Reply counts observed stable across the GXFP51A0 capture path and matching
   * the command semantics. Commands not listed here retain silence-based
   * draining. GET_IMAGE remains special because its ACK/TLS ordering varies. */
  switch (body[0])
    {
    case 0x32u: expected_plain_replies = 1; break; /* FDT down */
    case 0x36u: expected_plain_replies = 2; break; /* FDT manual/data */
    case 0x50u: expected_plain_replies = 2; break; /* NAV */
    case 0x80u: expected_plain_replies = 1; break; /* register write */
    case 0x82u: expected_plain_replies = 2; break; /* register read */
    case 0xaeu: expected_plain_replies = 2; break; /* MCU state */
    default: break;
    }

  if (out_ack_seen)
    *out_ack_seen = FALSE;
  if (out_tls_seen)
    *out_tls_seen = FALSE;

  for (attempt = 1; attempt <= attempts; attempt++)
    {
      guint8 ty;
      gboolean ack_seen = FALSE;
      gboolean tls_seen = FALSE;
      int no_reply_miss_limit =
        (body[0] == 0x20u || body[0] == 0xaeu) ? 12 : 25;
      int r, got = 0, i, misses = 0;

      /* Capture commands are sent directly. The recipe carries explicit NOPs
       * at the positions observed on GXFP51A0; do not prepend one here. */
      if (!gx_write_frame (self, GOODIX_PKT_PLAIN, body, n))
        return FALSE;

      /* Windows sends capture-group NOP without waiting for an ACK.
       * Waiting for silence here costs ~250 ms because NOP intentionally has
       * no response.  The outer capture recipe still keeps its conservative
       * inter-command gap, so this removes only a known-empty drain. */
      if (body[0] == 0x00u)
        {
          fp_dbg ("drain cmd=00: no ACK expected; skip silence wait");
          return TRUE;
        }

      g_usleep (15000);

      for (i = 0; i < 120; i++)
        {
          errno = 0;
          if (gx51_wait_irq_gpio48 (self->irq_fd, GX_DRAIN_IRQ_POLL_MS) < 0)
            {
              if (errno != ETIMEDOUT)
                return FALSE;

              misses++;
              if (got && misses >= GX_DRAIN_SILENCE)
                break;
              if (!got && misses >= no_reply_miss_limit)
                break;
              continue;
            }

          r = gx_read_frame (self, &ty, scratch, sizeof scratch);
          if (r > 0 && ty == GOODIX_PKT_PLAIN)
            {
              guint8 ack_status = 0;

              got++;
              misses = 0;
              if (gxfp_parse_ack (scratch, r, body[0], &ack_status) &&
                  gxfp_ack_status_success (ack_status))
                ack_seen = TRUE;
              if (expected_plain_replies > 0 && got >= expected_plain_replies)
                {
                  fp_dbg ("drain cmd=%02x: expected %d replies received; finish",
                          body[0], expected_plain_replies);
                  break;
                }
              g_usleep (5000);
              continue;
            }
          if (r > 0 && ty == GOODIX_PKT_TLS)
            {
              memcpy (self->tls_rx, scratch, r);
              self->tls_rxlen = r;
              self->tls_rxpos = 0;
              tls_seen = TRUE;
              fp_dbg ("drain cmd=%02x -> stashed TLS record, %d bytes",
                      body[0], r);
              break;
            }

          misses++;
          if (got && misses >= GX_DRAIN_SILENCE)
            break;
          if (!got && misses >= no_reply_miss_limit)
            break;
        }

      fp_dbg ("drain cmd=%02x: %d cleartext reply/replies ack=%d tls=%d attempt=%d/%d",
              body[0], got, ack_seen, tls_seen, attempt, attempts);

      if (out_ack_seen && ack_seen)
        *out_ack_seen = TRUE;
      if (out_tls_seen && tls_seen)
        *out_tls_seen = TRUE;

      if (body[0] != 0x20u)
        return TRUE;

      /* Windows and the validated Linux background path both receive a
       * cleartext ACK for GET_IMAGE before the oversized TLS record. If neither
       * ACK nor TLS arrived, the command was swallowed. Replaying the identical
       * GET_IMAGE once is safe because FDT remains armed. Never replay once a
       * TLS record is already present: that would advance the client record
       * stream twice and desynchronise AES-GCM sequence numbers. */
      if (tls_seen || ack_seen)
        return TRUE;

      if (attempt < attempts)
        {
          self->capture_retry_seen = TRUE;
          fp_warn ("GXFP51A0 GET_IMAGE had no ACK/TLS; retrying attempt=%d/%d",
                   attempt + 1, attempts);
          g_usleep (8000 * self->timing_scale / 100);
        }
    }

  fp_warn ("GXFP51A0 GET_IMAGE failed: no ACK/TLS after %d attempts",
           attempts);
  gx_capture_transport_desync (self);
  return FALSE;
}

/* ------------------------------------------------------------------ */
/*  Transport glue: TLS records travel inside 0xB0 SPI frames          */
/* ------------------------------------------------------------------ */

static int
gx_bio_send (gpointer ctx, const guint8 *b, gsize l)
{
  FpiDeviceGoodix51A0 *self = ctx;

  gsize off = 0;

  /* One TLS record per 0xB0 frame. OpenSSL batches several records into a
   * single write — the ServerHello group comes out as one 121-byte call — but
   * the sensor expects exactly one record per frame and silently ignores a
   * frame carrying two. Split on the record headers rather than forwarding the
   * buffer as it arrives. */
  while (off + 5 <= l)
    {
      gsize rec = 5 + (((gsize) b[off + 3] << 8) | b[off + 4]);

      if (off + rec > l)
        break;                        /* partial record: should not happen */
      if (!gx_write_frame (self, GOODIX_PKT_TLS, b + off, rec))
        return -1;
      off += rec;
    }
  return (int) l;
}

static int
gx_bio_recv (gpointer ctx, guint8 *b, gsize l)
{
  FpiDeviceGoodix51A0 *self = ctx;
  int avail, take, i;
  guint8 ty;

  if (self->tls_rxpos >= self->tls_rxlen)
    {
      /* Buffer empty: pull fresh TLS frames, skipping cleartext ones. The
       * sensor takes a while to produce the image, hence the generous poll. */
      int r = -1;
      self->tls_rxlen = self->tls_rxpos = 0;
      for (i = 0; i < GX_TLS_IRQ_POLLS; i++)
        {
          /* Do not call gx_read_frame() while the line is quiet: its generic
           * 1200 ms wait would turn this intended 20 ms poll loop into a
           * multi-minute block.  TLS handshake records observed on reference MateBook
           * normally arrive in ~10-20 ms, while 4 s remains generous for a
           * genuinely delayed record. */
          errno = 0;
          if (gx51_wait_irq_gpio48 (self->irq_fd, GX_TLS_IRQ_POLL_MS) < 0)
            {
              if (errno != ETIMEDOUT)
                return -1;
              continue;
            }

          r = gx_read_frame (self, &ty, self->tls_rx, GOODIX_RX_MAX);
          if (r > 0 && ty == GOODIX_PKT_TLS)
            {
              fp_dbg ("bio_recv: TLS frame %d bytes (attempt %d)", r, i);
              break;
            }
          r = -1;
        }
      if (r <= 0)
        {
          fp_dbg ("bio_recv: no TLS frame (timed out)");
          return -1;
        }
      self->tls_rxlen = r;
      self->tls_rxpos = 0;
    }
  avail = self->tls_rxlen - self->tls_rxpos;
  take = (int) l < avail ? (int) l : avail;
  memcpy (b, self->tls_rx + self->tls_rxpos, take);
  self->tls_rxpos += take;
  return take;
}

/* ------------------------------------------------------------------ */
/*  Image decoding: six bytes carry four pixels, in interleaved order  */
/* ------------------------------------------------------------------ */


/* ------------------------------------------------------------------ */
/*  Init, handshake and frame capture                                  */
/* ------------------------------------------------------------------ */

/* Hardware reset. GPIO264 is active-HIGH reset on GXFP51A0: HIGH holds the
 * MCU in reset and LOW lets it run. First-contact hardware confirmation uses
 * HIGH for 300 ms, then LOW with a 600 ms settle; final state remains LOW. */
static void
gx_gpio_reset (FpiDeviceGoodix51A0 *self)
{
  (void) self;
  if (gx51_reset_gpio264 () < 0)
    fp_warn ("GXFP51A0: reviewed GPIO264 reset failed");
}




static gboolean
gx_target_read_body (FpiDeviceGoodix51A0 *self,
                     guint8                 *body,
                     gsize                   cap,
                     int                    *out_len)
{
  guint8 type = 0;
  int n = gx_read_frame (self, &type, body, cap);

  if (n <= 0 || type != GOODIX_PKT_PLAIN)
    return FALSE;
  if (out_len)
    *out_len = n;
  return TRUE;
}

static gboolean
gx_target_read_response (FpiDeviceGoodix51A0 *self,
                         guint8               *body,
                         gsize                 cap,
                         int                  *out_len)
{
  /* Proven on reference MateBook: response-bearing commands need the ACK IRQ cycle to
   * deassert before the response is armed. The validated probes use 8 ms. */
  g_usleep (8000 * self->timing_scale / 100);
  return gx_target_read_body (self, body, cap, out_len);
}

static gboolean
gx_target_send_ack (FpiDeviceGoodix51A0       *self,
                    const struct gxfp_target_packet *packet,
                    guint8                           command,
                    guint8                          *status)
{
  guint8 rx[128];
  guint8 type = 0;
  guint8 ack_status = 0;
  int attempt;

  for (attempt = 1; attempt <= GX_TARGET_ACK_ATTEMPTS; attempt++)
    {
      int n;

      /* GPIO48 is level-high.  Never start a new command while a previous
       * response still owns the line. */
      if (gx51_wait_irq_gpio48_low (self->irq_fd, 50) < 0)
        {
          fp_warn ("GXFP51A0 target ACK diagnostic: pre-write-irq-high cmd=0x%02x",
                   command);
          return FALSE;
        }

      if (!gx_write_frame (self, GOODIX_PKT_PLAIN,
                           packet->inner, packet->inner_len))
        {
          fp_warn ("GXFP51A0 target ACK diagnostic: write-failed cmd=0x%02x",
                   command);
          return FALSE;
        }

      /* Distinguish a completely swallowed command (no IRQ edge/level at all)
       * from a protocol error.  Only the former is safe to retry: register
       * writes and idle/config commands are idempotent when replayed with the
       * same bytes.  If any packet arrives, parsing/status errors are final. */
      errno = 0;
      if (gx51_wait_irq_gpio48 (self->irq_fd, GX_TARGET_ACK_IRQ_TIMEOUT_MS) < 0)
        {
          if (errno == ETIMEDOUT && attempt < GX_TARGET_ACK_ATTEMPTS)
            {
              fp_warn ("GXFP51A0 target ACK diagnostic: no-irq retry cmd=0x%02x attempt=%d/%d",
                       command, attempt, GX_TARGET_ACK_ATTEMPTS);
              g_usleep (8000 * self->timing_scale / 100);
              continue;
            }

          fp_warn ("GXFP51A0 target ACK diagnostic: ack-read-failed cmd=0x%02x",
                   command);
          return FALSE;
        }

      n = gx_read_frame (self, &type, rx, sizeof rx);
      if (n <= 0)
        {
          fp_warn ("GXFP51A0 target ACK diagnostic: ack-read-failed cmd=0x%02x",
                   command);
          return FALSE;
        }
      if (type != GOODIX_PKT_PLAIN)
        {
          fp_warn ("GXFP51A0 target ACK diagnostic: ack-type-failed cmd=0x%02x type=0x%02x",
                   command, type);
          return FALSE;
        }
      if (!gxfp_parse_ack (rx, n, command, &ack_status))
        {
          fp_warn ("GXFP51A0 target ACK diagnostic: ack-parse-failed cmd=0x%02x len=%d first=0x%02x",
                   command, n, n > 0 ? rx[0] : 0);
          return FALSE;
        }
      if (!gxfp_ack_status_success (ack_status))
        {
          fp_warn ("GXFP51A0 target ACK diagnostic: status-failed cmd=0x%02x status=0x%02x",
                   command, ack_status);
          return FALSE;
        }

      if (status)
        *status = ack_status;
      return TRUE;
    }

  return FALSE;
}

static bool
gx_factory_staging_read_cb (void *user, uint32_t selector,
                            uint32_t request_len, uint8_t *out,
                            size_t out_cap, size_t *out_len)
{
  FpiDeviceGoodix51A0 *self = user;
  struct gxfp_target_packet packet;
  guint8 rx[GXFP_MEM_READ_MAX + 16];
  guint8 discard[GXFP_MEM_READ_MAX];
  guint8 type = 0, status = 0;
  int n;

  if (!out || !out_len || request_len != GXFP_FACTORY_BODY_LEN ||
      out_cap < GXFP_FACTORY_STAGING_LEN ||
      !gxfp_build_mem_read (selector, request_len, &packet) ||
      !gx_write_frame (self, GOODIX_PKT_PLAIN,
                       packet.inner, packet.inner_len))
    return false;

  n = gx_read_frame (self, &type, rx, sizeof rx);
  if (n <= 0 || type != GOODIX_PKT_PLAIN ||
      !gxfp_parse_ack (rx, n, 0xf2, &status) ||
      !gxfp_ack_status_success (status))
    return false;

  for (unsigned int i = 0; i < 3; i++)
    {
      enum gxfp_mem_read_result result;

      g_usleep ((i == 0 ? 8000 : 5000) * self->timing_scale / 100);
      n = gx_read_frame (self, &type, rx, sizeof rx);
      if (n <= 0 || type != GOODIX_PKT_PLAIN)
        return false;
      if (gxfp_14115_parse_rejected_staging_response (
            rx, n, selector, request_len, out, out_cap, out_len))
        return *out_len == GXFP_FACTORY_STAGING_LEN;

      result = gxfp_classify_mem_read_response (
        rx, n, selector, request_len, discard);
      if (result != GXFP_MEM_READ_ECHO_ONLY)
        return false;
    }
  return false;
}

static bool
gx_factory_e4_sanity (FpiDeviceGoodix51A0 *self)
{
  struct gxfp_target_packet packet;
  guint8 rx[128], value[32];
  uint32_t dtype = 0;
  int n = 0;
  bool ok;

  ok = gxfp_build_factory_hash_read (&packet) &&
       gx_target_send_ack (self, &packet, 0xe4, NULL) &&
       gx_target_read_response (self, rx, sizeof rx, &n) &&
       gxfp_parse_factory_hash_response (rx, n, &dtype, value) &&
       dtype == 0x0000aaaau;
  OPENSSL_cleanse (value, sizeof value);
  return ok;
}

static void
gx_pmk_clear (FpiDeviceGoodix51A0 *self)
{
  OPENSSL_cleanse (self->psk, sizeof self->psk);
  self->psk_ready = FALSE;
  self->psk_from_cache = FALSE;
}


static gboolean
gx_pmk_cache_load (FpiDeviceGoodix51A0 *self)
{
  struct stat st;
  g_autofree gchar *data = NULL;
  gsize len = 0;
  g_autoptr(GError) error = NULL;

  if (g_stat (GX_PMK_CACHE_FILE, &st) != 0)
    return FALSE;

  if (!S_ISREG (st.st_mode) ||
      st.st_uid != geteuid () ||
      (st.st_mode & 0077) != 0)
    {
      fp_warn ("GXFP51A0 PMK cache rejected: owner/permissions are unsafe");
      return FALSE;
    }

  if (!g_file_get_contents (GX_PMK_CACHE_FILE, &data, &len, &error))
    {
      fp_warn ("GXFP51A0 PMK cache read failed: %s", error->message);
      return FALSE;
    }

  if (len != GOODIX_PSK_LEN)
    {
      fp_warn ("GXFP51A0 PMK cache rejected: invalid length");
      OPENSSL_cleanse (data, len);
      return FALSE;
    }

  memcpy (self->psk, data, GOODIX_PSK_LEN);
  OPENSSL_cleanse (data, len);
  self->psk_ready = TRUE;
  self->psk_from_cache = TRUE;
  fp_info ("GXFP51A0 PMK cache candidate loaded; TLS validation pending");
  return TRUE;
}


static gboolean
gx_pmk_cache_save (FpiDeviceGoodix51A0 *self)
{
  g_autoptr(GError) error = NULL;

  if (!self->psk_ready || !self->tls_up)
    return FALSE;

  if (!g_file_test (GX_PMK_CACHE_DIR, G_FILE_TEST_IS_DIR) &&
      g_mkdir_with_parents (GX_PMK_CACHE_DIR, 0700) != 0)
    {
      fp_warn ("GXFP51A0 PMK cache directory creation failed: %s",
               g_strerror (errno));
      return FALSE;
    }

  if (!g_file_set_contents_full (
        GX_PMK_CACHE_FILE,
        (const gchar *) self->psk,
        GOODIX_PSK_LEN,
        G_FILE_SET_CONTENTS_CONSISTENT | G_FILE_SET_CONTENTS_DURABLE,
        0600,
        &error))
    {
      fp_warn ("GXFP51A0 PMK cache save failed: %s", error->message);
      return FALSE;
    }

  if (g_chmod (GX_PMK_CACHE_FILE, 0600) != 0)
    {
      fp_warn ("GXFP51A0 PMK cache chmod failed: %s", g_strerror (errno));
      (void) g_unlink (GX_PMK_CACHE_FILE);
      return FALSE;
    }

  fp_info ("GXFP51A0 PMK cache saved after live TLS validation");
  return TRUE;
}


static gboolean
gx_factory_load_staging_pmk (FpiDeviceGoodix51A0 *self)
{
  guint8 pmk[GXFP_FACTORY_PMK_LEN];
  gboolean ok = FALSE;

  /* On 14115 the rejected F2 path can expose one boot-staged factory record.
   * A second selector is not required at runtime: the first-byte brute force
   * must produce exactly one marker=0x000d,len=0x30 candidate, and that
   * candidate is then validated by the real TLS handshake.  Keeping the
   * two-selector consensus code as offline research avoids coupling runtime
   * success to the IRQ/reply behavior of a second rejected F2 command. */
  if (!gxfp_factory_load_pmk_from_single_staging (
        gx_factory_staging_read_cb, self, pmk))
    {
      fp_warn ("GXFP51A0 PMK single-staging candidate invalid for this boot session");
      goto out;
    }

  /* Run E4 only after extraction: any earlier command can reuse staging. */
  if (!gx_factory_e4_sanity (self))
    {
      fp_warn ("GXFP51A0 PMK candidate recovered but E4 sanity failed");
      goto out;
    }

  memcpy (self->psk, pmk, sizeof pmk);
  self->psk_ready = TRUE;
  self->psk_from_cache = FALSE;
  fp_info ("GXFP51A0 PMK recovered from single rejected-read boot staging; TLS validation pending");
  ok = TRUE;

out:
  if (!ok)
    {
      gx_pmk_clear (self);
    }
  OPENSSL_cleanse (pmk, sizeof pmk);
  return ok;
}


static gboolean
gx_factory_acquire_staging_pmk (FpiDeviceGoodix51A0 *self, gboolean allow_cache)
{
  int attempt;

  if (allow_cache && gx_pmk_cache_load (self))
    return TRUE;

  for (attempt = 1; attempt <= GXFP_PMK_ACQUIRE_ATTEMPTS; attempt++)
    {
      gx_gpio_reset (self);
      fp_info ("GXFP51A0 PMK staging attempt %d/%d after hardware reset",
               attempt, GXFP_PMK_ACQUIRE_ATTEMPTS);

      if (gx_factory_load_staging_pmk (self))
        {
          if (attempt > 1)
            fp_info ("GXFP51A0 PMK staging recovered on attempt %d", attempt);
          return TRUE;
        }

      if (attempt < GXFP_PMK_ACQUIRE_ATTEMPTS)
        g_usleep (50000);
    }

  fp_warn ("GXFP51A0 PMK staging acquisition exhausted after %d boot sessions",
           GXFP_PMK_ACQUIRE_ATTEMPTS);
  return FALSE;
}

static gboolean
gx_read_fw_version_stage2e (FpiDeviceGoodix51A0 *self, gchar *out, gsize cap)
{
  static const guint8 a8[] = {
    GOODIX_CMD_FW_VERSION, 0x03, 0x00, 0x00, 0x00, 0xFF
  };
  guint8 rx[128], type = 0, status = 0;
  int n = 0;

  /* Exact post-reset boundary proven by reference MateBook Stage2E:
   * A8 -> ACK -> 8 ms -> A8 response.  No preceding NOP here. */
  if (!gx_write_frame (self, GOODIX_PKT_PLAIN, a8, sizeof a8))
    {
      fp_warn ("GXFP51A0 Stage2E A8 write failed");
      return FALSE;
    }

  n = gx_read_frame (self, &type, rx, sizeof rx);
  if (n <= 0 || type != GOODIX_PKT_PLAIN ||
      !gxfp_parse_ack (rx, n, GOODIX_CMD_FW_VERSION, &status) ||
      !gxfp_ack_status_success (status))
    {
      fp_warn ("GXFP51A0 Stage2E A8 ACK failed");
      return FALSE;
    }
  fp_info ("GXFP51A0 Stage2E A8 ACK accepted");

  g_usleep (8000 * self->timing_scale / 100);

  n = gx_read_frame (self, &type, rx, sizeof rx);
  if (n <= 3 || type != GOODIX_PKT_PLAIN ||
      rx[0] != GOODIX_CMD_FW_VERSION)
    {
      fp_warn ("GXFP51A0 Stage2E A8 response failed");
      return FALSE;
    }

  g_strlcpy (out, (const gchar *) rx + 3,
             MIN ((gsize) (n - 3) + 1, cap));
  fp_info ("GXFP51A0 Stage2E A8 response accepted");
  return TRUE;
}


static gboolean
gx_target_soft_reset (FpiDeviceGoodix51A0 *self)
{
  struct gxfp_target_packet packet;
  guint8 rx[128];
  uint32_t code = 0;
  int n = 0;

  if (!gxfp_build_soft_reset (&packet))
    {
      fp_warn ("GXFP51A0 A2 diagnostic: build-failed");
      return FALSE;
    }
  if (!gx_target_send_ack (self, &packet, 0xa2, NULL))
    {
      fp_warn ("GXFP51A0 A2 diagnostic: ack-failed");
      return FALSE;
    }
  fp_info ("GXFP51A0 A2 ACK accepted");

  if (!gx_target_read_response (self, rx, sizeof rx, &n))
    {
      fp_warn ("GXFP51A0 A2 diagnostic: response-read-failed");
      return FALSE;
    }
  if (!gxfp_parse_soft_reset_response (rx, n, &code))
    {
      fp_warn ("GXFP51A0 A2 diagnostic: response-parse-failed len=%d", n);
      return FALSE;
    }
  if (code != 0x010008u)
    {
      fp_warn ("GXFP51A0 A2 diagnostic: unexpected-code=0x%06x", code);
      return FALSE;
    }

  fp_info ("GXFP51A0 A2 reset code accepted: 0x%06x", code);
  return TRUE;
}

static gboolean
gx_target_configure (FpiDeviceGoodix51A0 *self)
{
  struct gxfp_target_packet packet;
  struct gxfp_target_calibration cal;
  guint8 rx[512];
  guint8 otp[64];
  guint8 config[GXFP_CONFIG_LEN];
  guint8 status = 0;
  uint16_t chip_id = 0;
  int n = 0;

  if (!gx_target_soft_reset (self))
    {
      fp_warn ("GXFP51A0 target init failed: soft-reset-1");
      return FALSE;
    }

  if (!gxfp_build_chip_id (&packet) ||
      !gx_target_send_ack (self, &packet, 0x82, NULL) ||
      !gx_target_read_response (self, rx, sizeof rx, &n) ||
      !gxfp_parse_chip_id_response (rx, n, &chip_id) ||
      chip_id != 0x2504u)
    {
      fp_warn ("GXFP51A0 target init failed: chip-id");
      return FALSE;
    }
  fp_info ("GXFP51A0 chip-id accepted: 0x%04x", chip_id);

  if (!gxfp_build_read_otp (&packet))
    {
      fp_warn ("GXFP51A0 target init failed: otp-build");
      return FALSE;
    }
  if (!gx_target_send_ack (self, &packet, 0xa6, NULL))
    {
      fp_warn ("GXFP51A0 target init failed: otp-ack");
      return FALSE;
    }
  fp_info ("GXFP51A0 OTP ACK accepted");
  if (!gx_target_read_response (self, rx, sizeof rx, &n))
    {
      fp_warn ("GXFP51A0 target init failed: otp-response-read");
      return FALSE;
    }
  if (!gxfp_parse_otp_response (rx, n, otp))
    {
      fp_warn ("GXFP51A0 target init failed: otp-response-parse len=%d", n);
      return FALSE;
    }
  if (!gxfp_derive_calibration (otp, &cal))
    {
      fp_warn ("GXFP51A0 target init failed: otp-validation");
      return FALSE;
    }
  fp_info ("GXFP51A0 OTP validated: len=%d tcode=%u fdt_delta=%u",
           n, cal.tcode, cal.fdt_delta);

  memcpy (config, GXFP_TARGET_BASE_CONFIG, sizeof config);
  if (!gxfp_patch_config (config, &cal) ||
      !gxfp_config_checksum_valid (config))
    {
      fp_warn ("GXFP51A0 target init failed: config-patch");
      return FALSE;
    }

  if (!gx_target_soft_reset (self))
    {
      fp_warn ("GXFP51A0 target init failed: soft-reset-2");
      return FALSE;
    }

  if (!gxfp_build_idle (&packet) ||
      !gx_target_send_ack (self, &packet, 0x70, &status))
    {
      fp_warn ("GXFP51A0 target init failed: idle");
      return FALSE;
    }

  if (!gxfp_build_reg_write (0x0220u, cal.dac_main, &packet) ||
      !gx_target_send_ack (self, &packet, 0x80, NULL))
    {
      fp_warn ("GXFP51A0 target init failed: dac-main");
      return FALSE;
    }
  if (!gxfp_build_reg_write (0x0236u, cal.dac1, &packet) ||
      !gx_target_send_ack (self, &packet, 0x80, NULL))
    {
      fp_warn ("GXFP51A0 target init failed: dac1");
      return FALSE;
    }
  if (!gxfp_build_reg_write (0x0238u, cal.dac2, &packet) ||
      !gx_target_send_ack (self, &packet, 0x80, NULL))
    {
      fp_warn ("GXFP51A0 target init failed: dac2");
      return FALSE;
    }
  if (!gxfp_build_reg_write (0x023au, cal.dac3, &packet) ||
      !gx_target_send_ack (self, &packet, 0x80, NULL))
    {
      fp_warn ("GXFP51A0 target init failed: dac3");
      return FALSE;
    }

  if (!gxfp_build_upload_config (config, &packet) ||
      !gx_target_send_ack (self, &packet, 0x90, NULL))
    {
      fp_warn ("GXFP51A0 target init failed: config-ack");
      return FALSE;
    }
  if (!gx_target_read_response (self, rx, sizeof rx, &n) ||
      !gxfp_parse_config_response (rx, n, &status) || status != 0x01u)
    {
      fp_warn ("GXFP51A0 target init failed: config-response");
      return FALSE;
    }

  self->target_cal = cal;
  self->have_target_cal = TRUE;
  fp_info ("GXFP51A0 target config accepted: chip=0x%04x tcode=%u "
           "fdt_delta=%u dac=0x%03x/%02x/%02x/%02x",
           chip_id, cal.tcode, cal.fdt_delta, cal.dac_main,
           cal.dac1, cal.dac2, cal.dac3);
  return TRUE;
}


/* reference MateBook now validates the 14115 rejected-read staging provider. Genuine
 * private-flash/RAM F2 remains closed; the reset is required so extraction
 * happens before another command can reuse the boot staging area. */
static gboolean
gx_upload_config_and_reqtls (FpiDeviceGoodix51A0 *self, gboolean allow_cache)
{
  guint8 ack[128], status = 0, type = 0;
  int n;

  if (!self->psk_ready)
    {
      gchar fw[64] = { 0 };

      if (!gx_factory_acquire_staging_pmk (self, allow_cache))
        return FALSE;

      /* Rejected F2 staging reads are intentionally outside the normal 14115
       * command flow. Keep the recovered PMK host-side, but return the MCU to a
       * pristine boot state before target init. The exact reference MateBook config probe
       * that passed starts a fresh hardware reset with A8 -> A2 -> chip-id ->
       * OTP, so reproduce that boundary here instead of continuing after F2/E4. */
      fp_info ("GXFP51A0 PMK retained; performing post-PMK reset before target init");
      gx_gpio_reset (self);
      if (!gx_read_fw_version_stage2e (self, fw, sizeof fw) ||
          g_strcmp0 (fw, "GF_ST411SEC_APP_14115") != 0)
        {
          fp_warn ("GXFP51A0 target init failed: post-PMK reset/A8");
          return FALSE;
        }
      fp_info ("GXFP51A0 post-PMK reset/A8 confirmed: %s", fw);
    }

  if (!gx_target_configure (self))
    {
      fp_warn ("GXFP51A0: target initialization/configuration failed");
      return FALSE;
    }

  if (!gx_send_plain_raw (self, GX_REQTLS, sizeof GX_REQTLS))
    return FALSE;
  n = gx_read_frame (self, &type, ack, sizeof ack);
  if (n <= 0 || type != GOODIX_PKT_PLAIN ||
      !gxfp_parse_ack (ack, n, 0xd0, &status) ||
      !gxfp_ack_status_success (status))
    {
      fp_warn ("GXFP51A0: D0 TLS request was not accepted");
      return FALSE;
    }

  return TRUE;
}


/* Establishes the TLS-PSK channel, with us as the server. */
static gboolean
gx_tls_handshake (FpiDeviceGoodix51A0 *self)
{
  g_autoptr(GError) err = NULL;
  guint8 ack[128], status = 0, type = 0;
  int n;

  if (!self->psk_ready)
    return FALSE;
  self->tls_rxlen = self->tls_rxpos = 0;
  g_clear_pointer (&self->tls, gx_tls_free);
  self->tls = gx_tls_new (self->psk, GOODIX_PSK_LEN, GOODIX_TLS_IDENTITY,
                          gx_bio_send, gx_bio_recv, self);
  if (!self->tls)
    {
      fp_warn ("cannot set up the TLS channel");
      return FALSE;
    }
  if (!gx_tls_handshake_run (self->tls, &err))
    {
      fp_warn ("%s", err->message);
      return FALSE;
    }

  /* Windows and the validated Stage3C path both confirm the completed
   * handshake back to the MCU with NOP -> D4. */
  if (!gx_send_plain_raw (self, GX_TLS_OK, sizeof GX_TLS_OK))
    {
      fp_warn ("GXFP51A0: failed to send TLS established D4");
      return FALSE;
    }
  n = gx_read_frame (self, &type, ack, sizeof ack);
  if (n <= 0 || type != GOODIX_PKT_PLAIN ||
      !gxfp_parse_ack (ack, n, 0xd4, &status) ||
      !gxfp_ack_status_success (status))
    {
      fp_warn ("GXFP51A0: TLS established D4 was not accepted");
      return FALSE;
    }

  fp_info ("GXFP51A0 TLS established ACK D4 accepted");
  fp_info ("GXFP51A0 PMK candidate validated by live TLS handshake");
  fp_info ("TLS-PSK session up (%s)", gx_tls_ciphersuite (self->tls));
  self->tls_up = TRUE;
  if (self->psk_from_cache)
    fp_info ("GXFP51A0 cached PMK validated by live TLS handshake");
  else
    (void) gx_pmk_cache_save (self);
  return TRUE;
}


static void
gx_tls_teardown (FpiDeviceGoodix51A0 *self)
{
  if (self->tls_up)
    {
      gx_tls_close (self->tls);
      self->tls_up = FALSE;
    }
  g_clear_pointer (&self->tls, gx_tls_free);
}

/* Exact 14115/51x7 capture recipes, as validated by the Linux imaging path.
 * 30 ms remains the default on the reference 2021 unit. Slower controllers can
 * learn a capture-only pacing multiplier after a real GET_IMAGE transport
 * desync; this is deliberately separate from TLS/init timing. */
#ifndef GX_SEQ_GAP_US
#define GX_SEQ_GAP_US 30000
#endif

static gboolean
gx_send_capture_recipe (FpiDeviceGoodix51A0 *self, gboolean background)
{
  struct gxfp_capture_recipe recipe;
  gboolean ok;
  gsize i;

  if (background)
    ok = self->have_target_cal &&
         gxfp_build_background_capture_recipe (&self->target_cal, &recipe);
  else
    ok = gxfp_build_finger_capture_recipe (&recipe);
  if (!ok)
    return FALSE;

  for (i = 0; i < recipe.count; i++)
    {
      const struct gxfp_target_packet *packet = &recipe.steps[i];
      gint64 t0 = g_get_monotonic_time ();

      if (!gx_send_plain_drain (self, packet->inner, packet->inner_len, NULL, NULL))
        return FALSE;
      fp_dbg ("chrono cmd=%02x drain=%ld us", packet->inner[0],
              (long) (g_get_monotonic_time () - t0));
      g_usleep (gx_capture_gap_us (self));
    }
  return TRUE;
}


/* Takes exactly one complete sensor->host TLS transport frame. A frame may
 * already have been stashed by gx_send_plain_drain(); otherwise wait for it. */
static int
gx_take_tls_frame (FpiDeviceGoodix51A0 *self, guint8 *rec, gsize cap)
{
  int raw, k;

  if (self->tls_rxlen > self->tls_rxpos)
    {
      raw = self->tls_rxlen - self->tls_rxpos;
      if ((gsize) raw > cap)
        return -1;
      memcpy (rec, self->tls_rx + self->tls_rxpos, raw);
      self->tls_rxlen = self->tls_rxpos = 0;
      return raw;
    }

  for (k = 0; k < GX_TLS_IRQ_POLLS; k++)
    {
      guint8 ty;

      errno = 0;
      if (gx51_wait_irq_gpio48 (self->irq_fd, GX_TLS_IRQ_POLL_MS) < 0)
        {
          if (errno != ETIMEDOUT)
            return -1;
          continue;
        }

      raw = gx_read_frame (self, &ty, rec, cap);
      if (raw > 0 && ty == GOODIX_PKT_TLS)
        return raw;
    }
  return -1;
}


static int
gx_retry_get_image_after_tls_timeout (FpiDeviceGoodix51A0 *self,
                                      guint8 *rec,
                                      gsize cap)
{
  struct gxfp_target_packet packet;
  gboolean ack_seen = FALSE;
  gboolean tls_seen = FALSE;

  if (!gxfp_build_get_image (&packet))
    return -1;

  self->capture_retry_seen = TRUE;
  fp_warn ("GXFP51A0 GET_IMAGE ACK arrived but TLS image timed out; retrying once");
  if (!gx_send_plain_drain (self, packet.inner, packet.inner_len,
                            &ack_seen, &tls_seen))
    {
      if (!self->capture_recovery_pending)
        gx_capture_transport_desync (self);
      return -1;
    }

  {
    int raw = gx_take_tls_frame (self, rec, cap);

    if (raw < 0 && !self->capture_recovery_pending)
      {
        fp_warn ("GXFP51A0 GET_IMAGE retry received no TLS image; "
                 "marking capture transport desynchronised");
        gx_capture_transport_desync (self);
      }
    return raw;
  }
}


/* The 51x7 reference requires an FDT-up image, NAV and final FDT-down after a
 * finger frame. The intermediate image record must be AUTHENTICATED/decrypted,
 * not merely discarded: AES-GCM record sequence numbers advance for every
 * sensor record, and skipping it would desynchronise the following capture. */
static gboolean
gx_send_capture_cleanup (FpiDeviceGoodix51A0 *self)
{
  struct gxfp_capture_recipe recipe;
  g_autofree guint8 *rec = g_malloc0 (GOODIX_RX_MAX);
  g_autofree guint8 *plain = g_malloc0 (GOODIX_RX_MAX);
  gboolean ok = FALSE;
  gsize i;

  if (!gxfp_build_capture_cleanup_recipe (&recipe))
    goto out;

  for (i = 0; i < recipe.count; i++)
    {
      const struct gxfp_target_packet *packet = &recipe.steps[i];

      if (!gx_send_plain_drain (self, packet->inner, packet->inner_len, NULL, NULL))
        goto out;

      if (packet->inner[0] == 0x20u)
        {
          int raw = gx_take_tls_frame (self, rec, GOODIX_RX_MAX);
          gssize got;

          if (raw < 0)
            raw = gx_retry_get_image_after_tls_timeout (self, rec, GOODIX_RX_MAX);

          got = raw > 0
                  ? gx_tls_decrypt_record (self->tls, rec, (gsize) raw,
                                           plain, GOODIX_RX_MAX)
                  : -1;
          if (got != (gssize) GXFP_IMAGE_PLAINTEXT_LEN)
            {
              fp_warn ("capture cleanup image record failed (%d raw, %ld plain)",
                       raw, (long) got);
              goto out;
            }
        }

      g_usleep (gx_capture_gap_us (self));
    }

  ok = TRUE;
out:
  OPENSSL_cleanse (rec, GOODIX_RX_MAX);
  OPENSSL_cleanse (plain, GOODIX_RX_MAX);
  return ok;
}


/* Captures one full image, assuming a TLS session is already up, and fills
 * px[GOODIX_IMG_PIXELS] with 12-bit samples. */
static gboolean
gx_capture_frame (FpiDeviceGoodix51A0 *self, guint16 *px, gboolean background)
{
  g_autofree guint8 *img = g_malloc (GOODIX_RX_MAX);
  int total = 0;

  self->capture_retry_seen = FALSE;
  gint64 tA = g_get_monotonic_time ();
  if (!gx_send_capture_recipe (self, background))
    return FALSE;
  fp_dbg ("timing: capture sequence %ld us",
           (long) (g_get_monotonic_time () - tA));

  /* The image arrives as one complete sensor application-data record. Keep
   * explicit record decryption here because capture drains/stashes the already
   * framed transport record and the client-read sequence is tracked explicitly.
   * The record has usually already been picked up while draining the capture
   * sequence; otherwise wait for it. */
  {
    g_autofree guint8 *rec = g_malloc (GOODIX_RX_MAX);
    int raw = gx_take_tls_frame (self, rec, GOODIX_RX_MAX);
    gssize got;

    if (raw < 0)
      raw = gx_retry_get_image_after_tls_timeout (self, rec, GOODIX_RX_MAX);

    got = raw > 0 ? gx_tls_decrypt_record (self->tls, rec, (gsize) raw,
                                           img, GOODIX_RX_MAX) : -1;
    if (got < 0)
      {
        fp_warn ("cannot decrypt the image record (%d raw bytes)", raw);
        return FALSE;
      }
    total = (int) got;
  }
  fp_dbg ("timing: whole capture %ld us (image %d bytes)",
           (long) (g_get_monotonic_time () - tA), total);
  if (total != (int) GXFP_IMAGE_PLAINTEXT_LEN)
    {
      fp_warn ("unexpected GXFP51A0 image plaintext: %d bytes (expected %u)",
               total, (unsigned) GXFP_IMAGE_PLAINTEXT_LEN);
      return FALSE;
    }
  if (!gxfp_decode_image_plaintext (img, (gsize) total, px))
    {
      fp_warn ("cannot decode GXFP51A0 88x80 transport raster");
      return FALSE;
    }

  /* Preserve a successfully decoded finger frame before cleanup.  The cleanup
   * is required to keep TLS record sequencing healthy for subsequent captures,
   * but a cleanup failure must not destroy the diagnostic evidence from the
   * frame we already authenticated and decoded.  gx_dump_capture() is inert
   * unless the private dump directory exists. */
#ifdef GXFP51A0_DEVELOPER
  if (!background)
    gx_dump_capture (self, px);
#endif

  if (!background && !gx_send_capture_cleanup (self))
    {
      fp_warn ("GXFP51A0 post-capture cleanup failed");
      return FALSE;
    }

  if (!background)
    gx_capture_pacing_success (self);
  return TRUE;
}


static int
gx_cmp_dbl (const void *a, const void *b)
{
  double x = *(const double *) a - *(const double *) b;
  return (x > 0) - (x < 0);
}






/* Moyenne n trames en un tableau de pixels. */
static gboolean
gx_capture_avg (FpiDeviceGoodix51A0 *self, int nframes, guint16 *avg)
{
  g_autofree guint32 *acc = g_malloc0 (sizeof (guint32) * GOODIX_IMG_PIXELS);
  guint16 px[GOODIX_IMG_PIXELS];
  int got = 0, f, i;

  for (f = 0; f < nframes; f++)
    {
      if (!gx_capture_frame (self, px, TRUE))
        {
          if (self->capture_recovery_pending)
            return FALSE;
          continue;
        }
      for (i = 0; i < GOODIX_IMG_PIXELS; i++)
        acc[i] += px[i];
      got++;
    }
  if (!got)
    return FALSE;
  for (i = 0; i < GOODIX_IMG_PIXELS; i++)
    avg[i] = acc[i] / got;
  return TRUE;
}

/* ------------------------------------------------------------------ */
/*  Device life cycle: open / close                                    */
/* ------------------------------------------------------------------ */



/* Native finger detection: six 16-bit values, one per sensor zone, in about
 * 33 ms — some 70 times faster than capturing an image. A finger pulls those
 * values DOWN by roughly 100 counts (around 335/371/361 idle against
 * 229/269/275 with a finger), which is what makes cheap polling possible. */
#define GX_FDT_PROBE_ATTEMPTS 3
#define GX_FDT_IRQ_TIMEOUT_MS 100

static int
gx_fdt_probe (FpiDeviceGoodix51A0 *self, int *out_zones)
{
  struct gxfp_target_packet packet;
  guint8 rx[256], ty, ack_status, touchflag;
  guint16 zones[GXFP_FDT_ZONE_COUNT];
  int attempt, n, k;

  if (!gxfp_build_fdt_probe (&packet))
    return -1;

  for (attempt = 1; attempt <= GX_FDT_PROBE_ATTEMPTS; attempt++)
    {
      const gchar *stage = "send";

      /* FDT manual is idempotent and Windows reissues it repeatedly while
       * building the baseline. A missing IRQ here is therefore recoverable:
       * retry the complete command, but never spin indefinitely. */
      if (!gx_send_plain_raw (self, packet.inner, packet.inner_len))
        return -1;

      g_usleep (15000 * self->timing_scale / 100);

      stage = "ack";
      errno = 0;
      if (gx51_wait_irq_gpio48 (self->irq_fd, GX_FDT_IRQ_TIMEOUT_MS) < 0)
        goto retry;

      n = gx_read_frame (self, &ty, rx, sizeof rx);
      if (n <= 0 || ty != GOODIX_PKT_PLAIN ||
          !gxfp_parse_ack (rx, (size_t) n, 0x36u, &ack_status) ||
          !gxfp_ack_status_success (ack_status))
        goto retry;

      g_usleep (8000 * self->timing_scale / 100);

      stage = "response";
      errno = 0;
      if (gx51_wait_irq_gpio48 (self->irq_fd, GX_FDT_IRQ_TIMEOUT_MS) < 0)
        goto retry;

      n = gx_read_frame (self, &ty, rx, sizeof rx);
      if (n <= 0 || ty != GOODIX_PKT_PLAIN ||
          !gxfp_parse_fdt_response (rx, (size_t) n, &touchflag, zones))
        goto retry;

      for (k = 0; k < (int) GXFP_FDT_ZONE_COUNT; k++)
        out_zones[k] = (int) zones[k];

      return 0;

retry:
      fp_warn ("GXFP51A0 FDT probe retry: stage=%s attempt=%d/%d",
               stage, attempt, GX_FDT_PROBE_ATTEMPTS);
      if (attempt < GX_FDT_PROBE_ATTEMPTS)
        {
          /* Give a late/stale transaction a small quiesce window before
           * reissuing the same idempotent FDT-manual command. */
          g_usleep (10000 * self->timing_scale / 100);
        }
    }

  return -1;
}

/* Mean of the six exact-target FDT zones: an absolute test needing no baseline. */
static int
gx_fdt_mean (const int *v)
{
  int k, s = 0;
  for (k = 0; k < (int) GXFP_FDT_ZONE_COUNT; k++)
    s += v[k];
  return s / (int) GXFP_FDT_ZONE_COUNT;
}

/* Total drop against the baseline; above the threshold means a finger. */
static int
gx_fdt_drop (const int *base, const int *cur)
{
  int k, d = 0;
  for (k = 0; k < (int) GXFP_FDT_ZONE_COUNT; k++)
    d += base[k] - cur[k];
  return d / (int) GXFP_FDT_ZONE_COUNT;
}

/* ------------------------------------------------------------------ */
/*  Enrolment and verification, using local descriptors instead of the */
/*  NBIS pipeline.                                                     */
/*                                                                     */
/*  FpImageDevice mandates NBIS (minutiae plus bozorth3), which this    */
/*  tiny active area cannot reliably feed the stock NBIS pipeline.     */
/*  far below what reliable matching needs, and bozorth3 scored zero    */
/*  every time. Hence deriving straight from FpDevice and implementing  */
/*  enrol and verify against the descriptor matcher in goodix_sift.c.   */
/* ------------------------------------------------------------------ */

/* SIGFM score gates.
 *
 * These are candidate values, not security claims.  The release is only
 * promotable after a labelled genuine/impostor corpus shows a clear margin.
 * External small-sensor SIGFM drivers use runtime gates around 100-150; start
 * at the conservative low end until this exact 80x64 target is measured. */
#define GX_MATCH_THRESHOLD            7
#define GX_MIN_CAPTURE_KEYPOINTS     25

/* One user-visible press is one biometric sample.  Hidden second captures made
 * the previous enrollment slow and did not add controlled diversity. */
#define GX_ENROLL_STAGES             20
#define GX_VIEWS_PER_STAGE            1
#define GX_ENROLL_VIEWS              GX_ENROLL_STAGES

/* Reads the firmware version, which also proves the SPI dialogue works. */
static gboolean
gx_wait_plain_ack_for (FpiDeviceGoodix51A0 *self, guint8 command)
{
  guint8 rx[128], type = 0;
  int n = gx_read_frame (self, &type, rx, sizeof rx);

  return n >= 5 &&
         type == GOODIX_PKT_PLAIN &&
         rx[0] == 0xB0 &&
         rx[3] == command;
}

static gboolean
gx_driverstate_install_windows (FpiDeviceGoodix51A0 *self)
{
  int wrapper, attempt;

  /* Windows GF3658 first-contact: NOP -> 5 ms -> DriverState Install. */
  if (!gx_write_frame (self, GOODIX_PKT_PLAIN,
                       GX_AMORCE, sizeof GX_AMORCE))
    return FALSE;

  g_usleep (5000);

  for (wrapper = 0; wrapper < 2; wrapper++)
    for (attempt = 0; attempt < 2; attempt++)
      {
        if (!gx_write_frame (self, GOODIX_PKT_PLAIN,
                             GX_ENABLE, sizeof GX_ENABLE))
          return FALSE;
        if (gx_wait_plain_ack_for (self, 0x96))
          return TRUE;
      }

  return FALSE;
}

static gboolean
gx_read_fw_version_once (FpiDeviceGoodix51A0 *self, gchar *out, gsize cap)
{
  static const guint8 nop[] = {
    0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA5
  };
  static const guint8 a8[] = {
    GOODIX_CMD_FW_VERSION, 0x03, 0x00, 0x00, 0x00, 0xFF
  };
  guint8 rx[128], cached[128];
  guint8 ty = 0, cached_ty = 0;
  int n, cached_n = 0;
  int send_index, read_index;
  gboolean acked = FALSE;

  if (!gx_write_frame (self, GOODIX_PKT_PLAIN, nop, sizeof nop))
    return FALSE;
  g_usleep (5000);

  for (send_index = 0; send_index < 2 && !acked; send_index++)
    {
      cached_n = 0;
      cached_ty = 0;

      if (!gx_write_frame (self, GOODIX_PKT_PLAIN, a8, sizeof a8))
        return FALSE;

      for (read_index = 0; read_index < 2; read_index++)
        {
          n = gx_read_frame (self, &ty, rx, sizeof rx);
          if (n <= 0)
            break;
          if (ty != GOODIX_PKT_PLAIN)
            continue;

          if (n >= 5 && rx[0] == 0xB0 && rx[3] == GOODIX_CMD_FW_VERSION)
            {
              acked = TRUE;
              break;
            }

          if (n > 3 && rx[0] != 0xB0)
            {
              memcpy (cached, rx, n);
              cached_n = n;
              cached_ty = ty;
            }
        }
    }

  if (!acked)
    return FALSE;

  if (cached_n > 3 && cached_ty == GOODIX_PKT_PLAIN)
    {
      g_strlcpy (out, (const gchar *) cached + 3,
                 MIN ((gsize) (cached_n - 3) + 1, cap));
      return TRUE;
    }

  n = gx_read_frame (self, &ty, rx, sizeof rx);
  if (n <= 3 || ty != GOODIX_PKT_PLAIN || rx[0] == 0xB0)
    return FALSE;

  g_strlcpy (out, (const gchar *) rx + 3,
             MIN ((gsize) (n - 3) + 1, cap));
  return TRUE;
}

static gboolean
gx_read_fw_version (FpiDeviceGoodix51A0 *self, gchar *out, gsize cap)
{
  int attempt;

  /* GetEvkVersionWithRetry: three initial tries. The caller owns the
   * reviewed HardResetMcu fallback and one final try. */
  for (attempt = 0; attempt < 3; attempt++)
    if (gx_read_fw_version_once (self, out, cap))
      return TRUE;

  return FALSE;
}


/* ------------------------------------------------------------------ */
/*  Session: TLS setup, background frame, detection baseline           */
/* ------------------------------------------------------------------ */

/* Learned protocol-timing multiplier, remembered across opens.
 *
 * timing_scale grows within a session when the sensor loses sync (see below),
 * but resets to nominal on every open — so a consistently slow unit paid one
 * failed handshake at the start of every session. Persisting the last value
 * that WORKED skips that: the next open starts at the timing this unit is known
 * to need. It lives in fprintd's state directory (the only writable path under
 * ProtectSystem=strict), is device- not user-scoped, and is a single integer.
 * Delete the file to reset the learned value. */
#define GX_TIMING_FILE "/var/lib/fprint/.goodix51a0-timing"

static int
gx_timing_load (void)
{
  g_autofree gchar *txt = NULL;
  int v;

  if (!g_file_get_contents (GX_TIMING_FILE, &txt, NULL, NULL))
    return 100;
  v = atoi (txt);
  return (v >= 100 && v <= 300) ? v : 100;   /* clamp; ignore a garbled file */
}

static void
gx_timing_save (int scale)
{
  g_autofree gchar *txt = g_strdup_printf ("%d\n", scale);

  if (!g_file_set_contents (GX_TIMING_FILE, txt, -1, NULL))
    fp_warn ("could not persist timing scale to %s", GX_TIMING_FILE);
  else
    g_chmod (GX_TIMING_FILE, 0600);
}

/* Capture pacing is learned independently from target/TLS timing. The nominal
 * 30 ms gap remains the fast path. A slow unit only moves upward after an
 * actual GET_IMAGE transport loss (two no-ACK/TLS attempts), and an elevated
 * value is persisted only after a complete finger frame + cleanup succeeds. */
#define GX_CAPTURE_TIMING_FILE "/var/lib/fprint/.goodix51a0-capture-timing"
#define GX_CAPTURE_SCALE_MIN 100
#define GX_CAPTURE_SCALE_MAX 300
#define GX_CAPTURE_SCALE_STEP 50
#define GX_CAPTURE_CLEAN_DECAY_STREAK 16

static int
gx_capture_timing_load (void)
{
  g_autofree gchar *txt = NULL;
  int v;

  if (!g_file_get_contents (GX_CAPTURE_TIMING_FILE, &txt, NULL, NULL))
    return GX_CAPTURE_SCALE_MIN;
  v = atoi (txt);
  return (v >= GX_CAPTURE_SCALE_MIN && v <= GX_CAPTURE_SCALE_MAX)
           ? v : GX_CAPTURE_SCALE_MIN;
}

static void
gx_capture_timing_save (int scale)
{
  g_autofree gchar *txt = g_strdup_printf ("%d\n", scale);

  if (!g_file_set_contents (GX_CAPTURE_TIMING_FILE, txt, -1, NULL))
    fp_warn ("could not persist capture timing scale to %s",
             GX_CAPTURE_TIMING_FILE);
  else
    g_chmod (GX_CAPTURE_TIMING_FILE, 0600);
}

static guint
gx_capture_gap_us (FpiDeviceGoodix51A0 *self)
{
  int scale = CLAMP (self->capture_gap_scale,
                     GX_CAPTURE_SCALE_MIN, GX_CAPTURE_SCALE_MAX);

  return (guint) ((guint64) GX_SEQ_GAP_US * (guint) scale / 100u);
}

static void
gx_capture_transport_desync (FpiDeviceGoodix51A0 *self)
{
  int previous = MAX (self->capture_gap_scale, GX_CAPTURE_SCALE_MIN);

  self->capture_clean_streak = 0;
  self->capture_recovery_pending = TRUE;

  /* S3/hibernate destroys the MCU session.  A desync while rebuilding that
   * lifecycle boundary says nothing about the steady-state capture gap, so it
   * must never ratchet the persistent pacing value upward. */
  if (self->capture_pacing_suppressed)
    {
      fp_warn ("GXFP51A0 lifecycle recovery desync: pacing remains %d%% "
               "(%u us gap); full MCU/session recovery required",
               previous, gx_capture_gap_us (self));
      return;
    }

  self->capture_gap_scale =
    MIN (previous + GX_CAPTURE_SCALE_STEP, GX_CAPTURE_SCALE_MAX);

  fp_warn ("GXFP51A0 capture transport desync: pacing %d%% -> %d%% "
           "(%u us gap); full MCU/session recovery required",
           previous, self->capture_gap_scale, gx_capture_gap_us (self));
}

static void
gx_capture_pacing_success (FpiDeviceGoodix51A0 *self)
{
  if (self->capture_gap_scale > self->capture_gap_saved)
    {
      gx_capture_timing_save (self->capture_gap_scale);
      self->capture_gap_saved = self->capture_gap_scale;
      fp_info ("GXFP51A0 learned capture pacing %d%% persisted after "
               "successful finger capture", self->capture_gap_scale);
    }

  if (self->capture_retry_seen)
    {
      self->capture_clean_streak = 0;
      self->capture_retry_seen = FALSE;
      return;
    }

  if (self->capture_gap_scale > GX_CAPTURE_SCALE_MIN)
    {
      self->capture_clean_streak++;
      if (self->capture_clean_streak >= GX_CAPTURE_CLEAN_DECAY_STREAK)
        {
          int previous = self->capture_gap_scale;

          self->capture_gap_scale =
            MAX (GX_CAPTURE_SCALE_MIN,
                 previous - GX_CAPTURE_SCALE_STEP);
          gx_capture_timing_save (self->capture_gap_scale);
          self->capture_gap_saved = self->capture_gap_scale;
          self->capture_clean_streak = 0;
          fp_info ("GXFP51A0 capture pacing decayed after %d clean captures: "
                   "%d%% -> %d%% (%u us gap)",
                   GX_CAPTURE_CLEAN_DECAY_STREAK, previous,
                   self->capture_gap_scale, gx_capture_gap_us (self));
        }
    }
  else
    self->capture_clean_streak = 0;

  self->capture_retry_seen = FALSE;
}

/* Establishes the TLS channel. This is the expensive step, about half a
 * second, and it does not depend on when the finger arrives — so it can be
 * done once and kept. */
static gboolean
gx_tls_session (FpiDeviceGoodix51A0 *self)
{
  int att;
  gboolean diagnostic = g_getenv ("GXFP_DIAGNOSTIC_ONESHOT") != NULL;
  gboolean capture_diagnostic = g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE") != NULL;
  int max_attempts = capture_diagnostic ? 2 : (diagnostic ? 1 : 5);

  if (self->tls_up)
    return TRUE;

  for (att = 1; att <= max_attempts && !self->tls_up; att++)
    {
      GCancellable *c = fpi_device_get_cancellable (FP_DEVICE (self));

      if (c && g_cancellable_is_cancelled (c))
        {
          fp_info ("TLS setup cancelled by the caller");
          break;
        }

      if (gx_upload_config_and_reqtls (self, TRUE) &&
          gx_tls_handshake (self))
        break;

      gx_tls_teardown (self);

      /* A PMK that reached D4 in an earlier session is durable trusted state.
       * A transport/configuration/handshake failure later does NOT prove that
       * the key changed, so never unlink the cache on a transient failure. */
      if (self->psk_from_cache && diagnostic)
        {
          if (att >= max_attempts)
            {
              fp_warn ("GXFP51A0 cached PMK retained after failed session; diagnostic mode will not fall back to staging");
              break;
            }
          fp_warn ("GXFP51A0 cached PMK retained after failed diagnostic TLS attempt; retrying clean target init");
        }

      /* Self-healing on desync. The protocol delays are tuned to the author's
       * unit and sit right at the edge; a different SPI controller can be
       * slower and lose sync. Only successful timing values are persisted. */
      if (self->timing_scale < 300)
        {
          self->timing_scale = MIN (self->timing_scale + 50, 300);
          fp_info ("handshake failed; loosening protocol timings to %d%%",
                   self->timing_scale);
        }

      {
        gchar fw[64] = { 0 };

        gx_gpio_reset (self);
        if (!gx_read_fw_version_stage2e (self, fw, sizeof fw) ||
            g_strcmp0 (fw, "GF_ST411SEC_APP_14115") != 0)
          {
            fp_warn ("GXFP51A0 TLS retry reset/A8 failed");
            break;
          }
        fp_info ("GXFP51A0 TLS retry reset/A8 confirmed: %s", fw);
      }
    }

  /* Production-only stale-cache recovery. Keep the validated cache file on
   * disk while probing fresh boot staging. If the newly recovered candidate
   * reaches D4, gx_pmk_cache_save() atomically replaces the old file. If it
   * does not, the last-known-good cache remains available for a later boot. */
  if (!self->tls_up && !diagnostic && self->psk_from_cache)
    {
      fp_warn ("GXFP51A0 cached PMK could not establish TLS; trying fresh staging without deleting validated cache");
      gx_pmk_clear (self);

      if (gx_upload_config_and_reqtls (self, FALSE) &&
          gx_tls_handshake (self))
        {
          fp_info ("GXFP51A0 fresh staging replaced stale cache after live TLS validation");
        }
      else
        {
          gx_tls_teardown (self);
          fp_warn ("GXFP51A0 fresh staging fallback failed; validated cache file retained");
        }
    }

  if (!self->tls_up)
    fp_warn ("no TLS session after %d/%d attempts; if this persists the sensor "
             "needs a full recovery (long reset plus an spidev rebind)",
             att - 1, max_attempts);
  else if (self->timing_scale > self->timing_saved)
    {
      gx_timing_save (self->timing_scale);
      self->timing_saved = self->timing_scale;
      fp_info ("learned timing scale %d%% persisted", self->timing_scale);
    }

  return self->tls_up;
}

/* Refreshes the background frame and the detection baseline.
 *
 * This must happen JUST BEFORE each operation, unlike the TLS setup above: the
 * sensor's baseline level drifts, and the whole chain rests on the
 * background-minus-finger difference. A background captured too early yields a
 * distorted image and collapses the score — measured at 11 to 28 matches with
 * a fresh background against 2 to 4 with one a few tens of seconds old. */

/* How long to wait for the finger to be lifted before taking the background. */
#define GX_BG_WAIT_MS 2000

/* One-shot diagnostic UX: give the operator time to react to the explicit
 * "sensor clear" prompt before measuring anything. Then reject a calibration
 * whose mean moved too far from the just-observed no-finger anchor. */
#define GX_DIAG_CLEAR_GRACE_SEC 3
#define GX_DIAG_BASELINE_MAX_DRIFT 20
#define GX_DIAG_BASELINE_ATTEMPTS 4
#define GX_CLEAR_WAIT_MS 15000

static gboolean
gx_wait_clean_anchor (FpiDeviceGoodix51A0 *self, int *out_mean)
{
  int cur[GXFP_FDT_ZONE_COUNT];
  int waited = 0;
  gboolean warned = FALSE;

  while (waited <= GX_CLEAR_WAIT_MS)
    {
      GCancellable *c = fpi_device_get_cancellable (FP_DEVICE (self));

      if (c && g_cancellable_is_cancelled (c))
        return FALSE;

      if (gx_fdt_probe (self, cur) == 0)
        {
          int mean = gx_fdt_mean (cur);

          if (mean >= GOODIX_FDT_ABS)
            {
              *out_mean = mean;
              fp_info ("GXFP51A0 clean calibration anchor: mean=%d", mean);
              return TRUE;
            }

          if (!warned)
            {
              fp_warn ("GXFP51A0 calibration waiting for sensor clear: mean=%d floor=%d",
                       mean, GOODIX_FDT_ABS);
              warned = TRUE;
            }
        }

      g_usleep (200 * 1000);
      waited += 200;
    }

  fp_warn ("GXFP51A0 calibration could not find a clean sensor within %d ms",
           GX_CLEAR_WAIT_MS);
  return FALSE;
}

static gboolean
gx_wait_sensor_clear (FpiDeviceGoodix51A0 *self,
                      int off_anchor_mean,
                      int *out_mean)
{
  int cur[GXFP_FDT_ZONE_COUNT];
  int waited = 0;
  gboolean warned = FALSE;

  while (waited <= GX_CLEAR_WAIT_MS)
    {
      if (gx_fdt_probe (self, cur) == 0)
        {
          int mean = gx_fdt_mean (cur);

          if (off_anchor_mean - mean <= GX_DIAG_BASELINE_MAX_DRIFT)
            {
              if (out_mean)
                *out_mean = mean;
              if (warned)
                fp_info ("GXFP51A0 sensor clear again: mean=%d anchor=%d",
                         mean, off_anchor_mean);
              return TRUE;
            }

          if (!warned)
            {
              fp_warn ("GXFP51A0 calibration waiting for sensor clear: mean=%d anchor=%d",
                       mean, off_anchor_mean);
              warned = TRUE;
            }
        }

      g_usleep (200 * 1000);
      waited += 200;
    }

  fp_warn ("GXFP51A0 sensor still not clear after %d ms",
           GX_CLEAR_WAIT_MS);
  return FALSE;
}

static gboolean
gx_diag_press_countdown (FpiDeviceGoodix51A0 *self, int off_anchor_mean)
{
  int cur[GXFP_FDT_ZONE_COUNT];
  int q;

  for (;;)
    {
      gboolean restart = FALSE;

      fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_GET_READY: keep finger OFF until zero");
      for (q = 3; q > 0; q--)
        {
          fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_PRESS_IN_%d", q);
          g_usleep (G_USEC_PER_SEC);

          if (gx_fdt_probe (self, cur) == 0)
            {
              int mean = gx_fdt_mean (cur);

              if (off_anchor_mean - mean > GX_DIAG_BASELINE_MAX_DRIFT)
                {
                  fp_warn ("GXFP51A0 CAPTURE_DIAGNOSTIC_COUNTDOWN_RESTART: REMOVE_FINGER mean=%d anchor=%d",
                           mean, off_anchor_mean);
                  if (!gx_wait_sensor_clear (self, off_anchor_mean, NULL))
                    return FALSE;
                  restart = TRUE;
                  break;
                }
            }
        }

      if (restart)
        continue;

      fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_PRESS_NOW: PRESS_AND_HOLD_NOW");
      return TRUE;
    }
}

static gboolean
gx_prepare_capture_context_once (FpiDeviceGoodix51A0 *self,
                                 gboolean capture_diagnostic)
{
  int q, k;
  int off_anchor_mean = -1;

  if (!gx_tls_session (self))
    return FALSE;


  /* The sensor drives GPIO48 level-high while a response is pending. The
   * first background capture must not race the tail of the TLS handshake:
   * wait for a proven idle-low boundary, then give the MCU a short quiesce
   * window before starting the capture recipe. This only runs on cold/context
   * preparation; the normal warm Claim path never pays this delay. */
  if (gx51_wait_irq_gpio48_low (self->irq_fd, 250) < 0)
    {
      fp_warn ("GXFP51A0 TLS settled but IRQ did not return low before calibration");
      return FALSE;
    }
  g_usleep (100 * 1000);

  if (capture_diagnostic)
    {
      fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_PREPARING_BACKGROUND: KEEP_FINGER_OFF_SENSOR");
      fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_CLEAR_SENSOR: REMOVE_FINGER_NOW");
      for (q = GX_DIAG_CLEAR_GRACE_SEC; q > 0; q--)
        {
          fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_CALIBRATION_STARTS_IN_%d", q);
          g_usleep (G_USEC_PER_SEC);
        }
    }

  self->bg_dirty = FALSE;

  /* Both the background and the detection baseline are only meaningful with
   * the finger LIFTED. A finger left resting on the sensor when the operation
   * starts ends up in the background, the difference then cancels out, and the
   * capture is worthless — the observed symptom being verifications collapsing
   * from about 100 matches to 6 with no change in how the finger was placed.
   *
   * So take the background, ask the sensor whether it saw a finger, and redo it
   * if so. Background first, detection second, matching the order the rest of
   * the driver uses.
   *
   * The presence test here is the ABSOLUTE one, the only usable choice, since
   * the relative baseline is precisely what we are about to establish. */
  if (!self->bg_frame)
    self->bg_frame = g_malloc (sizeof (guint16) * GOODIX_IMG_PIXELS);

  {
    int cur[GXFP_FDT_ZONE_COUNT];
    gint64 t0 = g_get_monotonic_time ();

    /* Production and diagnostics use the same invariant: calibration starts
     * only from a proven finger-off sample. The previous production path used
     * a 2 s timeout and then accepted a contaminated background anyway; on
     * reference MateBook that learned idle≈211 while the true finger-off level is≈353,
     * making every subsequent press invisible. Never do that. */
    if (!gx_wait_clean_anchor (self, &off_anchor_mean))
      return FALSE;

    if (capture_diagnostic)
      fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_CLEAR_SENSOR_ANCHOR: mean=%d",
               off_anchor_mean);

    for (;;)
      {
        int clear_mean = off_anchor_mean;
        int mean;

        if (!gx_wait_sensor_clear (self, off_anchor_mean, &clear_mean))
          return FALSE;
        if (clear_mean > off_anchor_mean)
          off_anchor_mean = clear_mean;

        if (!gx_capture_avg (self, GOODIX_BG_FRAMES, self->bg_frame))
          return FALSE;

        /* A finger may land during the ~2 s background capture. Reject that
         * frame and wait for release rather than baking the finger into the
         * reference image. */
        if (gx_fdt_probe (self, cur) != 0)
          return FALSE;

        mean = gx_fdt_mean (cur);
        if (mean > off_anchor_mean)
          off_anchor_mean = mean;

        if (off_anchor_mean - mean <= GX_DIAG_BASELINE_MAX_DRIFT)
          break;

        fp_warn ("GXFP51A0 background contaminated by touch: mean=%d anchor=%d; discarding",
                 mean, off_anchor_mean);
        if (!gx_wait_sensor_clear (self, off_anchor_mean, NULL))
          return FALSE;
      }

    fp_info ("session ready in %d ms",
             (int) ((g_get_monotonic_time () - t0) / 1000));
  }

  /* Detection baseline. In one-shot diagnostic mode, validate it against the
   * no-finger anchor. If the user touched while those four probes were being
   * collected, discard them and retry instead of learning the finger as idle. */
  {
    int attempt;

    self->have_fdt = FALSE;
    for (attempt = 1; attempt <= GX_DIAG_BASELINE_ATTEMPTS; attempt++)
      {
        int t[GXFP_FDT_ZONE_COUNT];
        int acc[GXFP_FDT_ZONE_COUNT] = { 0 };
        int nb = 0;
        int baseline_mean;

        for (q = 0; q < 4; q++)
          if (gx_fdt_probe (self, t) == 0)
            {
              for (k = 0; k < (int) GXFP_FDT_ZONE_COUNT; k++)
                acc[k] += t[k];
              nb++;
            }

        if (!nb)
          continue;

        for (k = 0; k < (int) GXFP_FDT_ZONE_COUNT; k++)
          self->fdt_base[k] = acc[k] / nb;
        baseline_mean = gx_fdt_mean (self->fdt_base);

        if (off_anchor_mean >= 0 &&
            off_anchor_mean - baseline_mean > GX_DIAG_BASELINE_MAX_DRIFT)
          {
              fp_warn ("GXFP51A0 FDT baseline contaminated by touch: mean=%d anchor=%d attempt=%d/%d",
                     baseline_mean, off_anchor_mean, attempt,
                     GX_DIAG_BASELINE_ATTEMPTS);
            if (!gx_wait_sensor_clear (self, off_anchor_mean, NULL))
              return FALSE;
            continue;
          }

        if (baseline_mean > off_anchor_mean)
          off_anchor_mean = baseline_mean;

        self->have_fdt = TRUE;
        self->fdt_abs = baseline_mean - GOODIX_FDT_ABS_MARGIN;
        fp_info ("FDT auto-calibrated: idle mean=%d -> floor=%d (drop>%d)",
                 baseline_mean, self->fdt_abs, GOODIX_FDT_DROP);
        if (capture_diagnostic)
          fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_BASELINE_STABLE: mean=%d anchor=%d",
                   baseline_mean, off_anchor_mean);
        break;
      }
  }

  if (capture_diagnostic && self->have_fdt &&
      !gx_diag_press_countdown (self, off_anchor_mean))
    return FALSE;

  return self->have_fdt;
}

#define GX_PREPARE_ATTEMPTS 2

static void
gx_invalidate_capture_context (FpiDeviceGoodix51A0 *self)
{
  self->production_ready = FALSE;
  self->warm_valid = FALSE;
  self->have_fdt = FALSE;
  self->bg_dirty = FALSE;
  self->tls_rxlen = 0;
  self->tls_rxpos = 0;
}

static gboolean
gx_recover_capture_context (FpiDeviceGoodix51A0 *self)
{
  gchar fw[64] = { 0 };

  gx_invalidate_capture_context (self);
  gx_tls_teardown (self);

  /* A timed-out image record leaves the TLS sequence and MCU transaction
   * boundary uncertain.  Recovery is therefore a full hardware reset, not a
   * blind replay on the same session.  The validated PMK cache is deliberately
   * retained: a transport timeout does not prove that the key changed. */
  gx_gpio_reset (self);
  if (!gx_read_fw_version_stage2e (self, fw, sizeof fw) ||
      g_strcmp0 (fw, "GF_ST411SEC_APP_14115") != 0)
    {
      fp_warn ("GXFP51A0 capture-context recovery could not re-establish the firmware boundary");
      return FALSE;
    }

  fp_info ("GXFP51A0 capture-context recovery reset/A8 confirmed: %s", fw);
  return TRUE;
}

static gboolean
gx_prepare_capture_context (FpiDeviceGoodix51A0 *self,
                            gboolean capture_diagnostic)
{
  int attempt;

  /* Diagnostics are intentionally single-shot so protocol failures remain
   * visible to the research harness.  Production operations get a bounded
   * whole-session retry; each retry starts after a hard reset because a
   * missing TLS image after ACK may have advanced unknown sensor state. */
  if (capture_diagnostic ||
      g_getenv ("GXFP_DIAGNOSTIC_ONESHOT") ||
      g_getenv ("GXFP_DIAGNOSTIC_TLS_ONLY"))
    return gx_prepare_capture_context_once (self, capture_diagnostic);

  for (attempt = 1; attempt <= GX_PREPARE_ATTEMPTS; attempt++)
    {
      GCancellable *c = fpi_device_get_cancellable (FP_DEVICE (self));

      if (c && g_cancellable_is_cancelled (c))
        return FALSE;

      if (gx_prepare_capture_context_once (self, FALSE))
        {
          self->capture_recovery_pending = FALSE;
          return TRUE;
        }

      fp_warn ("GXFP51A0 capture-context preparation failed attempt=%d/%d",
               attempt, GX_PREPARE_ATTEMPTS);

      if (!gx_recover_capture_context (self))
        break;
    }

  return FALSE;
}

static gboolean
gx_session_start (FpiDeviceGoodix51A0 *self)
{
  gboolean capture_diagnostic =
    g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE") != NULL;

  if (self->capture_recovery_pending)
    {
      fp_info ("GXFP51A0 rebuilding capture context after transport desync");
      if (!gx_recover_capture_context (self))
        return FALSE;
    }

  /* Diagnostics deliberately retain their interactive preparation so the
   * research harness can observe each boundary. Normal fprintd clients are
   * prepared during device open/Claim, before EnrollStart or VerifyStart is
   * returned to the desktop. */
  if (capture_diagnostic || g_getenv ("GXFP_DIAGNOSTIC_ONESHOT") ||
      g_getenv ("GXFP_DIAGNOSTIC_TLS_ONLY"))
    return gx_prepare_capture_context (self, capture_diagnostic);

  if (self->production_ready && self->tls_up && self->have_fdt &&
      self->bg_frame)
    {
      fp_info ("GXFP51A0 reusing capture context prepared during device open");
      return TRUE;
    }

  /* Defensive fallback for non-fprintd clients that may reach an operation
   * without a normal Claim/Open lifecycle. */
  if (!gx_prepare_capture_context (self, FALSE))
    return FALSE;

  self->capture_recovery_pending = FALSE;
  self->production_ready = TRUE;
  return TRUE;
}



/* Pre-processing: subtract the background, then remove row and column
 * banding with a median. */

static double *
gx_preprocess (FpiDeviceGoodix51A0 *self, const guint16 *px)
{
  const int n = GOODIX_IMG_PIXELS;
  double *out = g_new (double, n);
  g_autofree double *sorted = g_new (double, n);
  double pos, frac, p54;
  int lo, hi;

  /* Exact-target GXFP51A0 imaging: frame-background has a drifting DC
   * component.  Recenter at the ~54th percentile, clip negatives, and keep
   * one physical frame per press.  The matcher wrapper performs the final
   * percentile stretch and unsharp mask. */
  for (int i = 0; i < n; i++)
    {
      out[i] = (double) px[i] - self->bg_frame[i];
      sorted[i] = out[i];
    }

  qsort (sorted, n, sizeof *sorted, gx_cmp_dbl);
  pos = 0.54 * (double) (n - 1);
  lo = (int) floor (pos);
  hi = (int) ceil (pos);
  frac = pos - lo;
  p54 = sorted[lo] * (1.0 - frac) + sorted[hi] * frac;

  for (int i = 0; i < n; i++)
    out[i] = MAX (0.0, out[i] - p54);

  return out;
}

/* Is a finger actually down? Costs about 33 ms. */
static gboolean
gx_finger_present (FpiDeviceGoodix51A0 *self)
{
  int cur[GXFP_FDT_ZONE_COUNT];

  if (gx_fdt_probe (self, cur) != 0)
    return FALSE;
  return gx_fdt_drop (self->fdt_base, cur) > GOODIX_FDT_DROP ||
         gx_fdt_mean (cur) < self->fdt_abs;
}


#ifdef GXFP51A0_DEVELOPER
/* Dumps captures for offline evaluation. Enabled simply by the dump directory
 * existing, rather than by an environment variable, which cannot conveniently
 * be set on an already-running systemd service.
 *
 * pN.bin holds the raw frame as 16-bit samples and pN.bin.bg the matching
 * background, so that recorded sets can be replayed through the offline
 * matcher bench. */
#define GX_DUMP_DIR "/run/goodix51a0/dump"

static void
gx_dump_capture (FpiDeviceGoodix51A0 *self, const guint16 *px)
{
  static int seq = 0;
  g_autofree gchar *p = NULL, *b = NULL;

  if (!g_file_test (GX_DUMP_DIR, G_FILE_TEST_IS_DIR) || !self->bg_frame)
    return;

  /* Continue past captures already there, so a restart does not overwrite
   * an earlier collection run. */
  do
    {
      g_free (p);
      p = g_strdup_printf ("%s/p%03d.bin", GX_DUMP_DIR, ++seq);
    }
  while (g_file_test (p, G_FILE_TEST_EXISTS) && seq < 9999);

  b = g_strdup_printf ("%s.bg", p);
  if (g_file_set_contents_full (
        p, (const gchar *) px,
        sizeof (guint16) * GOODIX_IMG_PIXELS,
        G_FILE_SET_CONTENTS_CONSISTENT, 0600, NULL) &&
      g_file_set_contents_full (
        b, (const gchar *) self->bg_frame,
        sizeof (guint16) * GOODIX_IMG_PIXELS,
        G_FILE_SET_CONTENTS_CONSISTENT, 0600, NULL))
    fp_info ("capture saved: %s", p);
}

#endif

/* Captures one press and extracts its descriptors. */
static GxSiftFeatures *
gx_capture_features (FpiDeviceGoodix51A0 *self)
{
  guint16 px[GOODIX_IMG_PIXELS];
  g_autofree double *img = NULL;
  double m = 0, v = 0;
  int i;

  if (!gx_capture_frame (self, px, FALSE))
    return NULL;
  img = gx_preprocess (self, px);

  /* This quality gate is ESSENTIAL. The keypoint detector always returns
   * maxima, even on pure noise, so the number of points says nothing about
   * whether a capture is usable. What separates them is contrast: about 5
   * with no finger against about 200 with one. Without this check a failed
   * press enters the template and degrades it permanently — observed when a
   * user lifted between the two views of a press, poisoning every stage. */
  for (i = 0; i < GOODIX_IMG_PIXELS; i++)
    m += img[i];
  m /= GOODIX_IMG_PIXELS;
  for (i = 0; i < GOODIX_IMG_PIXELS; i++)
    { double d = img[i] - m; v += d * d; }
  v = sqrt (v / GOODIX_IMG_PIXELS);
  if (v < GOODIX_FINGER_STD / 3.0)
    {
      fp_info ("capture rejected: contrast %.0f (no finger?)", v);
      return NULL;
    }
  return gx_sift_extract (img, GOODIX_IMG_WIDTH, GOODIX_IMG_HEIGHT);
}

/* ------------------------------------------------------------------ */
/*  Serialising a set of views into an FpPrint                         */
/* ------------------------------------------------------------------ */

/* Driver-private template schema. Increment this whenever the serialized
 * descriptor representation or matching semantics become incompatible.
 *
 * Versioned templates make future driver upgrades explicit: a newer driver
 * can request re-enrollment instead of silently interpreting stale biometric
 * data with changed semantics. Legacy aay templates from the development
 * harness remain readable so current research data does not get stranded. */
#define GX_TEMPLATE_VERSION 4u

static GVariant *
gx_views_to_variant (GPtrArray *views)
{
  GVariantBuilder b;
  GVariant *payload;
  guint i;

  g_variant_builder_init (&b, G_VARIANT_TYPE ("aay"));
  for (i = 0; i < views->len; i++)
    {
      g_autoptr(GByteArray) ba = gx_sift_serialize (g_ptr_array_index (views, i));
      g_variant_builder_add_value (
        &b, g_variant_new_fixed_array (G_VARIANT_TYPE_BYTE, ba->data, ba->len, 1));
    }

  payload = g_variant_builder_end (&b);
  return g_variant_new ("(u@aay)", GX_TEMPLATE_VERSION, payload);
}

static GPtrArray *
gx_views_from_print (FpPrint *print)
{
  g_autoptr(GVariant) data = NULL;
  g_autoptr(GVariant) payload = NULL;
  GPtrArray *views = g_ptr_array_new_with_free_func ((GDestroyNotify) gx_sift_free);
  GVariantIter it;
  GVariant *child;
  guint32 version = 0;

  g_object_get (print, "fpi-data", &data, NULL);
  if (!data)
    return views;

  if (g_variant_is_of_type (data, G_VARIANT_TYPE ("(uaay)")))
    {
      g_variant_get (data, "(u@aay)", &version, &payload);
      if (version != GX_TEMPLATE_VERSION)
        {
          fp_warn ("unsupported template version %u (driver expects %u); re-enrollment required",
                   version, GX_TEMPLATE_VERSION);
          return views;
        }
    }
  else
    {
      fp_warn ("unsupported template payload type %s",
               g_variant_get_type_string (data));
      return views;
    }

  g_variant_iter_init (&it, payload);
  while ((child = g_variant_iter_next_value (&it)))
    {
      gsize len = 0;
      const guint8 *raw = g_variant_get_fixed_array (child, &len, 1);
      GxSiftFeatures *f = gx_sift_deserialize (raw, len);
      if (f)
        g_ptr_array_add (views, f);
      g_variant_unref (child);
    }
  return views;
}

/* ------------------------------------------------------------------ */
/*  Enrolment and verification                                         */
/*                                                                     */
/*  A libfprint driver must not block the main loop: fprintd answers    */
/*  D-Bus calls while an operation is in flight. Waiting for the finger */
/*  is therefore done with successive detection polls driven by a       */
/*  timeout, each returning within about 33 ms.                        */
/* ------------------------------------------------------------------ */

typedef struct
{
  GPtrArray *views;        /* descriptors accumulated while enrolling */
  GxSiftFeatures *probe;   /* descriptors of the capture being verified */
  int        best;         /* best score reached across attempts */
  int        tries;        /* captures attempted for this verification */
  int        stage;        /* vue en cours */
  int        polls;        /* polls done in the current state */
  gboolean   verifying;       /* verify or identify: capture exactly one usable press */
  gboolean   identifying;     /* one-to-many gallery match */
  gboolean   match_reported;  /* terminal match/no-match already sent early */
  FpPrint   *identify_match;  /* matched gallery print, owned while the task lives */
} GxTask;

enum {
  GX_ST_SESSION,       /* init TLS + fond + ligne de base FDT */
  GX_ST_WAIT_ON,       /* wait for the finger, polling without blocking */
  GX_ST_CAPTURE,       /* capture, then extract descriptors */
  GX_ST_WAIT_OFF,      /* wait for the finger to be lifted */
  GX_ST_DONE,
  GX_ST_NUM,
};

#define GX_POLL_MS     100     /* detection polling period */
#define GX_POLL_MAX    300     /* about 30 s before giving up */
#define GX_POLL_OFF    100     /* about 10 s to wait for release */
#define GX_RECOVERY_OFF_POLLS 2 /* ~1 s worst-case with failed FDT probes */
#define GX_VERIFY_MAX_ATTEMPTS 3 /* fixed budget; never score-proximity conditioned */

/* ------------------------------------------------------------------ */
/*  Off-loading the blocking work                                      */
/* ------------------------------------------------------------------ */

/* Two steps take about a second each and cannot be split: establishing the
 * session (TLS handshake plus a background capture) and capturing an image.
 * Both go through OpenSSL's blocking API over a synchronous SPI file
 * descriptor, which cannot be pumped from callbacks without restructuring the
 * whole TLS layer.
 *
 * Run inline they froze the main loop, so fprintd stopped answering D-Bus for
 * the duration. Since libfprint runs one operation at a time and the state
 * machine waits for the completion callback, nothing else touches the device
 * while the worker runs, which makes a worker thread safe here; libfprint's own
 * secugen driver off-loads its heavy work the same way.
 *
 * Only these two steps move off the main loop. Finger detection stays on it: at
 * roughly 33 ms a poll it is short enough not to be felt, and keeping it there
 * avoids any cross-thread access to the sensor between captures. */

typedef struct
{
  FpiSsm         *ssm;
  FpDevice       *dev;
  GxSiftFeatures *feat;      /* capture result, NULL on failure */
  gboolean        ok;
} GxWork;

static void
gx_work_free (GxWork *w)
{
  g_clear_pointer (&w->feat, gx_sift_free);
  g_free (w);
}

static void
gx_session_thread (GTask *task, gpointer src, gpointer data, GCancellable *c)
{
  GxWork *w = data;
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (w->dev);

  if (g_getenv ("GXFP_DIAGNOSTIC_TLS_ONLY"))
    w->ok = gx_tls_session (self);
  else
    w->ok = gx_session_start (self);
  g_task_return_boolean (task, TRUE);
}

static void
gx_capture_thread (GTask *task, gpointer src, gpointer data, GCancellable *c)
{
  GxWork *w = data;
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (w->dev);

  w->feat = gx_capture_features (self);
  w->ok = (w->feat != NULL);
  g_task_return_boolean (task, TRUE);
}

static void
gx_session_done (GObject *src, GAsyncResult *res, gpointer user_data)
{
  GxWork *w = g_task_get_task_data (G_TASK (res));
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (w->dev);

  if (!w->ok)
    {
      fpi_ssm_mark_failed (w->ssm, fpi_device_error_new_msg (
        FP_DEVICE_ERROR_PROTO, "sensor initialisation failed"));
      return;
    }
  if (g_getenv ("GXFP_DIAGNOSTIC_TLS_ONLY"))
    {
      fp_info ("GXFP51A0 TLS-only diagnostic complete");
      fpi_ssm_mark_failed (w->ssm, fpi_device_error_new_msg (
        FP_DEVICE_ERROR_GENERAL, "TLS-only diagnostic complete"));
      return;
    }
  if (self->bg_dirty)
    {
      /* Better to ask for the finger to be removed than to return a collapsed
       * score the user could not possibly explain. */
      fpi_ssm_mark_failed (w->ssm,
        fpi_device_retry_new (FP_DEVICE_RETRY_REMOVE_FINGER));
      return;
    }

  if (g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE"))
    fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_READY: PRESS_AND_HOLD_FINGER");
  fpi_ssm_next_state (w->ssm);
}

/* Runs @fn on a worker thread, then @done on the main loop. */
static void
gx_run_async (FpiSsm *ssm, FpDevice *dev, GTaskThreadFunc fn,
              GAsyncReadyCallback done)
{
  GTask *task = g_task_new (dev, NULL, done, NULL);
  GxWork *w = g_new0 (GxWork, 1);

  w->ssm = ssm;
  w->dev = dev;
  g_task_set_task_data (task, w, (GDestroyNotify) gx_work_free);
  g_task_run_in_thread (task, fn);
  g_object_unref (task);
}

static void
gx_task_free (GxTask *t)
{
  if (!t)
    return;
  if (t->views)
    g_ptr_array_free (t->views, TRUE);
  g_clear_pointer (&t->probe, gx_sift_free);
  g_clear_object (&t->identify_match);
  g_free (t);
}


/* libfprint provides a GCancellable per operation; that is how fprintd asks us
 * to stop when the user dismisses the prompt or picks the password instead.
 * Without checking it the polls run to their limit, roughly 30 seconds, the
 * stop call times out and the sensor stays busy. */
static gboolean
gx_cancelled (FpDevice *dev, FpiSsm *ssm)
{
  GCancellable *c = fpi_device_get_cancellable (dev);

  if (!c || !g_cancellable_is_cancelled (c))
    return FALSE;
  fp_info ("operation cancelled by the caller");
  fpi_device_report_finger_status (dev, FP_FINGER_STATUS_NONE);
  fpi_ssm_mark_failed (ssm, g_error_new (G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                         "operation cancelled"));
  return TRUE;
}

/* Non-blocking poll, re-armed by timeout until the finger is detected. */
static gboolean
gx_poll_on (gpointer user_data)
{
  FpiSsm *ssm = user_data;
  FpDevice *dev = fpi_ssm_get_device (ssm);
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);
  GxTask *t = fpi_ssm_get_data (ssm);
  int cur[GXFP_FDT_ZONE_COUNT];

  if (gx_cancelled (dev, ssm))
    { self->poll_id = 0; return G_SOURCE_REMOVE; }

  if (gx_fdt_probe (self, cur) != 0)
    {
      fp_dbg ("wait-on: detection probe failed");
      goto again;
    }

  /* Reuse the values just read; probing twice per poll perturbs the sensor. */
  if (t->polls % 5 == 0)
    {
      fp_info ("wait-on: mean=%d drop=%d (thresholds %d / %d)",
               gx_fdt_mean (cur), gx_fdt_drop (self->fdt_base, cur),
               self->fdt_abs, GOODIX_FDT_DROP);
      if (g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE"))
        fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_WAITING_FOR_FINGER: PRESS_AND_HOLD_NOW");
    }

  if (gx_fdt_drop (self->fdt_base, cur) > GOODIX_FDT_DROP ||
      gx_fdt_mean (cur) < self->fdt_abs)
    {
      /* Keep NEEDED asserted: the capture still takes about 1.1 s and the
       * finger must stay down for it. This flag is what lets a user interface
       * say when to lift — without it people lift on detection, one second too
       * early, and spoil the capture. */
      fpi_device_report_finger_status (dev, FP_FINGER_STATUS_NEEDED |
                                            FP_FINGER_STATUS_PRESENT);
      fp_info ("finger status: needed=1 present=1; capture starting");
      self->poll_id = 0;
      fpi_ssm_jump_to_state (ssm, GX_ST_CAPTURE);
      return G_SOURCE_REMOVE;
    }
again:
  if (++t->polls > GX_POLL_MAX)
    {
      self->poll_id = 0;
      fpi_ssm_mark_failed (ssm, fpi_device_retry_new (FP_DEVICE_RETRY_GENERAL));
      return G_SOURCE_REMOVE;
    }
  return G_SOURCE_CONTINUE;
}

static gboolean
gx_poll_off (gpointer user_data)
{
  FpiSsm *ssm = user_data;
  FpDevice *dev = fpi_ssm_get_device (ssm);
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);
  GxTask *t = fpi_ssm_get_data (ssm);
  int cur[GXFP_FDT_ZONE_COUNT];
  gboolean off = FALSE;

  if (gx_cancelled (dev, ssm))
    { self->poll_id = 0; return G_SOURCE_REMOVE; }

  if (gx_fdt_probe (self, cur) == 0 &&
      gx_fdt_drop (self->fdt_base, cur) < GOODIX_FDT_DROP / 2 &&
      gx_fdt_mean (cur) >= self->fdt_abs)
    off = TRUE;

  if (off || ++t->polls >
             (self->capture_recovery_pending ? GX_RECOVERY_OFF_POLLS
                                             : GX_POLL_OFF))
    {
      fpi_device_report_finger_status (dev, FP_FINGER_STATUS_NONE);

      if (self->capture_recovery_pending)
        {
          fp_info ("GXFP51A0 finger released/timeout after transport desync; "
                   "rebuilding session before another biometric press");
          fpi_ssm_jump_to_state (ssm, GX_ST_SESSION);
        }
      /* Next enrollment view, fixed-budget verify retry, or finish. */
      else if (t->verifying && !t->identifying && !t->match_reported &&
               t->tries < GX_VERIFY_MAX_ATTEMPTS)
        {
          fp_info ("verify: finger released; waiting for retry press %d/%d",
                   t->tries + 1, GX_VERIFY_MAX_ATTEMPTS);
          fpi_ssm_jump_to_state (ssm, GX_ST_WAIT_ON);
        }
      else if (t->verifying || t->stage >= GX_ENROLL_STAGES)
        fpi_ssm_jump_to_state (ssm, GX_ST_DONE);
      else
        fpi_ssm_jump_to_state (ssm, GX_ST_WAIT_ON);
      self->poll_id = 0;
      return G_SOURCE_REMOVE;
    }
  return G_SOURCE_CONTINUE;
}

static int
gx_score_probe_against_print (FpPrint *tmpl,
                              const GxSiftFeatures *probe,
                              guint *out_base_views,
                              guint *out_adapt_views)
{
  g_autoptr(GPtrArray) views = gx_views_from_print (tmpl);
  int best = 0;
  int top[5] = { 0, 0, 0, 0, 0 };
  guint top_idx[5] = { 0, 0, 0, 0, 0 };

  if (out_base_views)
    *out_base_views = views ? views->len : 0;
  if (out_adapt_views)
    *out_adapt_views = 0;

  if (!probe)
    return 0;

  /* Modern small-sensor SIGFM drivers use the best score against one enrolled
   * sample.  Fusing evidence across every view inflated the impostor floor in
   * the previous matcher as galleries became richer. */
  for (guint i = 0; views && i < views->len; i++)
    {
      int score = gx_sift_match (probe, g_ptr_array_index (views, i));

      if (score > best)
        best = score;

      for (guint rank = 0; rank < G_N_ELEMENTS (top); rank++)
        if (score > top[rank])
          {
            for (guint j = G_N_ELEMENTS (top) - 1; j > rank; j--)
              {
                top[j] = top[j - 1];
                top_idx[j] = top_idx[j - 1];
              }
            top[rank] = score;
            top_idx[rank] = i;
            break;
          }
    }

  if (g_getenv ("GXFP_MATCH_DIAGNOSTICS"))
    {
      fp_info ("gallery scores: %d@%u %d@%u %d@%u %d@%u %d@%u (views=%u)",
               top[0], top_idx[0], top[1], top_idx[1], top[2], top_idx[2],
               top[3], top_idx[3], top[4], top_idx[4],
               views ? views->len : 0);

      if (views)
        for (guint rank = 0; rank < G_N_ELEMENTS (top); rank++)
          {
            guint idx = top_idx[rank];
            int inliers = 0, overlap = 0, zncc = 0, agree = 0;

            if (top[rank] <= 0 || idx >= views->len)
              continue;
            if (gx_sift_pixel_overlap_metrics (probe,
                                               g_ptr_array_index (views, idx),
                                               &inliers, &overlap, &zncc, &agree))
              fp_info ("pixel diagnostic: rank=%u view=%u baseline=%d "
                       "inliers=%d overlap=%d zncc_milli=%d agree_permille=%d",
                       rank, idx, top[rank], inliers, overlap, zncc, agree);
          }
    }

  /* Pixel metrics are research-only and MUST NOT affect authentication. */
  return best;
}

static void
gx_capture_done (GObject *src, GAsyncResult *res, gpointer user_data)
{
  GxWork *w = g_task_get_task_data (G_TASK (res));
  FpiSsm *ssm = w->ssm;
  FpDevice *dev = w->dev;
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);
  GxTask *t = fpi_ssm_get_data (ssm);
  GxSiftFeatures *f = g_steal_pointer (&w->feat);

  if (g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE"))
    {
      guint nfeatures = f ? gx_sift_keypoints (f) : 0;

      fp_info ("GXFP51A0 capture-only diagnostic complete: features=%u",
               nfeatures);
      fp_info ("GXFP51A0 CAPTURE_DIAGNOSTIC_DONE: REMOVE_FINGER");
      g_clear_pointer (&f, gx_sift_free);
      fpi_device_report_finger_status (dev, FP_FINGER_STATUS_NONE);
      fpi_ssm_mark_failed (ssm, fpi_device_error_new_msg (
        FP_DEVICE_ERROR_GENERAL, "capture-only diagnostic complete"));
      return;
    }

      if (!f && self->capture_recovery_pending)
        {
          /* No authenticated image exists, so this is transport recovery, not
           * a biometric no-match and must not consume the fixed verify budget.
           * Ask for release, rebuild the session, then request a fresh press. */
          fp_warn ("GXFP51A0 capture transport failed; recovering before "
                   "another biometric attempt");
          fpi_device_report_finger_status (dev, FP_FINGER_STATUS_PRESENT);
          t->polls = 0;
          self->poll_id = g_timeout_add (GX_POLL_MS, gx_poll_off, ssm);
          return;
        }

      if (!f || gx_sift_keypoints (f) < GX_MIN_CAPTURE_KEYPOINTS)
        {
          /* Tell the two causes apart: they call for opposite gestures.
           * The image capture takes about 1.4 s, so a finger pressed and
           * immediately lifted does trigger detection, but the image is taken
           * once it has gone — contrast around 5, the empty level. Reporting
           * "not centred" there sends the user to fix the wrong thing, which
           * is glaring the first time someone unfamiliar tries the sensor. */
          FpDeviceRetry why = gx_finger_present (self)
                                ? FP_DEVICE_RETRY_CENTER_FINGER
                                : FP_DEVICE_RETRY_TOO_SHORT;

          g_clear_pointer (&f, gx_sift_free);
          if (why == FP_DEVICE_RETRY_TOO_SHORT)
            fp_info ("finger lifted before the capture finished");

          if (t->verifying)
            {
              fpi_ssm_mark_failed (ssm, fpi_device_retry_new (why));
              return;
            }
          /* unusable press: ask again without advancing the stage */
          fpi_device_enroll_progress (dev, t->stage, NULL,
                                      fpi_device_retry_new (why));
        }
      else if (t->verifying)
        {
          /* A usable press is one independent biometric decision. Verification
           * has a small fixed retry budget for partial-sensor placement misses;
           * retries never depend on how close a score is to the threshold. */
          t->tries++;
          g_clear_pointer (&t->probe, gx_sift_free);
          t->probe = f;

          if (t->identifying)
            {
              GPtrArray *gallery = NULL;
              FpPrint *best_print = NULL;
              int best = 0;

              fpi_device_get_identify_data (dev, &gallery);
              for (guint i = 0; gallery && i < gallery->len; i++)
                {
                  FpPrint *candidate = g_ptr_array_index (gallery, i);
                  guint base_views = 0, adapt_views = 0;
                  int score = gx_score_probe_against_print (candidate, t->probe,
                                                            &base_views,
                                                            &adapt_views);

                  fp_info ("identify: candidate=%u score=%d threshold=%d views=%u+%u",
                           i, score, GX_MATCH_THRESHOLD,
                           base_views, adapt_views);
                  if (!best_print || score > best)
                    {
                      best = score;
                      best_print = candidate;
                    }
                }

              t->best = best;
              if (best_print && best >= GX_MATCH_THRESHOLD)
                {
                  t->identify_match = g_object_ref (best_print);
                    }

              fpi_device_identify_report (dev,
                                          t->identify_match,
                                          NULL,
                                          NULL);
              t->match_reported = TRUE;
              fp_info ("identify: early result reported best=%d threshold=%d gallery=%u",
                       best, GX_MATCH_THRESHOLD, gallery ? gallery->len : 0);
            }
          else
            {
              FpPrint *tmpl = NULL;
              guint base_views = 0, adapt_views = 0;

              fpi_device_get_verify_data (dev, &tmpl);
              int attempt_score = gx_score_probe_against_print (tmpl, t->probe,
                                                                  &base_views,
                                                                  &adapt_views);
              t->best = MAX (t->best, attempt_score);

              fp_info ("verify: attempt %d/%d -> %d matches (best=%d threshold=%d, %u views + %u acquired)",
                       t->tries, GX_VERIFY_MAX_ATTEMPTS, attempt_score, t->best,
                       GX_MATCH_THRESHOLD, base_views, adapt_views);

              if (attempt_score >= GX_MATCH_THRESHOLD)
                {
                  fpi_device_verify_report (dev, FPI_MATCH_SUCCESS, NULL, NULL);
                  t->match_reported = TRUE;
                  fp_info ("verify: match reported on attempt %d at %d matches",
                           t->tries, attempt_score);
                }
              else if (t->tries >= GX_VERIFY_MAX_ATTEMPTS)
                {
                  fpi_device_verify_report (dev, FPI_MATCH_FAIL, NULL, NULL);
                  t->match_reported = TRUE;
                  fp_info ("verify: no-match reported after %d fixed attempts (best=%d threshold=%d)",
                           t->tries, t->best, GX_MATCH_THRESHOLD);
                }
              else
                {
                  fp_info ("verify: no-match attempt %d/%d; request another complete press",
                           t->tries, GX_VERIFY_MAX_ATTEMPTS);
                }
            }

        }
      else
        {
          guint keypoints = gx_sift_keypoints (f);

          /* On an 80x64 partial sensor, two valid presses of the same finger
           * may cover disjoint patches and legitimately score zero pairwise.
           * Rejecting those samples traps enrollment and destroys coverage.
           * Quality is gated above by contrast and keypoint count; biometric
           * discrimination is evaluated later against the complete gallery. */
          g_ptr_array_add (t->views, f);
          t->stage++;
          fp_info ("enroll: stage=%d/%d keypoints=%u",
                   t->stage, GX_ENROLL_STAGES, keypoints);
          fpi_device_enroll_progress (dev, t->stage, NULL, NULL);
        }
      /* Capture done: we no longer need the finger, only its release.
       * PRESENT without NEEDED is the "you may lift now" signal. */
      fpi_device_report_finger_status (dev, FP_FINGER_STATUS_PRESENT);
      t->polls = 0;
      self->poll_id = g_timeout_add (GX_POLL_MS, gx_poll_off, ssm);
}

static void
gx_run_state (FpiSsm *ssm, FpDevice *dev)
{
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);
  GxTask *t = fpi_ssm_get_data (ssm);

  switch (fpi_ssm_get_cur_state (ssm))
    {
    case GX_ST_SESSION:
      gx_run_async (ssm, dev, gx_session_thread, gx_session_done);
      break;

    case GX_ST_WAIT_ON:
      {
        gboolean changed;

        t->polls = 0;
        changed = fpi_device_report_finger_status (dev, FP_FINGER_STATUS_NEEDED);
        fp_info ("finger status: needed=1 present=0 changed=%d",
                 changed ? 1 : 0);
        self->poll_id = g_timeout_add (GX_POLL_MS, gx_poll_on, ssm);
        break;                     /* the poll drives the next state */
      }

    case GX_ST_CAPTURE:
      gx_run_async (ssm, dev, gx_capture_thread, gx_capture_done);
      break;

    case GX_ST_WAIT_OFF:
      /* only reached by jumping here; the poll drives what follows */
      break;

    case GX_ST_DONE:
      fpi_ssm_mark_completed (ssm);
      break;
    }
}

/* --- enrolment completion ------------------------------------------ */
static void
gx_enroll_done (FpiSsm *ssm, FpDevice *dev, GError *error)
{
  GxTask *t = fpi_ssm_get_data (ssm);
  FpPrint *print = NULL;

  if (error)
    {
      fpi_device_enroll_complete (dev, NULL, error);
      return;
    }
  if (!t->views || t->views->len < 3)
    {
      fpi_device_enroll_complete (dev, NULL,
        fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                  "too few usable views"));
      return;
    }

  fpi_device_get_enroll_data (dev, &print);
  fpi_print_set_type (print, FPI_PRINT_RAW);
  fpi_print_set_device_stored (print, FALSE);
  g_object_set (print, "fpi-data", gx_views_to_variant (t->views), NULL);

  fpi_device_enroll_complete (dev, g_object_ref (print), NULL);
}

/* ------------------------------------------------------------------ */
/*  Device operations                                                  */
/* ------------------------------------------------------------------ */

static void
gx_transport_close (FpiDeviceGoodix51A0 *self)
{
  if (self->irq_fd >= 0)
    {
      close (self->irq_fd);
      self->irq_fd = -1;
    }

  if (self->spi_fd >= 0)
    {
      close (self->spi_fd);
      self->spi_fd = -1;
    }
}

static gboolean
gx_transport_open (FpDevice *dev, GError **error)
{
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);
  const gchar *path;
  guint8 mode = SPI_MODE_0 | SPI_CS_HIGH;
  guint8 bits = 8;
  guint32 speed = 1000000;

  path = fpi_device_get_udev_data (dev, FPI_DEVICE_UDEV_SUBTYPE_SPIDEV);
  if (!path || !*path)
    {
      g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_NOT_FOUND,
                           "GXFP51A0 spidev node was not supplied by libfprint udev discovery");
      return FALSE;
    }

  self->spi_fd = open (path, O_RDWR | O_CLOEXEC);
  if (self->spi_fd < 0)
    {
      g_set_error (error, G_IO_ERROR, g_io_error_from_errno (errno),
                   "cannot open spidev node %s", path);
      return FALSE;
    }

  if (flock (self->spi_fd, LOCK_EX | LOCK_NB) != 0)
    {
      gx_transport_close (self);
      g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_BUSY,
                           "sensor already in use by another process");
      return FALSE;
    }

  if (ioctl (self->spi_fd, SPI_IOC_WR_MODE, &mode) < 0 ||
      ioctl (self->spi_fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
      ioctl (self->spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0)
    {
      int saved_errno = errno;

      gx_transport_close (self);
      g_set_error (error, G_IO_ERROR, g_io_error_from_errno (saved_errno),
                   "cannot configure GXFP51A0 SPI transport: %s",
                   g_strerror (saved_errno));
      return FALSE;
    }

  self->irq_fd = gx51_open_irq_gpio48 ();
  if (self->irq_fd < 0)
    {
      gx_transport_close (self);
      g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_PROTO,
                           "GXFP51A0 GPIO48 IRQ input is not available");
      return FALSE;
    }

  fp_info ("GXFP51A0 IRQ source: direct GPIO48 level polling");
  return TRUE;
}

#define GX_SLEEP_DELTA_STALE_US (250 * 1000)

static gboolean
gx_sleep_delta_us (gint64 *out)
{
  struct timespec boot = { 0, }, mono = { 0, };

  g_return_val_if_fail (out != NULL, FALSE);

  if (clock_gettime (CLOCK_BOOTTIME, &boot) != 0 ||
      clock_gettime (CLOCK_MONOTONIC, &mono) != 0)
    return FALSE;

  *out = ((gint64) boot.tv_sec - (gint64) mono.tv_sec) * G_USEC_PER_SEC +
         ((gint64) boot.tv_nsec - (gint64) mono.tv_nsec) / 1000;
  return TRUE;
}

static gboolean
gx_warm_crossed_sleep (FpiDeviceGoodix51A0 *self)
{
  gint64 now = 0;

  if (!self->warm_valid || !self->warm_sleep_clock_valid)
    return FALSE;

  if (!gx_sleep_delta_us (&now))
    return FALSE;

  if (now - self->warm_sleep_delta_us > GX_SLEEP_DELTA_STALE_US)
    {
      fp_info ("GXFP51A0 sleep boundary detected: boottime-monotonic advanced by %d ms",
               (int) ((now - self->warm_sleep_delta_us) / 1000));
      return TRUE;
    }

  return FALSE;
}

static void
gx_warm_abandon (FpiDeviceGoodix51A0 *self)
{
  /* Host-only invalidation.  Use this after suspend or another lifecycle
   * boundary where sensor-side TLS state cannot be trusted: never send a
   * close_notify over a session that may no longer exist. */
  self->warm_valid = FALSE;
  self->production_ready = FALSE;
  self->have_fdt = FALSE;
  self->bg_dirty = FALSE;
  self->tls_rxlen = 0;
  self->tls_rxpos = 0;
  self->tls_up = FALSE;
  self->warm_sleep_delta_us = 0;
  self->warm_sleep_clock_valid = FALSE;
  g_clear_pointer (&self->tls, gx_tls_free);
  gx_pmk_clear (self);
  g_clear_pointer (&self->bg_frame, g_free);
}

static void
gx_warm_discard (FpiDeviceGoodix51A0 *self)
{
  if (self->tls_up && self->spi_fd >= 0 && self->irq_fd >= 0)
    gx_tls_teardown (self);
  gx_warm_abandon (self);
}

static gboolean
gx_warm_available (FpiDeviceGoodix51A0 *self)
{
  return self->warm_valid && self->tls_up && self->tls &&
         self->bg_frame && self->have_fdt;
}

static gboolean
gx_warm_validate (FpiDeviceGoodix51A0 *self)
{
  int cur[GXFP_FDT_ZONE_COUNT];
  gint64 t0 = g_get_monotonic_time ();

  if (gx_fdt_probe (self, cur) != 0)
    return FALSE;

  fp_info ("GXFP51A0 warm context validated in %d ms (FDT mean=%d drop=%d)",
           (int) ((g_get_monotonic_time () - t0) / 1000),
           gx_fdt_mean (cur), gx_fdt_drop (self->fdt_base, cur));
  return TRUE;
}

static gboolean
gx_cold_prepare (FpiDeviceGoodix51A0 *self)
{
  gchar fw[64] = "";

  self->fdt_abs = GOODIX_FDT_ABS;
  self->timing_scale = gx_timing_load ();
  self->timing_saved = self->timing_scale;
  if (self->capture_gap_scale < GX_CAPTURE_SCALE_MIN)
    {
      self->capture_gap_scale = gx_capture_timing_load ();
      self->capture_gap_saved = self->capture_gap_scale;
    }

  if (!gx_driverstate_install_windows (self))
    {
      fp_info ("GXFP51A0: DriverState silent; applying reviewed Windows fallback reset");
      gx_gpio_reset (self);
      fp_warn ("GXFP51A0: continuing to init_MCU after DriverState fallback as Windows does");
    }

  if (gx_read_fw_version (self, fw, sizeof fw))
    fp_info ("GXFP51A0 firmware: %s", fw);
  else
    {
      fp_info ("GXFP51A0: three A8 attempts silent; applying common-init reset fallback");
      gx_gpio_reset (self);
      if (gx_read_fw_version_once (self, fw, sizeof fw))
        fp_info ("GXFP51A0 firmware after reset fallback: %s", fw);
      else
        fp_warn ("GXFP51A0: no A8 firmware response after final fallback");
    }

  fp_info ("GXFP51A0 opened; experimental PMK/TLS/capture path enabled");

  if (g_getenv ("GXFP_DIAGNOSTIC_CAPTURE_ONCE") ||
      g_getenv ("GXFP_DIAGNOSTIC_ONESHOT") ||
      g_getenv ("GXFP_DIAGNOSTIC_TLS_ONLY"))
    return FALSE;

  /* Claim/open is the authoritative preparation boundary.  Unlike rel24/25
   * probe prewarm, this uses the bounded recovery wrapper, including a fresh
   * MCU boundary between attempts and the production PMK fallback. */
  if (!gx_prepare_capture_context (self, FALSE))
    {
      fp_warn ("GXFP51A0 cold preparation failed after bounded recovery");
      gx_invalidate_capture_context (self);
      gx_tls_teardown (self);
      gx_pmk_clear (self);
      g_clear_pointer (&self->bg_frame, g_free);
      return FALSE;
    }

  self->capture_recovery_pending = FALSE;
  self->capture_pacing_suppressed = FALSE;
  self->production_ready = TRUE;
  self->warm_valid = TRUE;
  self->warm_sleep_clock_valid =
    gx_sleep_delta_us (&self->warm_sleep_delta_us);
  fp_info ("GXFP51A0 production capture context ready; native warm state armed "
           "(capture pacing=%d%% gap=%u us)",
           self->capture_gap_scale, gx_capture_gap_us (self));
  return TRUE;
}

static void
gx_dev_probe (FpDevice *dev)
{
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);
  GError *err = NULL;

  /* Enumeration must be passive.  rel24/25 performed a complete TLS +
   * background GET_IMAGE transaction here, before any biometric Claim.  A
   * transport miss could therefore desynchronise the MCU before the greeter
   * ever asked for a fingerprint.  Validate only host-side transport
   * availability in probe(); the real Claim/open owns sensor initialisation. */
  if (!gx_transport_open (dev, &err))
    {
      fpi_device_probe_complete (dev, NULL, NULL, err);
      return;
    }

  gx_transport_close (self);
  fpi_device_probe_complete (dev, NULL, NULL, NULL);
}

static void
gx_dev_open (FpDevice *dev)
{
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);
  GError *err = NULL;
  gboolean cold_boundary_done = FALSE;
  gboolean slept = gx_warm_crossed_sleep (self);
  gboolean had_warm = self->warm_valid || self->tls != NULL || self->tls_up;

  /* An idle libfprint device may not receive the driver suspend vfunc.  Detect
   * that case before reopening hardware handles, while stale TLS can still be
   * discarded host-side without sending anything to the sensor. */
  if (slept || self->force_cold_reset)
    {
      fp_info ("GXFP51A0 lifecycle boundary detected; invalidating warm state");
      gx_warm_abandon (self);
      self->capture_recovery_pending = FALSE;
      /* A dead S3 session is not evidence that the SPI controller needs slower
       * capture pacing. Forget any unpersisted in-process escalation and reload
       * only a value validated by a successful complete capture. */
      self->capture_gap_scale = 0;
      self->capture_gap_saved = 0;
      self->capture_clean_streak = 0;
      self->capture_retry_seen = FALSE;
      self->capture_pacing_suppressed = TRUE;
      had_warm = FALSE;
    }

  if (!gx_transport_open (dev, &err))
    {
      fpi_device_open_complete (dev, err);
      return;
    }

  if (slept || self->force_cold_reset)
    {
      gx_gpio_reset (self);
      self->force_cold_reset = FALSE;
      cold_boundary_done = TRUE;
    }

  if (self->capture_recovery_pending)
    {
      fp_info ("GXFP51A0 pending capture recovery found at open; resetting "
               "before cold preparation");
      if (!gx_recover_capture_context (self))
        {
          gx_transport_close (self);
          fpi_device_open_complete (
            dev, fpi_device_error_new_msg (FP_DEVICE_ERROR_PROTO,
                                           "capture transport recovery failed"));
          return;
        }
      cold_boundary_done = TRUE;
    }

  if (gx_warm_available (self))
    {
      if (gx_warm_validate (self))
        {
          self->production_ready = TRUE;
          fp_info ("GXFP51A0 reusing native libfprint warm context");
          fpi_device_open_complete (dev, NULL);
          return;
        }

      fp_warn ("GXFP51A0 warm context did not answer; falling back to cold preparation");
      gx_warm_discard (self);
      gx_gpio_reset (self);
      cold_boundary_done = TRUE;
    }
  else if (had_warm)
    {
      fp_info ("GXFP51A0 incomplete warm context; returning to cold preparation");
      gx_warm_discard (self);
      gx_gpio_reset (self);
      cold_boundary_done = TRUE;
    }

  if (!cold_boundary_done)
    gx_gpio_reset (self);

  if (!gx_cold_prepare (self))
    {
      gx_warm_abandon (self);
      gx_transport_close (self);
      fpi_device_open_complete (
        dev, fpi_device_error_new_msg (FP_DEVICE_ERROR_PROTO,
                                       "GXFP51A0 cold preparation failed"));
      return;
    }

  fpi_device_open_complete (dev, NULL);
}

static void
gx_dev_close (FpDevice *dev)
{
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);

  g_clear_handle_id (&self->poll_id, g_source_remove);

  if (!self->force_cold_reset &&
      self->production_ready && self->warm_valid && self->tls_up &&
      self->tls && self->have_fdt && self->bg_frame)
    {
      self->production_ready = FALSE;
      gx_pmk_clear (self);
      gx_transport_close (self);
      fp_info ("GXFP51A0 stashed native warm context across fp_device close");
      fpi_device_close_complete (dev, NULL);
      return;
    }

  if (self->force_cold_reset)
    gx_warm_abandon (self);
  else
    gx_warm_discard (self);
  gx_transport_close (self);
  fpi_device_close_complete (dev, NULL);
}

static void
gx_dev_suspend (FpDevice *dev)
{
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (dev);

  /* The ST411 does not preserve TLS/FDT state across S3, so an interactive
   * action cannot safely continue after resume.  libfprint explicitly asks
   * such drivers to return NOT_SUPPORTED: it cancels the current action before
   * forwarding the suspend result to fprintd, which accepts this condition. */
  self->force_cold_reset = TRUE;
  self->warm_valid = FALSE;
  self->production_ready = FALSE;
  fp_info ("GXFP51A0 suspend: cancelling active action; cold reset required after resume");
  fpi_device_suspend_complete (
    dev, fpi_device_error_new (FP_DEVICE_ERROR_NOT_SUPPORTED));
}

static void
gx_dev_resume (FpDevice *dev)
{
  /* The suspended action was cancelled by libfprint.  A following Claim sees
   * force_cold_reset and reconstructs the sensor session from a clean boundary. */
  fpi_device_resume_complete (dev, NULL);
}



/* --- verification completion --------------------------------------- */
static void
gx_verify_done (FpiSsm *ssm, FpDevice *dev, GError *error)
{
  GxTask *t = fpi_ssm_get_data (ssm);
  FpPrint *template = NULL;
  g_autoptr(GPtrArray) views = NULL;
  int best = 0;

  if (error)
    {
      /* fprintd/PAM may cancel immediately after receiving an early terminal
       * result. That cancellation is cleanup, not a failed authentication. */
      if (t->match_reported &&
          g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
        {
          fp_info ("verify: caller stopped operation after early result");
          g_clear_error (&error);
          fpi_device_verify_complete (dev, NULL);
          return;
        }
      if (error->domain == FP_DEVICE_RETRY)
        fpi_device_verify_report (dev, FPI_MATCH_ERROR, NULL, g_steal_pointer (&error));
      fpi_device_verify_complete (dev, error);
      return;
    }
  if (!t->probe)
    {
      fpi_device_verify_report (dev, FPI_MATCH_ERROR, NULL,
        fpi_device_retry_new (FP_DEVICE_RETRY_GENERAL));
      fpi_device_verify_complete (dev, NULL);
      return;
    }

  best = t->best;
  fpi_device_get_verify_data (dev, &template);
  views = gx_views_from_print (template);
  fp_info ("verify: %d matches in %d attempt(s) "
           "(threshold %d, %u enrolled views)", best, t->tries,
           GX_MATCH_THRESHOLD, views->len);

  /* Defensive fallback for paths that reached completion without a usable
   * capture-side report. The normal production path reports before WAIT_OFF. */
  if (!t->match_reported)
    fpi_device_verify_report (dev,
                              best >= GX_MATCH_THRESHOLD ? FPI_MATCH_SUCCESS
                                                         : FPI_MATCH_FAIL,
                              NULL, NULL);
  fpi_device_verify_complete (dev, NULL);
}

static void
gx_identify_done (FpiSsm *ssm, FpDevice *dev, GError *error)
{
  GxTask *t = fpi_ssm_get_data (ssm);

  if (error)
    {
      if (t->match_reported &&
          g_error_matches (error, G_IO_ERROR, G_IO_ERROR_CANCELLED))
        {
          fp_info ("identify: caller stopped operation after early result");
          g_clear_error (&error);
          fpi_device_identify_complete (dev, NULL);
          return;
        }

      if (error->domain == FP_DEVICE_RETRY)
        {
          fpi_device_identify_report (dev, NULL, NULL,
                                      g_steal_pointer (&error));
          fpi_device_identify_complete (dev, NULL);
          return;
        }

      fpi_device_identify_complete (dev, error);
      return;
    }

  if (!t->probe)
    {
      fpi_device_identify_report (dev, NULL, NULL,
                                  fpi_device_retry_new (FP_DEVICE_RETRY_GENERAL));
      fpi_device_identify_complete (dev, NULL);
      return;
    }

  if (!t->match_reported)
    fpi_device_identify_report (dev,
                                t->best >= GX_MATCH_THRESHOLD
                                  ? t->identify_match
                                  : NULL,
                                NULL, NULL);

  fpi_device_identify_complete (dev, NULL);
}

static void
gx_dev_enroll (FpDevice *dev)
{
  FpiSsm *ssm = fpi_ssm_new (dev, gx_run_state, GX_ST_NUM);
  GxTask *t = g_new0 (GxTask, 1);
  FpPrint *print = NULL;
  FpiPrintType ptype = FPI_PRINT_UNDEFINED;

  t->views = g_ptr_array_new_with_free_func ((GDestroyNotify) gx_sift_free);

  /* Updating an existing print: keep its views and add the new ones.
   * Note this path is unused with fprintd, whose enrol always supplies a fresh
   * FpPrint, so in practice re-enrolling REPLACES the template. */
  fpi_device_get_enroll_data (dev, &print);
  if (print)
    g_object_get (print, "fpi-type", &ptype, NULL);
  if (ptype != FPI_PRINT_UNDEFINED)
    {
      g_autoptr(GPtrArray) old = gx_views_from_print (print);
      guint i;
      for (i = 0; i < old->len; i++)
        g_ptr_array_add (t->views, g_ptr_array_index (old, i));
      g_ptr_array_set_free_func (old, NULL);   /* ownership transferred */
      if (t->views->len)
        fp_info ("enroll: kept %u existing views", t->views->len);
    }
  fpi_ssm_set_data (ssm, t, (GDestroyNotify) gx_task_free);
  fpi_ssm_start (ssm, gx_enroll_done);
}

static void
gx_dev_verify (FpDevice *dev)
{
  FpiSsm *ssm = fpi_ssm_new (dev, gx_run_state, GX_ST_NUM);
  GxTask *t = g_new0 (GxTask, 1);

  t->verifying = TRUE;
  fpi_ssm_set_data (ssm, t, (GDestroyNotify) gx_task_free);
  fpi_ssm_start (ssm, gx_verify_done);
}

static void
gx_dev_identify (FpDevice *dev)
{
  FpiSsm *ssm = fpi_ssm_new (dev, gx_run_state, GX_ST_NUM);
  GxTask *t = g_new0 (GxTask, 1);

  t->verifying = TRUE;
  t->identifying = TRUE;
  fpi_ssm_set_data (ssm, t, (GDestroyNotify) gx_task_free);
  fpi_ssm_start (ssm, gx_identify_done);
}

/* ------------------------------------------------------------------ */

static void
fpi_device_goodix51a0_init (FpiDeviceGoodix51A0 *self)
{
  self->spi_fd = -1;
  self->irq_fd = -1;
  self->capture_gap_scale = 0; /* loaded lazily from root-owned state */
  self->capture_gap_saved = 0;
  self->capture_clean_streak = 0;
  self->capture_retry_seen = FALSE;
  self->capture_pacing_suppressed = FALSE;
  self->capture_recovery_pending = FALSE;
  self->warm_sleep_delta_us = 0;
  self->warm_sleep_clock_valid = FALSE;
  self->force_cold_reset = FALSE;
}


static void
fpi_device_goodix51a0_finalize (GObject *object)
{
  FpiDeviceGoodix51A0 *self = FPI_DEVICE_GOODIX51A0 (object);

  if (self->force_cold_reset)
    gx_warm_abandon (self);
  else
    gx_warm_discard (self);
  gx_transport_close (self);
  G_OBJECT_CLASS (fpi_device_goodix51a0_parent_class)->finalize (object);
}


static void
fpi_device_goodix51a0_class_init (FpiDeviceGoodix51A0Class *klass)
{
  FpDeviceClass *dev_class = FP_DEVICE_CLASS (klass);

  dev_class->id = "goodix51a0";
  dev_class->full_name = "Goodix GXFP51A0 SPI (ST411 / experimental)";
  dev_class->type = FP_DEVICE_TYPE_UDEV;
  dev_class->id_table = goodix51a0_id_table;
  dev_class->scan_type = FP_SCAN_TYPE_PRESS;
  dev_class->nr_enroll_stages = GX_ENROLL_STAGES;

  dev_class->temp_hot_seconds = -1;   /* slow capture: no thermal throttling */

  dev_class->probe = gx_dev_probe;
  dev_class->open = gx_dev_open;
  dev_class->close = gx_dev_close;
  dev_class->suspend = gx_dev_suspend;
  dev_class->resume = gx_dev_resume;
  dev_class->enroll = gx_dev_enroll;
  dev_class->verify = gx_dev_verify;
  dev_class->identify = gx_dev_identify;

  G_OBJECT_CLASS (klass)->finalize = fpi_device_goodix51a0_finalize;

  /* Derives the advertised features from the vfuncs implemented above.
   * Must be called LAST: otherwise the device is announced without
   * verification support. FpImageDevice did this for us; deriving straight
   * from FpDevice makes it the driver's job. */
  fpi_device_class_auto_initialize_features (dev_class);

  /* Advertise that an existing print can be updated rather than replaced,
   * for callers that pass one in. */
  dev_class->features |= FP_DEVICE_FEATURE_UPDATE_PRINT;
}
