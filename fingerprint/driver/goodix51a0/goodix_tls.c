/*
 * TLS-PSK channel for the Goodix GXFP51A0 sensor
 *
 * Copyright (C) 2026 Benjamin Allègre (https://github.com/Sigfrodr)
 *
 * SPDX-License-Identifier: LGPL-2.1-or-later
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
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include <string.h>

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/bio.h>

#include "goodix_tls.h"

struct _GxTls
{
  SSL_CTX   *ctx;
  SSL       *ssl;
  BIO_METHOD *biom;

  GxTlsSend  send;
  GxTlsRecv  recv;
  gpointer   user;

  guint8     psk[64];
  gsize      psk_len;
  gchar     *identity;

  /* Optional complete TLS record injected by gx_tls_decrypt_record().
   * This lets stock OpenSSL authenticate/decrypt GCM records that the SPI
   * layer has already framed separately. */
  const guint8 *inject_buf;
  gsize         inject_len;
  gsize         inject_pos;
  gboolean      inject_active;
};

/* ------------------------------------------------------------------ */
/*  Transport glue                                                     */
/* ------------------------------------------------------------------ */

static int
bio_write_cb (BIO *b, const char *buf, int len)
{
  GxTls *t = BIO_get_data (b);
  int r = t->send (t->user, (const guint8 *) buf, len);

  BIO_clear_retry_flags (b);
  return r > 0 ? r : -1;
}

static int
bio_read_cb (BIO *b, char *buf, int len)
{
  GxTls *t = BIO_get_data (b);
  int r;

  BIO_clear_retry_flags (b);
  if (t->inject_active)
    {
      gsize remain = t->inject_len - t->inject_pos;
      gsize take = MIN ((gsize) len, remain);

      if (take == 0)
        return -1;
      memcpy (buf, t->inject_buf + t->inject_pos, take);
      t->inject_pos += take;
      return (int) take;
    }

  r = t->recv (t->user, (guint8 *) buf, len);
  return r > 0 ? r : -1;
}

static long
bio_ctrl_cb (BIO *b, int cmd, long num, void *ptr)
{
  (void) b;
  (void) num;
  (void) ptr;
  return cmd == BIO_CTRL_FLUSH ? 1 : 0;
}

static int
bio_create_cb (BIO *b)
{
  BIO_set_init (b, 1);
  return 1;
}

/* ------------------------------------------------------------------ */
/*  Handshake                                                          */
/* ------------------------------------------------------------------ */

static unsigned int
psk_server_cb (SSL *ssl, const char *identity, unsigned char *psk,
               unsigned int max_psk_len)
{
  GxTls *t = SSL_get_ex_data (ssl, 0);

  if (!t || !identity || !t->identity ||
      strcmp (identity, t->identity) != 0 ||
      t->psk_len > max_psk_len)
    return 0;
  memcpy (psk, t->psk, t->psk_len);
  return (unsigned int) t->psk_len;
}

GxTls *
gx_tls_new (const guint8 *psk, gsize psk_len, const gchar *identity,
            GxTlsSend send, GxTlsRecv recv, gpointer user)
{
  GxTls *t;

  if (!psk || psk_len == 0 || psk_len > sizeof t->psk)
    return NULL;

  t = g_new0 (GxTls, 1);
  memcpy (t->psk, psk, psk_len);
  t->psk_len = psk_len;
  t->identity = g_strdup (identity);
  t->send = send;
  t->recv = recv;
  t->user = user;
  return t;
}

