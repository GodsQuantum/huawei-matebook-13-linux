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

/*
 * Exact GXFP51A0 Windows traffic negotiates TLS 1.2 ciphersuite 0x00A8,
 * TLS_PSK_WITH_AES_128_GCM_SHA256. The sensor is the TLS CLIENT and the host
 * is the server. The PSK identity is "Client_identity".
 *
 * Target TLS records observed during the working Windows session fit inside
 * the standard TLS 1.2 record limit (the large captured record is ~10.6 kB),
 * so stock OpenSSL can authenticate/decrypt them. The SPI layer sometimes
 * hands us an already framed raw TLS record; gx_tls_decrypt_record() injects
 * that complete record back into the OpenSSL BIO and lets SSL_read() perform
 * the AEAD/GCM record processing.
 */
#pragma once

#include <gio/gio.h>

typedef struct _GxTls GxTls;

typedef int (*GxTlsSend) (gpointer user, const guint8 *buf, gsize len);
typedef int (*GxTlsRecv) (gpointer user, guint8 *buf, gsize cap);

GxTls *gx_tls_new (const guint8 *psk, gsize psk_len, const gchar *identity,
                   GxTlsSend send, GxTlsRecv recv, gpointer user);
void   gx_tls_free (GxTls *tls);

/* Runs the server side of the TLS 1.2 PSK-GCM handshake. */
gboolean gx_tls_handshake_run (GxTls *tls, GError **error);

/* Name of the negotiated ciphersuite, for logging and validation. */
const gchar *gx_tls_ciphersuite (GxTls *tls);

/* Sends application data through OpenSSL. */
gboolean gx_tls_write (GxTls *tls, const guint8 *buf, gsize len);

/* Authenticates/decrypts one complete raw TLS application-data record by
 * feeding it back through the established OpenSSL session. */
gssize gx_tls_decrypt_record (GxTls *tls, const guint8 *raw, gsize raw_len,
                              guint8 *out, gsize out_cap);

void gx_tls_close (GxTls *tls);
