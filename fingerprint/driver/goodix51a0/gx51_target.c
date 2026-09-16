#include "gx51_target.h"

#include <string.h>

const uint8_t GXFP_TARGET_BASE_CONFIG[GXFP_CONFIG_LEN] = {
    0x70,0x11,0x60,0x71,0x2c,0x9d,0x2c,0xc9,0x1c,0xe5,0x18,0xfd,0x00,0xfd,0x00,0xfd,
    0x03,0xba,0x00,0x01,0x80,0xca,0x00,0x04,0x00,0x84,0x00,0x15,0xb3,0x86,0x00,0x00,
    0xc4,0x88,0x00,0x00,0xba,0x8a,0x00,0x00,0xb2,0x8c,0x00,0x00,0xaa,0x8e,0x00,0x00,
    0xc1,0x90,0x00,0xbb,0xbb,0x92,0x00,0xb1,0xb1,0x94,0x00,0x00,0xa8,0x96,0x00,0x00,
    0xb6,0x98,0x00,0x00,0x00,0x9a,0x00,0x00,0x00,0xd2,0x00,0x00,0x00,0xd4,0x00,0x00,
    0x00,0xd6,0x00,0x00,0x00,0xd8,0x00,0x00,0x00,0x50,0x00,0x01,0x05,0xd0,0x00,0x00,
    0x00,0x70,0x00,0x00,0x00,0x72,0x00,0x78,0x56,0x74,0x00,0x34,0x12,0x20,0x00,0x10,
    0x40,0x2a,0x01,0x02,0x04,0x22,0x00,0x01,0x20,0x24,0x00,0x32,0x00,0x80,0x00,0x01,
    0x00,0x5c,0x00,0x80,0x00,0x56,0x00,0x24,0x20,0x58,0x00,0x03,0x02,0x32,0x00,0x0c,
    0x02,0x66,0x00,0x03,0x00,0x7c,0x00,0x00,0x58,0x82,0x00,0x80,0x15,0x2a,0x01,0x82,
    0x03,0x22,0x00,0x01,0x20,0x24,0x00,0x14,0x00,0x80,0x00,0x01,0x00,0x5c,0x00,0x00,
    0x01,0x56,0x00,0x04,0x20,0x58,0x00,0x03,0x02,0x32,0x00,0x0c,0x02,0x66,0x00,0x03,
    0x00,0x7c,0x00,0x00,0x58,0x82,0x00,0x80,0x21,0x2a,0x01,0x08,0x00,0x5c,0x00,0x80,
    0x00,0x54,0x00,0x10,0x01,0x62,0x00,0x04,0x03,0x64,0x00,0x19,0x00,0x66,0x00,0x03,
    0x00,0x7c,0x00,0x01,0x58,0x2a,0x01,0x08,0x00,0x5c,0x00,0xe0,0x00,0x52,0x00,0x08,
    0x00,0x54,0x00,0x00,0x01,0x66,0x00,0x03,0x00,0x7c,0x00,0x01,0x58,0x00,0x88,0x2e,
};

static void build_outer(size_t inner_len, uint8_t outer[4])
{
    outer[0] = 0xa0u;
    outer[1] = (uint8_t)(inner_len & 0xffu);
    outer[2] = (uint8_t)((inner_len >> 8) & 0xffu);
    outer[3] = (uint8_t)(outer[0] + outer[1] + outer[2]);
}

uint8_t gxfp_body_checksum(const uint8_t *buf, size_t len)
{
    uint8_t sum = 0u;
    size_t i;

    if (buf == NULL)
        return 0u;
    for (i = 0; i < len; i++)
        sum = (uint8_t)(sum + buf[i]);
    return (uint8_t)(0xaau - sum);
}

static bool build_fixed(const uint8_t *body, size_t body_len,
                        struct gxfp_target_packet *packet)
{
    if (body == NULL || packet == NULL || body_len > sizeof(packet->inner))
        return false;
    memset(packet, 0, sizeof(*packet));
    memcpy(packet->inner, body, body_len);
    packet->inner_len = body_len;
    build_outer(body_len, packet->outer);
    return true;
}

bool gxfp_build_soft_reset(struct gxfp_target_packet *packet)
{
    static const uint8_t body[] = {0xa2,0x03,0x00,0x01,0x14,0xf0};
    return build_fixed(body, sizeof(body), packet);
}

bool gxfp_build_chip_id(struct gxfp_target_packet *packet)
{
    static const uint8_t body[] = {0x82,0x06,0x00,0x00,0x00,0x00,0x04,0x00,0x1e};
    return build_fixed(body, sizeof(body), packet);
}

