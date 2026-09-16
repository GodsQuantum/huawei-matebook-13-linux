#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GXFP_FACTORY_PMK_LEN 48u
#define GXFP_FACTORY_SALT_LEN 16u
#define GXFP_FACTORY_BODY_MIN_LEN 80u

bool gxfp_factory_body_sha256 (const uint8_t *body,
                               size_t body_len,
                               uint8_t hash[32]);

bool gxfp_factory_pmk_decrypt (const uint8_t *body,
                               size_t body_len,
                               uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

bool gxfp_factory_pmk_recover_first_byte (
  const uint8_t *damaged_body,
  size_t body_len,
  uint8_t *recovered_first_byte,
  uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

bool gxfp_factory_pmk_recover_verified (
  const uint8_t *damaged_body,
  size_t body_len,
  const uint8_t expected_hash[32],
  uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

typedef bool (*GxfpFactoryMemRead) (void *user, uint32_t address,
                                    uint32_t len, uint8_t *out);
typedef bool (*GxfpFactoryHashRead) (void *user, uint8_t hash[32]);

bool gxfp_factory_load_pmk (GxfpFactoryMemRead mem_read,
                            GxfpFactoryHashRead hash_read,
                            void *user,
                            uint8_t pmk[GXFP_FACTORY_PMK_LEN]);
