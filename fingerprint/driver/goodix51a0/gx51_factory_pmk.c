#include "gx51_factory_pmk.h"

#include <string.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>

static const uint8_t goodix_fallback_seed[16] = {
  0x5c, 0xba, 0x6e, 0x25, 0x81, 0x95, 0x18, 0xde,
  0x2d, 0x53, 0xe9, 0x6d, 0xc0, 0x34, 0x7a, 0xb0
};

bool
gxfp_factory_body_sha256 (const uint8_t *body,
                          size_t body_len,
                          uint8_t hash[32])
{
  unsigned int n = 0;

  if (!body || !hash)
    return false;

  return EVP_Digest (body, body_len, hash, &n, EVP_sha256 (), NULL) == 1 && n == 32;
}

static bool
derive_factory_key (const uint8_t salt[GXFP_FACTORY_SALT_LEN], uint8_t key[16])
{
  uint8_t input[80] = {0};
  uint8_t digest[32];
  unsigned int n = 0;
  bool ok;

  memcpy (input, salt, GXFP_FACTORY_SALT_LEN);
  memcpy (input + 64, goodix_fallback_seed, sizeof goodix_fallback_seed);
  ok = EVP_Digest (input, sizeof input, digest, &n, EVP_sha256 (), NULL) == 1 && n == 32;
  if (ok)
    memcpy (key, digest, 16);

  OPENSSL_cleanse (digest, sizeof digest);
  OPENSSL_cleanse (input, sizeof input);
  return ok;
}

static uint32_t
read_be32 (const uint8_t *p)
{
  return ((uint32_t) p[0] << 24) | ((uint32_t) p[1] << 16) |
         ((uint32_t) p[2] << 8) | (uint32_t) p[3];
}

bool
gxfp_factory_pmk_decrypt (const uint8_t *body,
                          size_t body_len,
                          uint8_t pmk[GXFP_FACTORY_PMK_LEN])
{
  EVP_CIPHER_CTX *ctx = NULL;
  uint8_t key[16], plain[64];
  int out1 = 0, out2 = 0;
  bool ok = false;

  if (!body || !pmk || body_len < GXFP_FACTORY_BODY_MIN_LEN)
    return false;
  if ((body_len - GXFP_FACTORY_SALT_LEN) != sizeof plain)
    return false;
  if (!derive_factory_key (body, key))
    return false;

  ctx = EVP_CIPHER_CTX_new ();
  if (!ctx)
    goto out;
  if (EVP_DecryptInit_ex (ctx, EVP_aes_128_cbc (), NULL, key, body) != 1)
    goto out;
  if (EVP_CIPHER_CTX_set_padding (ctx, 0) != 1)
    goto out;
  if (EVP_DecryptUpdate (ctx, plain, &out1,
                         body + GXFP_FACTORY_SALT_LEN,
                         (int) (body_len - GXFP_FACTORY_SALT_LEN)) != 1)
    goto out;
  if (EVP_DecryptFinal_ex (ctx, plain + out1, &out2) != 1)
    goto out;
  if (out1 + out2 != (int) sizeof plain)
    goto out;

  if (plain[0] != 0x00 || plain[1] != 0x0d)
    goto out;
  if (read_be32 (plain + 2) != GXFP_FACTORY_PMK_LEN)
    goto out;

  memcpy (pmk, plain + 6, GXFP_FACTORY_PMK_LEN);
  ok = true;

out:
  EVP_CIPHER_CTX_free (ctx);
  OPENSSL_cleanse (plain, sizeof plain);
  OPENSSL_cleanse (key, sizeof key);
  if (!ok)
    OPENSSL_cleanse (pmk, GXFP_FACTORY_PMK_LEN);
  return ok;
}

