#include "../../driver/goodix51a0/goodix_tls.h"

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include <openssl/ssl.h>
#include <openssl/err.h>

#define TEST_PSK_LEN 48
#define TEST_PAYLOAD_LEN 10600

typedef struct {
    int fd;
    guint8 psk[TEST_PSK_LEN];
    guint8 payload[TEST_PAYLOAD_LEN];
    int ok;
    int gate_fd;
} ClientCtx;

static int transport_send(gpointer user, const guint8 *buf, gsize len)
{
    int fd = *(int *) user;
    ssize_t n = write(fd, buf, len);
    return n > 0 ? (int)n : -1;
}

static int transport_recv(gpointer user, guint8 *buf, gsize cap)
{
    int fd = *(int *) user;
    ssize_t n = read(fd, buf, cap);
    return n > 0 ? (int)n : -1;
}
static unsigned int client_psk_cb(SSL *ssl, const char *hint,
                                  char *identity, unsigned int max_identity_len,
                                  unsigned char *psk, unsigned int max_psk_len)
{
    ClientCtx *c = SSL_get_app_data(ssl);
    const char *id = "Client_identity";
    (void)hint;
    if (!c || strlen(id) + 1 > max_identity_len || TEST_PSK_LEN > max_psk_len)
        return 0;
    strcpy(identity, id);
    memcpy(psk, c->psk, TEST_PSK_LEN);
    return TEST_PSK_LEN;
}

static void *client_main(void *arg)
{
    ClientCtx *c = arg;
    SSL_CTX *ctx = NULL;
    SSL *ssl = NULL;

    ctx = SSL_CTX_new(TLS_client_method());
    if (!ctx) goto out;
    SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION);
    SSL_CTX_set_max_proto_version(ctx, TLS1_2_VERSION);
    if (SSL_CTX_set_cipher_list(ctx, "PSK-AES128-GCM-SHA256") != 1) goto out;
    SSL_CTX_set_psk_client_callback(ctx, client_psk_cb);
    ssl = SSL_new(ctx);
    if (!ssl) goto out;
    SSL_set_app_data(ssl, c);
    SSL_set_fd(ssl, c->fd);
    if (SSL_connect(ssl) != 1) goto out;
    if (strcmp(SSL_get_cipher(ssl), "PSK-AES128-GCM-SHA256") != 0) goto out;
    { char gate; if (read(c->gate_fd, &gate, 1) != 1) goto out; }
    if (SSL_write(ssl, c->payload, TEST_PAYLOAD_LEN) != TEST_PAYLOAD_LEN) goto out;
    c->ok = 1;
out:
    if (ssl) SSL_free(ssl);
    if (ctx) SSL_CTX_free(ctx);
    return NULL;
}
static int read_exact(int fd, guint8 *buf, size_t len)
{
    size_t off = 0;
    while (off < len) {
        ssize_t n = read(fd, buf + off, len - off);
        if (n <= 0) return -1;
        off += (size_t)n;
    }
    return 0;
}

int main(void)
{
    int fds[2], gate[2];
    pthread_t thread;
    ClientCtx client = {0};
    GxTls *server;
    g_autoptr(GError) error = NULL;
    guint8 hdr[5], raw[TEST_PAYLOAD_LEN + 128], plain[TEST_PAYLOAD_LEN + 32];
    guint16 record_len;
    gssize plain_len;

    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    assert(pipe(gate) == 0);
    client.fd = fds[1];
    client.gate_fd = gate[0];
    for (size_t i = 0; i < TEST_PSK_LEN; i++) client.psk[i] = (guint8)(0x31 + i);
    for (size_t i = 0; i < TEST_PAYLOAD_LEN; i++) client.payload[i] = (guint8)(i * 17u + 3u);

    server = gx_tls_new(client.psk, TEST_PSK_LEN, "Client_identity",
                        transport_send, transport_recv, &fds[0]);
    assert(server != NULL);
    assert(pthread_create(&thread, NULL, client_main, &client) == 0);

    assert(gx_tls_handshake_run(server, &error));
    assert(error == NULL);
    assert(strcmp(gx_tls_ciphersuite(server), "PSK-AES128-GCM-SHA256") == 0);
    assert(write(gate[1], "x", 1) == 1);
    assert(read_exact(fds[0], hdr, sizeof hdr) == 0);
    assert(hdr[0] == 0x17 && hdr[1] == 0x03 && hdr[2] == 0x03);
    record_len = ((guint16)hdr[3] << 8) | hdr[4];
    assert(record_len > TEST_PAYLOAD_LEN && (size_t) record_len + 5u <= sizeof raw);
    memcpy(raw, hdr, 5);
    assert(read_exact(fds[0], raw + 5, record_len) == 0);

    plain_len = gx_tls_decrypt_record(server, raw, (gsize)record_len + 5,
                                      plain, sizeof plain);
    assert(plain_len == TEST_PAYLOAD_LEN);
    assert(memcmp(plain, client.payload, TEST_PAYLOAD_LEN) == 0);

    assert(pthread_join(thread, NULL) == 0);
    assert(client.ok == 1);
    gx_tls_free(server);
    close(fds[0]);
    close(fds[1]);
    close(gate[0]);
    close(gate[1]);
    puts("test_goodix_tls_gcm: OK");
    return 0;
}