bool gxfp_build_read_otp(struct gxfp_target_packet *packet)
{
    static const uint8_t body[] = {0xa6,0x03,0x00,0x00,0x00,0x01};
    return build_fixed(body, sizeof(body), packet);
}

bool gxfp_build_idle(struct gxfp_target_packet *packet)
{
    static const uint8_t body[] = {0x70,0x03,0x00,0x14,0x00,0x23};
    return build_fixed(body, sizeof(body), packet);
}

bool gxfp_build_reg_write(uint16_t address, uint16_t value,
                          struct gxfp_target_packet *packet)
{
    uint8_t body[9] = {0x80,0x06,0x00,0x00,0,0,0,0,0};

    if (packet == NULL)
        return false;
    body[4] = (uint8_t)address;
    body[5] = (uint8_t)(address >> 8);
    body[6] = (uint8_t)value;
    body[7] = (uint8_t)(value >> 8);
    body[8] = gxfp_body_checksum(body, 8u);
    return build_fixed(body, sizeof(body), packet);
}

bool gxfp_build_factory_hash_read(struct gxfp_target_packet *packet)
{
    static const uint8_t body[] = {
        0xe4,0x09,0x00,0x03,0x00,0x02,0xbb,0x00,0x00,0x00,0x00,0xfd
    };
    return build_fixed(body, sizeof(body), packet);
}

bool gxfp_build_mem_read(uint32_t address, uint32_t len,
                         struct gxfp_target_packet *packet)
{
    uint32_t wire_address;
    uint8_t body[12];

    if (packet == NULL || address < 0x08000000u ||
        len == 0u || len > GXFP_MEM_READ_MAX)
        return false;

    wire_address = address - 0x08000000u;
    body[0] = 0xf2u;
    body[1] = 0x09u;
    body[2] = 0x00u;
    body[3] = (uint8_t)(wire_address);
    body[4] = (uint8_t)(wire_address >> 8);
    body[5] = (uint8_t)(wire_address >> 16);
    body[6] = (uint8_t)(wire_address >> 24);
    body[7] = (uint8_t)(len);
    body[8] = (uint8_t)(len >> 8);
    body[9] = (uint8_t)(len >> 16);
    body[10] = (uint8_t)(len >> 24);
    body[11] = gxfp_body_checksum(body, 11u);
    return build_fixed(body, sizeof(body), packet);
}

static uint16_t config_checksum(const uint8_t config[GXFP_CONFIG_LEN])
{
    uint32_t sum = 0xa5a5u;
    size_t i;

    for (i = 0; i < GXFP_CONFIG_LEN - 2u; i += 2u)
        sum += (uint32_t)config[i] | ((uint32_t)config[i + 1u] << 8);
    return (uint16_t)(0u - sum);
}

bool gxfp_config_checksum_valid(const uint8_t config[GXFP_CONFIG_LEN])
{
    uint16_t stored;

    if (config == NULL)
        return false;
    stored = (uint16_t)config[GXFP_CONFIG_LEN - 2u] |
             ((uint16_t)config[GXFP_CONFIG_LEN - 1u] << 8);
    return stored == config_checksum(config);
}

void gxfp_config_fix_checksum(uint8_t config[GXFP_CONFIG_LEN])
{
    uint16_t checksum;

    if (config == NULL)
        return;
    checksum = config_checksum(config);
    config[GXFP_CONFIG_LEN - 2u] = (uint8_t)checksum;
    config[GXFP_CONFIG_LEN - 1u] = (uint8_t)(checksum >> 8);
}

bool gxfp_build_upload_config(const uint8_t config[GXFP_CONFIG_LEN],
                              struct gxfp_target_packet *packet)
{
    size_t body_len = GXFP_CONFIG_LEN + 4u;

    if (config == NULL || packet == NULL || !gxfp_config_checksum_valid(config))
        return false;

    memset(packet, 0, sizeof(*packet));
    packet->inner[0] = 0x90u;
    packet->inner[1] = 0x01u;
    packet->inner[2] = 0x01u;
    memcpy(packet->inner + 3u, config, GXFP_CONFIG_LEN);
    packet->inner[body_len - 1u] =
        gxfp_body_checksum(packet->inner, body_len - 1u);
    packet->inner_len = body_len;
    build_outer(body_len, packet->outer);
    return true;
}


static bool body_matches(const uint8_t *body, size_t len,
                         uint8_t command, size_t payload_len)
{
    uint16_t inner_len;

    if (body == NULL || len != payload_len + 4u || body[0] != command)
        return false;
    inner_len = (uint16_t)body[1] | ((uint16_t)body[2] << 8);
    if (inner_len != payload_len + 1u)
        return false;
    return body[len - 1u] == gxfp_body_checksum(body, len - 1u);
}

