#ifndef GX51_TARGET_H
#define GX51_TARGET_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define GXFP_CONFIG_LEN 256u
#define GXFP_TARGET_INNER_MAX (GXFP_CONFIG_LEN + 4u)
#define GXFP_MEM_READ_MAX 256u

extern const uint8_t GXFP_TARGET_BASE_CONFIG[GXFP_CONFIG_LEN];

struct gxfp_target_packet {
    uint8_t outer[4];
    uint8_t inner[GXFP_TARGET_INNER_MAX];
    size_t inner_len;
};

struct gxfp_target_calibration {
    uint16_t tcode;
    uint8_t fdt_delta;
    uint8_t fdt_offset;
    uint16_t dac_main;
    uint8_t dac1, dac2, dac3;
};

uint8_t gxfp_body_checksum(const uint8_t *buf, size_t len);
bool gxfp_build_soft_reset(struct gxfp_target_packet *packet);
bool gxfp_build_chip_id(struct gxfp_target_packet *packet);
bool gxfp_build_read_otp(struct gxfp_target_packet *packet);
bool gxfp_build_idle(struct gxfp_target_packet *packet);
bool gxfp_build_reg_write(uint16_t address, uint16_t value,
                          struct gxfp_target_packet *packet);
bool gxfp_build_mem_read(uint32_t address, uint32_t len,
                         struct gxfp_target_packet *packet);
bool gxfp_build_factory_hash_read(struct gxfp_target_packet *packet);

bool gxfp_config_checksum_valid(const uint8_t config[GXFP_CONFIG_LEN]);
void gxfp_config_fix_checksum(uint8_t config[GXFP_CONFIG_LEN]);
bool gxfp_build_upload_config(const uint8_t config[GXFP_CONFIG_LEN],
                              struct gxfp_target_packet *packet);
bool gxfp_derive_calibration(const uint8_t otp[64],
                             struct gxfp_target_calibration *cal);
bool gxfp_patch_config(uint8_t config[GXFP_CONFIG_LEN],
                       const struct gxfp_target_calibration *cal);

bool gxfp_parse_ack(const uint8_t *body, size_t len, uint8_t expected_command,
                    uint8_t *status);
bool gxfp_ack_status_success(uint8_t status);
bool gxfp_parse_soft_reset_response(const uint8_t *body, size_t len,
                                    uint32_t *reset_code);
bool gxfp_parse_chip_id_response(const uint8_t *body, size_t len,
                                 uint16_t *chip_id);
bool gxfp_parse_otp_response(const uint8_t *body, size_t len, uint8_t out[64]);
bool gxfp_parse_config_response(const uint8_t *body, size_t len, uint8_t *status);
bool gxfp_parse_mem_read_response(const uint8_t *body, size_t len,
                                  uint32_t address, uint32_t requested_len,
                                  uint8_t *out);
bool gxfp_parse_factory_hash_response(const uint8_t *body, size_t len,
                                      uint32_t *dtype, uint8_t hash[32]);

#endif
