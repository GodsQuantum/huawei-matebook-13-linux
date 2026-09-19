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
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <openssl/crypto.h>

#include "goodix_tls.h"

#define GCM_KEY_LEN             16u
#define GCM_FIXED_IV_LEN         4u
#define GCM_EXPLICIT_NONCE_LEN   8u
#define GCM_NONCE_LEN           12u
#define GCM_TAG_LEN             16u
#define GCM_KEY_BLOCK_LEN       40u

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

  /* TLS 1.2 PSK-AES128-GCM traffic material. The sensor is the client,
   * therefore image records use the client_write key and fixed IV. */
  guint8     client_key[GCM_KEY_LEN];
  guint8     server_key[GCM_KEY_LEN];
  guint8     client_iv[GCM_FIXED_IV_LEN];
  guint8     server_iv[GCM_FIXED_IV_LEN];
  guint64    read_seq;
  gboolean   keys_ready;

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
/*  TLS 1.2 key expansion for PSK-AES128-GCM-SHA256                  */
/* ------------------------------------------------------------------ */

static void
tls_prf (const guint8 *secret, gsize secret_len,
         const gchar *label, const guint8 *seed, gsize seed_len,
         guint8 *out, gsize out_len)
{
  gsize label_len = strlen (label);
  g_autofree guint8 *ls = g_malloc (label_len + seed_len);
  guint8 a[EVP_MAX_MD_SIZE];
  unsigned int a_len = 0;
  gsize done = 0;

  memcpy (ls, label, label_len);
  memcpy (ls + label_len, seed, seed_len);
  HMAC (EVP_sha256 (), secret, (int) secret_len,
        ls, label_len + seed_len, a, &a_len);

  while (done < out_len)
    {
      guint8 block[EVP_MAX_MD_SIZE];
      unsigned int block_len = 0;
      g_autofree guint8 *tmp = g_malloc (a_len + label_len + seed_len);
      gsize take;

      memcpy (tmp, a, a_len);
      memcpy (tmp + a_len, ls, label_len + seed_len);
      HMAC (EVP_sha256 (), secret, (int) secret_len, tmp,
            a_len + label_len + seed_len, block, &block_len);
      take = MIN ((gsize) block_len, out_len - done);
      memcpy (out + done, block, take);
      done += take;
      HMAC (EVP_sha256 (), secret, (int) secret_len,
            a, a_len, a, &a_len);
      OPENSSL_cleanse (block, sizeof block);
    }
  OPENSSL_cleanse (a, sizeof a);
}

static gboolean
derive_record_keys (GxTls *t, GError **error)
{
  SSL_SESSION *sess = SSL_get_session (t->ssl);
  guint8 master[48], cr[32], sr[32], seed[64], kb[GCM_KEY_BLOCK_LEN];
  gsize n;

  if (!sess)
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED, "no TLS session");
      return FALSE;
    }
  n = SSL_SESSION_get_master_key (sess, master, sizeof master);
  if (n != sizeof master ||
      SSL_get_client_random (t->ssl, cr, sizeof cr) != sizeof cr ||
      SSL_get_server_random (t->ssl, sr, sizeof sr) != sizeof sr)
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                   "cannot derive TLS 1.2 record keys");
      return FALSE;
    }

  memcpy (seed, sr, 32);
  memcpy (seed + 32, cr, 32);
  tls_prf (master, sizeof master, "key expansion", seed, sizeof seed,
           kb, sizeof kb);
  memcpy (t->client_key, kb, GCM_KEY_LEN);
  memcpy (t->server_key, kb + GCM_KEY_LEN, GCM_KEY_LEN);
  memcpy (t->client_iv, kb + 2 * GCM_KEY_LEN, GCM_FIXED_IV_LEN);
  memcpy (t->server_iv, kb + 2 * GCM_KEY_LEN + GCM_FIXED_IV_LEN,
          GCM_FIXED_IV_LEN);

  /* After ChangeCipherSpec the client's Finished is encrypted at sequence 0.
   * The first post-handshake application record is therefore sequence 1. */
  t->read_seq = 1;
  t->keys_ready = TRUE;
  OPENSSL_cleanse (master, sizeof master);
  OPENSSL_cleanse (kb, sizeof kb);
  return TRUE;
}

/* ------------------------------------------------------------------ */
/*  Handshake                                                          */
/* ------------------------------------------------------------------ */