bool
gxfp_factory_pmk_recover_first_byte (
  const uint8_t *damaged_body,
  size_t body_len,
  uint8_t *recovered_first_byte,
  uint8_t pmk[GXFP_FACTORY_PMK_LEN])
{
  uint8_t candidate_body[GXFP_FACTORY_BODY_MIN_LEN];
  uint8_t candidate_pmk[GXFP_FACTORY_PMK_LEN];
  unsigned int hits = 0;
  uint8_t found = 0;

  if (!damaged_body || !recovered_first_byte || !pmk ||
      body_len != GXFP_FACTORY_BODY_MIN_LEN)
    return false;

  memcpy (candidate_body, damaged_body, body_len);
  for (unsigned int i = 0; i <= 0xffu; i++)
    {
      candidate_body[0] = (uint8_t) i;
      if (!gxfp_factory_pmk_decrypt (candidate_body, body_len, candidate_pmk))
        continue;
      hits++;
      found = (uint8_t) i;
      memcpy (pmk, candidate_pmk, GXFP_FACTORY_PMK_LEN);
    }

  OPENSSL_cleanse (candidate_pmk, sizeof candidate_pmk);
  OPENSSL_cleanse (candidate_body, sizeof candidate_body);

  if (hits != 1)
    {
      OPENSSL_cleanse (pmk, GXFP_FACTORY_PMK_LEN);
      return false;
    }

  *recovered_first_byte = found;
  return true;
}

bool
gxfp_factory_pmk_recover_verified (
  const uint8_t *damaged_body,
  size_t body_len,
  const uint8_t expected_hash[32],
  uint8_t pmk[GXFP_FACTORY_PMK_LEN])
{
  uint8_t corrected[GXFP_FACTORY_BODY_MIN_LEN];
  uint8_t actual_hash[32];
  uint8_t first = 0;
  bool ok = false;

  if (!damaged_body || !expected_hash || !pmk ||
      body_len != GXFP_FACTORY_BODY_MIN_LEN)
    return false;
  if (!gxfp_factory_pmk_recover_first_byte (damaged_body, body_len,
                                             &first, pmk))
    return false;

  memcpy (corrected, damaged_body, body_len);
  corrected[0] = first;
  if (gxfp_factory_body_sha256 (corrected, body_len, actual_hash) &&
      CRYPTO_memcmp (actual_hash, expected_hash, sizeof actual_hash) == 0)
    ok = true;

  OPENSSL_cleanse (corrected, sizeof corrected);
  OPENSSL_cleanse (actual_hash, sizeof actual_hash);
  if (!ok)
    OPENSSL_cleanse (pmk, GXFP_FACTORY_PMK_LEN);
  return ok;
}

bool
gxfp_factory_load_pmk (GxfpFactoryMemRead mem_read,
                       GxfpFactoryHashRead hash_read,
                       void *user,
                       uint8_t pmk[GXFP_FACTORY_PMK_LEN])
{
  uint8_t expected_hash[32], len_probe[5], body[GXFP_FACTORY_BODY_MIN_LEN];
  uint32_t body_len;
  bool ok = false;

  if (!mem_read || !hash_read || !pmk)
    return false;
  if (!hash_read (user, expected_hash))
    goto out;
  if (!mem_read (user, 0x08008003u, sizeof len_probe, len_probe))
    goto out;

  body_len = (uint32_t) len_probe[1] |
             ((uint32_t) len_probe[2] << 8) |
             ((uint32_t) len_probe[3] << 16) |
             ((uint32_t) len_probe[4] << 24);
  if (body_len != GXFP_FACTORY_BODY_MIN_LEN)
    goto out;
  if (!mem_read (user, 0x08008008u, body_len, body))
    goto out;
  ok = gxfp_factory_pmk_recover_verified (body, body_len,
                                           expected_hash, pmk);

out:
  OPENSSL_cleanse (expected_hash, sizeof expected_hash);
  OPENSSL_cleanse (len_probe, sizeof len_probe);
  OPENSSL_cleanse (body, sizeof body);
  if (!ok)
    OPENSSL_cleanse (pmk, GXFP_FACTORY_PMK_LEN);
  return ok;
}
