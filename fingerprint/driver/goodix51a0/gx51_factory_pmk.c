#include "gx51_factory_pmk.h"

#include <string.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>

static const uint8_t goodix_fallback_seed[16] = {
  0x5c, 0xba, 0x6e, 0x25, 0x81, 0x95, 0x18, 0xde,
  0x2d, 0x53, 0xe9, 0x6d, 0xc0, 0x34, 0x7a, 0xb0
};

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
  uint8_t key[16], plain[GXFP_FACTORY_BODY_LEN - GXFP_FACTORY_SALT_LEN];
  int out1 = 0, out2 = 0;
  bool ok = false;

  if (!body || !pmk || body_len < GXFP_FACTORY_READ_LEN ||
      body_len > GXFP_FACTORY_BODY_LEN ||
      ((body_len - GXFP_FACTORY_SALT_LEN) % 16u) != 0u)
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
                         body_len - GXFP_FACTORY_SALT_LEN) != 1)
    goto out;
  if (EVP_DecryptFinal_ex (ctx, plain + out1, &out2) != 1)
    goto out;
  if (out1 + out2 != (int) (body_len - GXFP_FACTORY_SALT_LEN))
    goto out;
  if (plain[0] != 0x00 || plain[1] != 0x0d ||
      read_be32 (plain + 2) != GXFP_FACTORY_PMK_LEN)
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
gxfp_factory_pmk_recover_first_byte (const uint8_t *damaged_body,
                                     size_t body_len,
                                     uint8_t *recovered_first_byte,
                                     uint8_t pmk[GXFP_FACTORY_PMK_LEN])
{
  uint8_t candidate_body[GXFP_FACTORY_BODY_LEN];
  uint8_t candidate_pmk[GXFP_FACTORY_PMK_LEN];
  unsigned int hits = 0;
  uint8_t found = 0;

  if (!damaged_body || !recovered_first_byte || !pmk ||
      body_len < GXFP_FACTORY_READ_LEN || body_len > GXFP_FACTORY_BODY_LEN ||
      ((body_len - GXFP_FACTORY_SALT_LEN) % 16u) != 0u)
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
gxfp_factory_load_pmk (GxfpFactoryMemRead mem_read,
                       void *user,
                       uint8_t pmk[GXFP_FACTORY_PMK_LEN])
{
  static const uint32_t bases[] = {0x08004000u, 0x08008000u, 0x0800a000u};
  uint8_t body[GXFP_FACTORY_READ_LEN];
  uint8_t candidates[3][GXFP_FACTORY_PMK_LEN];
  bool valid[3] = {false, false, false};
  bool ok = false;

  if (!mem_read || !pmk)
    return false;

  /* The firmware's own PMK loader passes factory_base + 8 to the decryptor.
   * Only the first 80 bytes are needed here: 16-byte salt plus four CBC
   * blocks, enough for marker(2) + length(4) + the 48-byte PMK.  Avoid a
   * separate F2 header read entirely; standalone F2 request echoes made that
   * observation ambiguous on Pegasus. */
  for (size_t i = 0; i < 3; i++)
    {
      uint8_t first = 0;
      memset (body, 0, sizeof body);
      if (!mem_read (user, bases[i] + 8u, sizeof body, body))
        continue;
      valid[i] = gxfp_factory_pmk_recover_first_byte (body, sizeof body,
                                                       &first, candidates[i]);
    }

  for (size_t i = 0; i < 3 && !ok; i++)
    for (size_t j = i + 1; j < 3 && !ok; j++)
      if (valid[i] && valid[j] &&
          CRYPTO_memcmp (candidates[i], candidates[j], GXFP_FACTORY_PMK_LEN) == 0)
        {
          memcpy (pmk, candidates[i], GXFP_FACTORY_PMK_LEN);
          ok = true;
        }

  OPENSSL_cleanse (body, sizeof body);
  OPENSSL_cleanse (candidates, sizeof candidates);
  if (!ok)
    OPENSSL_cleanse (pmk, GXFP_FACTORY_PMK_LEN);
  return ok;
}