static void
tls_msg_trace_cb (int write_p, int version, int content_type,
                  const void *buf, size_t len, SSL *ssl, void *arg)
{
  const guint8 *p = buf;
  int handshake_type = -1;

  (void) version;
  (void) ssl;
  (void) arg;

  if (content_type == SSL3_RT_HANDSHAKE && len > 0)
    handshake_type = p[0];

  g_debug ("GXFP51A0 TLS trace: %s content=%d handshake=%d len=%zu",
           write_p ? "host->sensor" : "sensor->host",
           content_type, handshake_type, len);
}


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
  /* ST411SEC_APP_14115 uses the classic TLS 1.2 PRF; EMS must stay off. */
  SSL_CTX_set_options (t->ctx, SSL_OP_NO_EXTENDED_MASTER_SECRET);
  if (!SSL_CTX_set_cipher_list (t->ctx, "PSK-AES128-GCM-SHA256"))
    {
      g_set_error (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                   "PSK-AES128-GCM-SHA256 unavailable in this OpenSSL build");
      return FALSE;
    }
  SSL_CTX_set_psk_server_callback (t->ctx, psk_server_cb);
  SSL_CTX_set_msg_callback (t->ctx, tls_msg_trace_cb);
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
  return derive_record_keys (t, error);
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
  EVP_CIPHER_CTX *c = NULL;
  const guint8 *body, *cipher, *tag;
  guint8 nonce[GCM_NONCE_LEN], aad[13];
  gsize body_len, cipher_len;
  int n = 0, fin = 0;
  gssize result = -1;

  if (!t || !t->ssl || !t->keys_ready || !raw || !out || raw_len < 5)
    return -1;
  if (raw[0] != 0x17 || raw[1] != 0x03 || raw[2] != 0x03)
    return -1;

  body_len = ((gsize) raw[3] << 8) | raw[4];
  if (body_len + 5 != raw_len ||
      body_len < GCM_EXPLICIT_NONCE_LEN + GCM_TAG_LEN)
    return -1;
  cipher_len = body_len - GCM_EXPLICIT_NONCE_LEN - GCM_TAG_LEN;
  if (cipher_len > out_cap || cipher_len > G_MAXINT)
    return -1;

  body = raw + 5;
  cipher = body + GCM_EXPLICIT_NONCE_LEN;
  tag = cipher + cipher_len;
  memcpy (nonce, t->client_iv, GCM_FIXED_IV_LEN);
  memcpy (nonce + GCM_FIXED_IV_LEN, body, GCM_EXPLICIT_NONCE_LEN);

  for (int i = 0; i < 8; i++)
    aad[i] = (guint8) (t->read_seq >> (56 - 8 * i));
  aad[8] = raw[0];
  aad[9] = raw[1];
  aad[10] = raw[2];
  aad[11] = (guint8) (cipher_len >> 8);
  aad[12] = (guint8) cipher_len;

  c = EVP_CIPHER_CTX_new ();
  if (!c)
    goto out;
  if (EVP_DecryptInit_ex (c, EVP_aes_128_gcm (), NULL, NULL, NULL) != 1 ||
      EVP_CIPHER_CTX_ctrl (c, EVP_CTRL_GCM_SET_IVLEN, sizeof nonce, NULL) != 1 ||
      EVP_DecryptInit_ex (c, NULL, NULL, t->client_key, nonce) != 1 ||
      EVP_DecryptUpdate (c, NULL, &n, aad, sizeof aad) != 1 ||
      EVP_DecryptUpdate (c, out, &n, cipher, (int) cipher_len) != 1 ||
      EVP_CIPHER_CTX_ctrl (c, EVP_CTRL_GCM_SET_TAG, GCM_TAG_LEN,
                           (void *) tag) != 1 ||
      EVP_DecryptFinal_ex (c, out + n, &fin) != 1)
    goto out;
  if ((gsize) (n + fin) != cipher_len)
    goto out;

  t->read_seq++;
  result = (gssize) cipher_len;

out:
  EVP_CIPHER_CTX_free (c);
  OPENSSL_cleanse (nonce, sizeof nonce);
  OPENSSL_cleanse (aad, sizeof aad);
  if (result < 0 && cipher_len <= out_cap)
    OPENSSL_cleanse (out, cipher_len);
  return result;
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