gboolean
gx_tls_handshake_run (GxTls *t, GError **error)
{
  BIO *bio;
  int r;

  t->ctx = SSL_CTX_new (TLS_server_method ());
  if (!t->ctx)
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED, "SSL_CTX_new failed");
      return FALSE;
    }

  /* GXFP51A0 Windows transcript negotiates TLS 1.2 suite 0x00A8:
   * TLS_PSK_WITH_AES_128_GCM_SHA256. */
  SSL_CTX_set_min_proto_version (t->ctx, TLS1_2_VERSION);
  SSL_CTX_set_max_proto_version (t->ctx, TLS1_2_VERSION);
  if (!SSL_CTX_set_cipher_list (t->ctx, "PSK-AES128-GCM-SHA256"))
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                   "PSK-AES128-GCM-SHA256 unavailable in this OpenSSL build");
      return FALSE;
    }
  SSL_CTX_set_psk_server_callback (t->ctx, psk_server_cb);
  if (t->identity)
    SSL_CTX_use_psk_identity_hint (t->ctx, t->identity);

  t->ssl = SSL_new (t->ctx);
  if (!t->ssl)
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED, "SSL_new failed");
      return FALSE;
    }
  SSL_set_ex_data (t->ssl, 0, t);

  t->biom = BIO_meth_new (BIO_get_new_index () | BIO_TYPE_SOURCE_SINK,
                          "goodix-spi");
  BIO_meth_set_write (t->biom, bio_write_cb);
  BIO_meth_set_read (t->biom, bio_read_cb);
  BIO_meth_set_ctrl (t->biom, bio_ctrl_cb);
  BIO_meth_set_create (t->biom, bio_create_cb);

  bio = BIO_new (t->biom);
  BIO_set_data (bio, t);
  SSL_set_bio (t->ssl, bio, bio);          /* SSL takes ownership */

  r = SSL_accept (t->ssl);
  if (r != 1)
    {
      unsigned long e = ERR_get_error ();
      char buf[256] = "";

      if (e)
        ERR_error_string_n (e, buf, sizeof buf);
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                   "TLS handshake failed (%d/%d) %s", r,
                   SSL_get_error (t->ssl, r), buf);
      return FALSE;
    }
  return TRUE;
}

const gchar *
gx_tls_ciphersuite (GxTls *t)
{
  return t && t->ssl ? SSL_get_cipher (t->ssl) : "none";
}

gboolean
gx_tls_write (GxTls *t, const guint8 *buf, gsize len)
{
  return t && t->ssl && SSL_write (t->ssl, buf, (int) len) == (int) len;
}

/* ------------------------------------------------------------------ */
/*  Record decryption                                                  */
/* ------------------------------------------------------------------ */

gssize
gx_tls_decrypt_record (GxTls *t, const guint8 *raw, gsize raw_len,
                       guint8 *out, gsize out_cap)
{
  gsize body_len;
  int n;

  if (!t || !t->ssl || !raw || !out || raw_len < 5 || out_cap == 0)
    return -1;
  if (raw[0] != 0x17 || raw[1] != 0x03 || raw[2] != 0x03)
    return -1;
  body_len = ((gsize) raw[3] << 8) | raw[4];
  if (body_len + 5 != raw_len)
    return -1;

  t->inject_buf = raw;
  t->inject_len = raw_len;
  t->inject_pos = 0;
  t->inject_active = TRUE;
  ERR_clear_error ();
  n = SSL_read (t->ssl, out, (int) MIN (out_cap, (gsize) G_MAXINT));
  t->inject_active = FALSE;
  t->inject_buf = NULL;
  t->inject_len = 0;
  t->inject_pos = 0;

  return n > 0 ? (gssize) n : -1;
}

void
gx_tls_close (GxTls *t)
{
  if (t && t->ssl)
    SSL_shutdown (t->ssl);
}

void
gx_tls_free (GxTls *t)
{
  if (!t)
    return;
  if (t->ssl)
    SSL_free (t->ssl);                      /* frees the BIO too */
  if (t->ctx)
    SSL_CTX_free (t->ctx);
  if (t->biom)
    BIO_meth_free (t->biom);
  OPENSSL_cleanse (t->psk, sizeof t->psk);
  g_free (t->identity);
  g_free (t);
}