bool gxfp_parse_ack(const uint8_t *body, size_t len, uint8_t expected_command,
                    uint8_t *status)
{
    if (status == NULL || !body_matches(body, len, 0xb0u, 2u) ||
        body[3] != expected_command)
        return false;
    *status = body[4];
    return true;
}

bool gxfp_ack_status_success(uint8_t status)
{
    /* Bit 0 means the command was accepted. Bit 1 is the pre-TLS gate flag,
     * so both 0x01 and 0x03 are successful ACK states. */
    return (status & 0x01u) != 0u;
}

bool gxfp_parse_soft_reset_response(const uint8_t *body, size_t len,
                                    uint32_t *reset_code)
{
    if (reset_code == NULL || !body_matches(body, len, 0xa2u, 3u))
        return false;
    *reset_code = ((uint32_t)body[3] << 16) |
                  ((uint32_t)body[4] << 8) | body[5];
    return true;
}

bool gxfp_parse_chip_id_response(const uint8_t *body, size_t len,
                                 uint16_t *chip_id)
{
    if (chip_id == NULL || !body_matches(body, len, 0x82u, 4u))
        return false;
    *chip_id = (uint16_t)body[4] | ((uint16_t)body[5] << 8);
    return true;
}

bool gxfp_parse_otp_response(const uint8_t *body, size_t len, uint8_t out[64])
{
    if (out == NULL || !body_matches(body, len, 0xa6u, 64u))
        return false;
    memcpy(out, body + 3u, 64u);
    return true;
}

bool gxfp_parse_config_response(const uint8_t *body, size_t len, uint8_t *status)
{
    if (status == NULL || !body_matches(body, len, 0x90u, 2u))
        return false;
    *status = body[3];
    return true;
}

bool gxfp_parse_factory_hash_response(const uint8_t *body, size_t len,
                                      uint32_t *dtype, uint8_t hash[32])
{
    uint32_t dlen;

    if (dtype == NULL || hash == NULL ||
        !body_matches(body, len, 0xe4u, 41u) || body[3] != 0u)
        return false;
    *dtype = (uint32_t)body[4] | ((uint32_t)body[5] << 8) |
             ((uint32_t)body[6] << 16) | ((uint32_t)body[7] << 24);
    dlen = (uint32_t)body[8] | ((uint32_t)body[9] << 8) |
           ((uint32_t)body[10] << 16) | ((uint32_t)body[11] << 24);
    if (dlen != 32u)
        return false;
    memcpy(hash, body + 12u, 32u);
    return true;
}

enum gxfp_mem_read_result
gxfp_classify_mem_read_response(const uint8_t *body, size_t len,
                                uint32_t address, uint32_t requested_len,
                                uint8_t *out)
{
    uint32_t wire_address;
    uint8_t echo[8];
    size_t data_offset;

    if (out == NULL || body == NULL || address < 0x08000000u ||
        requested_len == 0u || requested_len > GXFP_MEM_READ_MAX)
        return GXFP_MEM_READ_INVALID;

    wire_address = address - 0x08000000u;
    echo[0] = (uint8_t)wire_address;
    echo[1] = (uint8_t)(wire_address >> 8);
    echo[2] = (uint8_t)(wire_address >> 16);
    echo[3] = (uint8_t)(wire_address >> 24);
    echo[4] = (uint8_t)requested_len;
    echo[5] = (uint8_t)(requested_len >> 8);
    echo[6] = (uint8_t)(requested_len >> 16);
    echo[7] = (uint8_t)(requested_len >> 24);

    /* Some 14115 reads emit the exact addr32||len32 echo as its own F2
     * packet before the real data.  This must be checked before the direct
     * form: for an 8-byte request both frames are 12 bytes long. */
    if (len == 12u && body_matches(body, len, 0xf2u, 8u) &&
        memcmp(body + 3u, echo, sizeof echo) == 0)
        return GXFP_MEM_READ_ECHO_ONLY;

    if (len == (size_t) requested_len + 4u) {
        if (!body_matches(body, len, 0xf2u, requested_len))
            return GXFP_MEM_READ_INVALID;
        data_offset = 3u;
    } else if (len == (size_t) requested_len + 12u) {
        if (!body_matches(body, len, 0xf2u, (size_t) requested_len + 8u) ||
            memcmp(body + 3u, echo, sizeof echo) != 0)
            return GXFP_MEM_READ_INVALID;
        data_offset = 11u;
    } else {
        return GXFP_MEM_READ_INVALID;
    }

    memcpy(out, body + data_offset, requested_len);
    return GXFP_MEM_READ_DATA;
}

bool gxfp_parse_mem_read_response(const uint8_t *body, size_t len,
                                  uint32_t address, uint32_t requested_len,
                                  uint8_t *out)
{
    return gxfp_classify_mem_read_response(body, len, address,
                                           requested_len, out) ==
           GXFP_MEM_READ_DATA;
}

