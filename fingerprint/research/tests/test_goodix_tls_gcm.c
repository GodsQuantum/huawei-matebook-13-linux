#include "../../driver/goodix51a0/goodix_tls.h"

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/hmac.h>
#include <openssl/crypto.h>

#define TEST_PSK_LEN 48
#define TEST_PAYLOAD_LEN 10600
#define TEST_OVERSIZE_LEN 22176

typedef struct {
    int fd;
    guint8 psk[TEST_PSK_LEN];
    guint8 payload[TEST_PAYLOAD_LEN];
    guint8 oversized[TEST_OVERSIZE_LEN];
    int ok;
    int extms;
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


static void tls_prf(const guint8 *secret, gsize secret_len,
                    const char *label, const guint8 *seed, gsize seed_len,
                    guint8 *out, gsize out_len)
{
    size_t ll = strlen(label), done = 0;
    guint8 ls[128], a[EVP_MAX_MD_SIZE], block[EVP_MAX_MD_SIZE];
    unsigned int al = 0, bl = 0;
    assert(ll + seed_len <= sizeof ls);
    memcpy(ls, label, ll); memcpy(ls + ll, seed, seed_len);
    HMAC(EVP_sha256(), secret, (int)secret_len, ls, ll + seed_len, a, &al);
    while (done < out_len) {
        guint8 tmp[256]; size_t take;
        assert(al + ll + seed_len <= sizeof tmp);
        memcpy(tmp, a, al); memcpy(tmp + al, ls, ll + seed_len);
        HMAC(EVP_sha256(), secret, (int)secret_len, tmp, al + ll + seed_len, block, &bl);
        take = bl < out_len - done ? bl : out_len - done;
        memcpy(out + done, block, take); done += take;
        HMAC(EVP_sha256(), secret, (int)secret_len, a, al, a, &al);
    }
}

static int derive_client_material(SSL *ssl, guint8 key[16], guint8 iv[4])
{
    SSL_SESSION *sess = SSL_get_session(ssl);
    guint8 master[48], cr[32], sr[32], seed[64], kb[40];
    if (!sess || SSL_SESSION_get_master_key(sess, master, sizeof master) != sizeof master) return 0;
    if (SSL_get_client_random(ssl, cr, sizeof cr) != sizeof cr ||
        SSL_get_server_random(ssl, sr, sizeof sr) != sizeof sr) return 0;
    memcpy(seed, sr, 32); memcpy(seed + 32, cr, 32);
    tls_prf(master, sizeof master, "key expansion", seed, sizeof seed, kb, sizeof kb);
    memcpy(key, kb, 16); memcpy(iv, kb + 32, 4);
    OPENSSL_cleanse(master, sizeof master); OPENSSL_cleanse(kb, sizeof kb);
    return 1;
}

static size_t make_gcm_record(SSL *ssl, uint64_t seq, const guint8 *plain, size_t plen,
                              guint8 *raw, size_t cap)
{
    guint8 key[16], fixed[4], nonce[12], aad[13], explicit_nonce[8], tag[16];
    EVP_CIPHER_CTX *ctx = NULL; int n = 0, fin = 0; size_t body = 8 + plen + 16;
    if (cap < body + 5 || body > 0xffff || !derive_client_material(ssl, key, fixed)) return 0;
    for (int i = 0; i < 8; i++) explicit_nonce[i] = (guint8)(seq >> (56 - 8 * i));
    memcpy(nonce, fixed, 4); memcpy(nonce + 4, explicit_nonce, 8);
    memcpy(aad, explicit_nonce, 8); aad[8]=0x17; aad[9]=0x03; aad[10]=0x03;
    aad[11]=(guint8)(plen >> 8); aad[12]=(guint8)plen;
    raw[0]=0x17; raw[1]=0x03; raw[2]=0x03; raw[3]=(guint8)(body >> 8); raw[4]=(guint8)body;
    memcpy(raw + 5, explicit_nonce, 8);
    ctx = EVP_CIPHER_CTX_new(); if (!ctx) return 0;
    if (EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL) != 1 ||
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, sizeof nonce, NULL) != 1 ||
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, nonce) != 1 ||
        EVP_EncryptUpdate(ctx, NULL, &n, aad, sizeof aad) != 1 ||
        EVP_EncryptUpdate(ctx, raw + 13, &n, plain, (int)plen) != 1 ||
        EVP_EncryptFinal_ex(ctx, raw + 13 + n, &fin) != 1 ||
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, sizeof tag, tag) != 1) { EVP_CIPHER_CTX_free(ctx); return 0; }
    memcpy(raw + 13 + plen, tag, sizeof tag); EVP_CIPHER_CTX_free(ctx);
    OPENSSL_cleanse(key, sizeof key); return body + 5;
}

static int write_exact_all(int fd, const guint8 *buf, size_t len)
{
    size_t off=0; while (off<len) { ssize_t n=write(fd,buf+off,len-off); if(n<=0)return -1; off+=(size_t)n; } return 0;
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
    c->extms = SSL_get_extms_support(ssl);
    { char gate; if (read(c->gate_fd, &gate, 1) != 1) goto out; }
    if (SSL_write(ssl, c->payload, TEST_PAYLOAD_LEN) != TEST_PAYLOAD_LEN) goto out;
    {
        guint8 raw[TEST_OVERSIZE_LEN + 64];
        size_t rn = make_gcm_record(ssl, 2, c->oversized, TEST_OVERSIZE_LEN, raw, sizeof raw);
        if (!rn || write_exact_all(c->fd, raw, rn) != 0) goto out;
    }
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
    guint8 hdr[5], raw[TEST_OVERSIZE_LEN + 128], plain[TEST_OVERSIZE_LEN + 32];
    guint16 record_len;
    gssize plain_len;

    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    assert(pipe(gate) == 0);
    client.fd = fds[1];
    client.gate_fd = gate[0];
    for (size_t i = 0; i < TEST_PSK_LEN; i++) client.psk[i] = (guint8)(0x31 + i);
    for (size_t i = 0; i < TEST_PAYLOAD_LEN; i++) client.payload[i] = (guint8)(i * 17u + 3u);
    for (size_t i = 0; i < TEST_OVERSIZE_LEN; i++) client.oversized[i] = (guint8)(i * 29u + 7u);

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

    assert(read_exact(fds[0], hdr, sizeof hdr) == 0);
    record_len = ((guint16)hdr[3] << 8) | hdr[4];
    assert(record_len == TEST_OVERSIZE_LEN + 24);
    memcpy(raw, hdr, 5);
    assert(read_exact(fds[0], raw + 5, record_len) == 0);
    plain_len = gx_tls_decrypt_record(server, raw, (gsize)record_len + 5, plain, sizeof plain);
    assert(plain_len == TEST_OVERSIZE_LEN);
    assert(memcmp(plain, client.oversized, TEST_OVERSIZE_LEN) == 0);

    assert(pthread_join(thread, NULL) == 0);
    assert(client.ok == 1);
    assert(client.extms == 0);
    gx_tls_free(server);
    close(fds[0]);
    close(fds[1]);
    close(gate[0]);
    close(gate[1]);
    puts("test_goodix_tls_gcm: OK");
    return 0;
}
