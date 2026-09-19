/* SPDX-License-Identifier: LGPL-2.1-or-later */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GXFP_FACTORY_PMK_LEN 48u
#define GXFP_FACTORY_SALT_LEN 16u
#define GXFP_FACTORY_BODY_LEN 256u
#define GXFP_FACTORY_READ_LEN 80u
#define GXFP_FACTORY_STAGING_LEN (GXFP_FACTORY_BODY_LEN - 8u)

enum gxfp_factory_staging_diag {
  GXFP_FACTORY_STAGING_OK = 0,
  GXFP_FACTORY_STAGING_READ_FIRST_FAILED,
  GXFP_FACTORY_STAGING_READ_SECOND_FAILED,
  GXFP_FACTORY_STAGING_FIRST_LENGTH_INVALID,
  GXFP_FACTORY_STAGING_SECOND_LENGTH_INVALID,
  GXFP_FACTORY_STAGING_PAIR_LENGTH_MISMATCH,
  GXFP_FACTORY_STAGING_PAIR_BODY_MISMATCH,
  GXFP_FACTORY_STAGING_FIRST_RECOVER_FAILED,
  GXFP_FACTORY_STAGING_SECOND_RECOVER_FAILED,
  GXFP_FACTORY_STAGING_RECOVERED_BYTE_MISMATCH,
  GXFP_FACTORY_STAGING_PMK_MISMATCH,
};

const char *gxfp_factory_staging_diag_name (
  enum gxfp_factory_staging_diag diag);

bool gxfp_factory_pmk_decrypt (const uint8_t *body,
                               size_t body_len,
                               uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

bool gxfp_factory_pmk_recover_first_byte (
  const uint8_t *damaged_body,
  size_t body_len,
  uint8_t *recovered_first_byte,
  uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

bool gxfp_factory_pmk_from_staging_pair (
  const uint8_t *first,
  size_t first_len,
  const uint8_t *second,
  size_t second_len,
  uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

typedef bool (*GxfpFactoryStagingRead) (
  void *user, uint32_t selector, uint32_t request_len,
  uint8_t *out, size_t out_cap, size_t *out_len);

bool gxfp_factory_load_pmk_from_single_staging (
  GxfpFactoryStagingRead staging_read,
  void *user,
  uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

bool gxfp_factory_load_pmk_from_staging (
  GxfpFactoryStagingRead staging_read,
  void *user,
  uint8_t pmk[GXFP_FACTORY_PMK_LEN]);

bool gxfp_factory_load_pmk_from_staging_diag (
  GxfpFactoryStagingRead staging_read,
  void *user,
  uint8_t pmk[GXFP_FACTORY_PMK_LEN],
  enum gxfp_factory_staging_diag *diag);

typedef bool (*GxfpFactoryMemRead) (void *user, uint32_t address,
                                    uint32_t len, uint8_t *out);

bool gxfp_factory_load_pmk (GxfpFactoryMemRead mem_read,
                            void *user,
                            uint8_t pmk[GXFP_FACTORY_PMK_LEN]);