static uint8_t crc8_goodix(const uint8_t *data, size_t len)
{
    uint8_t crc = 0u;
    size_t i;
    unsigned bit;

    for (i = 0; i < len; i++) {
        crc ^= data[i];
        for (bit = 0; bit < 8u; bit++)
            crc = (uint8_t)((crc & 0x80u) ? (((unsigned)crc << 1) ^ 0x07u) : ((unsigned)crc << 1));
    }
    return crc;
}

static uint8_t otp_crc_join(const uint8_t otp[64], const uint8_t *indices, size_t n)
{
    uint8_t tmp[32];
    size_t i;

    if (n > sizeof tmp)
        return 0u;
    for (i = 0; i < n; i++)
        tmp[i] = otp[indices[i]];
    return (uint8_t)~crc8_goodix(tmp, n);
}

bool gxfp_derive_calibration(const uint8_t otp[64],
                             struct gxfp_target_calibration *cal)
{
    static const uint8_t cp_idx[] = {
        0,1,2,3,4,5,6,7,8,9,10,36,37,38,39
    };
    static const uint8_t mt_idx[] = {
        20,21,22,23,24,25,26,27,29,30,31,32,33,34,35,
        40,41,42,43,44,45,46,47,48,49,54,55
    };
    static const uint8_t ft_idx[] = {
        11,12,13,14,15,16,17,18,19,28,50,51,52,53,56,57,58,59,62
    };
    uint16_t tcode;
    unsigned raw_delta;
    uint8_t a, b, c;

    if (otp == NULL || cal == NULL)
        return false;
    if (otp_crc_join(otp, cp_idx, sizeof cp_idx) != otp[60] ||
        otp_crc_join(otp, mt_idx, sizeof mt_idx) != otp[63] ||
        otp_crc_join(otp, ft_idx, sizeof ft_idx) != otp[61] ||
        (uint8_t)~crc8_goodix(otp + 50, 4u) != otp[62] ||
        (uint8_t)~crc8_goodix(otp + 46, 4u) != otp[22] ||
        memcmp(otp + 46, otp + 50, 4u) != 0)
        return false;
    if (otp[42] == 0u || otp[42] != (uint8_t)~otp[43])
        return false;

    tcode = (uint16_t)(((otp[42] >> 4) + 1u) * 16u + 64u);
    raw_delta = (unsigned)(((otp[42] & 0x0fu) + 2u) * 25600u / tcode / 3u);

    a = otp[27] & 3u;
    b = (otp[27] >> 2) & 3u;
    c = (otp[27] >> 4) & 3u;
    cal->fdt_offset = (a == c || a == b) ? a : (c == b ? c : 0u);
    cal->tcode = tcode;
    cal->fdt_delta = (uint8_t)((raw_delta >> 4) & 0xffu);
    cal->dac_main = (uint16_t)(((uint16_t)otp[46] << 4) | 8u);
    cal->dac1 = otp[47];
    cal->dac2 = otp[48];
    cal->dac3 = otp[49];
    return true;
}


static bool config_replace_section_value(uint8_t config[GXFP_CONFIG_LEN],
                                         unsigned section, uint16_t tag,
                                         uint16_t value)
{
    size_t table = 1u + section * 2u;
    size_t base, size, off;

    if (section >= 8u || table + 1u >= GXFP_CONFIG_LEN)
        return false;
    base = config[table];
    size = config[table + 1u];
    if ((size % 4u) != 0u || base + size > GXFP_CONFIG_LEN - 2u)
        return false;
    for (off = base; off + 3u < base + size; off += 4u) {
        uint16_t found = (uint16_t)config[off] | ((uint16_t)config[off + 1u] << 8);
        if (found == tag) {
            config[off + 2u] = (uint8_t)value;
            config[off + 3u] = (uint8_t)(value >> 8);
            return true;
        }
    }
    return false;
}

bool gxfp_patch_config(uint8_t config[GXFP_CONFIG_LEN],
                       const struct gxfp_target_calibration *cal)
{
    if (config == NULL || cal == NULL || !gxfp_config_checksum_valid(config))
        return false;
    if (!config_replace_section_value(config, 2u, 0x005cu, cal->tcode) ||
        !config_replace_section_value(config, 3u, 0x005cu, cal->tcode) ||
        !config_replace_section_value(config, 4u, 0x005cu, cal->tcode) ||
        !config_replace_section_value(config, 2u, 0x0082u,
                                      (uint16_t)(((uint16_t)cal->fdt_delta << 8) | 0x80u)))
        return false;
    gxfp_config_fix_checksum(config);
    return gxfp_config_checksum_valid(config);
}
