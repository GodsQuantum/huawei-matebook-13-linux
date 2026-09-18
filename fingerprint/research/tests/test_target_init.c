#include "../../driver/goodix51a0/gx51_target.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void expect_bytes(const uint8_t *got, const uint8_t *want, size_t n)
{
    assert(memcmp(got, want, n) == 0);
}

int main(void)
{
    struct gxfp_target_packet p;
    uint8_t cfg[GXFP_CONFIG_LEN] = {0};
    assert(sizeof GXFP_TARGET_BASE_CONFIG == GXFP_CONFIG_LEN);
    assert(GXFP_TARGET_BASE_CONFIG[0] == 0x70u);
    assert(GXFP_TARGET_BASE_CONFIG[GXFP_CONFIG_LEN - 1] == 0x2eu);
    assert(gxfp_config_checksum_valid(GXFP_TARGET_BASE_CONFIG));
    static const uint8_t soft_reset[] = {0xa2,0x03,0x00,0x01,0x14,0xf0};
    static const uint8_t chip_id[] = {0x82,0x06,0x00,0x00,0x00,0x00,0x04,0x00,0x1e};
    static const uint8_t otp[] = {0xa6,0x03,0x00,0x00,0x00,0x01};
    static const uint8_t idle[] = {0x70,0x03,0x00,0x14,0x00,0x23};
    static const uint8_t reg_main[] = {0x80,0x06,0x00,0x00,0x20,0x02,0x68,0x0b,0x8f};
    static const uint8_t mem_20000000_256[] = {
        0xf2,0x09,0x00,0x00,0x00,0x00,0x18,0x00,0x01,0x00,0x00,0x96
    };

    assert(gxfp_build_soft_reset(&p));
    assert(p.inner_len == sizeof soft_reset);
    expect_bytes(p.inner, soft_reset, sizeof soft_reset);

    assert(gxfp_build_chip_id(&p));
    assert(p.inner_len == sizeof chip_id);
    expect_bytes(p.inner, chip_id, sizeof chip_id);

    assert(gxfp_build_read_otp(&p));
    assert(p.inner_len == sizeof otp);
    expect_bytes(p.inner, otp, sizeof otp);

    assert(gxfp_build_idle(&p));
    assert(p.inner_len == sizeof idle);
    expect_bytes(p.inner, idle, sizeof idle);

    assert(gxfp_build_reg_write(0x0220u, 0x0b68u, &p));
    assert(p.inner_len == sizeof reg_main);
    expect_bytes(p.inner, reg_main, sizeof reg_main);

    assert(gxfp_build_mem_read(0x20000000u, 256u, &p));
    assert(p.inner_len == sizeof mem_20000000_256);
    expect_bytes(p.inner, mem_20000000_256, sizeof mem_20000000_256);
    assert(!gxfp_build_mem_read(0x07ffffffu, 48u, &p));
    assert(!gxfp_build_mem_read(0x20000000u, 0u, &p));
    assert(!gxfp_build_mem_read(0x20000000u, GXFP_MEM_READ_MAX + 1u, &p));

    {
        static const uint8_t want_e4[] = {
            0xe4,0x09,0x00,0x03,0x00,0x02,0xbb,0x00,0x00,0x00,0x00,0xfd
        };
        uint8_t rsp[45] = {0xe4,0x2a,0x00,0x00,0xaa,0xaa,0x00,0x00,0x20,0x00,0x00,0x00};
        uint8_t hash[32] = {0};
        uint32_t dtype = 0;
        assert(gxfp_build_factory_hash_read(&p));
        assert(p.inner_len == sizeof want_e4);
        expect_bytes(p.inner, want_e4, sizeof want_e4);
        for (size_t i=0;i<32;i++) rsp[12+i]=(uint8_t)(i+1);
        rsp[44]=gxfp_body_checksum(rsp,44);
        assert(gxfp_parse_factory_hash_response(rsp,sizeof rsp,&dtype,hash));
        assert(dtype==0x0000aaaau);
        assert(memcmp(hash,rsp+12,32)==0);
        rsp[3]=1u; rsp[44]=gxfp_body_checksum(rsp,44);
        assert(!gxfp_parse_factory_hash_response(rsp,sizeof rsp,&dtype,hash));
    }

    {
        static const uint8_t direct_rsp[] = {
            0xf2,0x11,0x00,
            0x00,0x00,0x02,0x20,0x99,0x31,0x03,0x08,
            0xe9,0x31,0x03,0x08,0x35,0x5a,0x02,0x08,0xf2
        };
        static const uint8_t want[] = {
            0x00,0x00,0x02,0x20,0x99,0x31,0x03,0x08,
            0xe9,0x31,0x03,0x08,0x35,0x5a,0x02,0x08
        };
        uint8_t out[16] = {0};
        assert(gxfp_parse_mem_read_response(direct_rsp, sizeof direct_rsp,
                                            0x08020000u, 16u, out));
        assert(memcmp(out, want, sizeof want) == 0);
    }

    {
        uint8_t echo_only[12] = {
            0xf2,0x09,0x00,
            0x00,0x40,0x00,0x00, 0x08,0x00,0x00,0x00,
            0x00
        };
        uint8_t out[8] = {0};
        echo_only[11] = gxfp_body_checksum(echo_only, 11);
        assert(gxfp_classify_mem_read_response(echo_only, sizeof echo_only,
                                               0x08004000u, 8u, out) ==
               GXFP_MEM_READ_ECHO_ONLY);
        assert(!gxfp_parse_mem_read_response(echo_only, sizeof echo_only,
                                             0x08004000u, 8u, out));
    }

    {
        uint8_t rsp[16] = {
            0xf2,0x0d,0x00,
            0x08,0x80,0x00,0x00, 0x04,0x00,0x00,0x00,
            0xaa,0xbb,0xcc,0xdd,0x00
        };
        uint8_t out[4] = {0};
        rsp[15] = gxfp_body_checksum(rsp, 15);
        assert(gxfp_parse_mem_read_response(rsp, sizeof rsp, 0x08008008u, 4u, out));
        assert(memcmp(out, rsp + 11, sizeof out) == 0);
        rsp[3] ^= 1u;
        rsp[15] = gxfp_body_checksum(rsp, 15);
        assert(!gxfp_parse_mem_read_response(rsp, sizeof rsp, 0x08008008u, 4u, out));
        rsp[3] ^= 1u;
        rsp[15] = gxfp_body_checksum(rsp, 15);
        rsp[15] ^= 1u;
        assert(!gxfp_parse_mem_read_response(rsp, sizeof rsp, 0x08008008u, 4u, out));
    }

    /* Internal 16-bit config checksum seed is 0xa5a5. */
    for (size_t i = 0; i < GXFP_CONFIG_LEN - 2; i++)
        cfg[i] = (uint8_t)i;
    gxfp_config_fix_checksum(cfg);
    assert(gxfp_config_checksum_valid(cfg));
    assert(gxfp_build_upload_config(cfg, &p));
    assert(p.inner_len == GXFP_CONFIG_LEN + 4u);
    assert(p.inner[0] == 0x90 && p.inner[1] == 0x01 && p.inner[2] == 0x01);
    assert(p.inner[p.inner_len - 1] == gxfp_body_checksum(p.inner, p.inner_len - 1));

    {
        uint8_t status = 0;
        uint16_t chip = 0;
        uint32_t reset_code = 0;
        uint8_t otp_out[64] = {0};
        uint8_t otp_rsp[68] = {0xa6,0x41,0x00};
        const uint8_t ack_a2[] = {0xb0,0x03,0x00,0xa2,0x01,0x54};
        const uint8_t reset_rsp[] = {0xa2,0x04,0x00,0x01,0x00,0x08,0xfb};
        const uint8_t chip_rsp[] = {0x82,0x05,0x00,0xa2,0x04,0x25,0x00,0x58};
        const uint8_t cfg_rsp[] = {0x90,0x03,0x00,0x01,0x00,0x16};

        for (size_t i = 0; i < 64; i++)
            otp_rsp[3 + i] = (uint8_t)(0x40u + i);
        otp_rsp[67] = gxfp_body_checksum(otp_rsp, 67);

        assert(gxfp_parse_ack(ack_a2, sizeof ack_a2, 0xa2, &status));
        assert(status == 1);
        assert(gxfp_parse_soft_reset_response(reset_rsp, sizeof reset_rsp, &reset_code));
        assert(reset_code == 0x010008u);
        assert(gxfp_parse_chip_id_response(chip_rsp, sizeof chip_rsp, &chip));
        assert(chip == 0x2504u);
        assert(gxfp_parse_otp_response(otp_rsp, sizeof otp_rsp, otp_out));
        assert(memcmp(otp_out, otp_rsp + 3, 64) == 0);
        assert(gxfp_parse_config_response(cfg_rsp, sizeof cfg_rsp, &status));
        assert(status == 1);
        assert(!gxfp_parse_ack(ack_a2, sizeof ack_a2, 0xa8, &status));
        assert(gxfp_ack_status_success(0x01u));
        assert(gxfp_ack_status_success(0x03u));
        assert(!gxfp_ack_status_success(0x00u));
        assert(!gxfp_ack_status_success(0x02u));
    }

    {
        static const uint8_t public_otp[64] = {
          0x53,0x32,0x42,0x39,0x37,0x33,0x2e,0x00,0x0a,0x77,0x7a,0xa3,0x45,0x2c,0xec,0x02,
          0x51,0x07,0x05,0x02,0x7d,0x4b,0xd5,0x27,0x41,0x03,0xd1,0x0c,0xf1,0x8f,0x70,0x0c,
          0x38,0xc1,0x30,0x33,0xa5,0x8f,0x5f,0xf4,0x07,0xf4,0x8e,0x71,0x01,0x8e,0xb6,0xb7,
          0xb6,0xb6,0xb6,0xb7,0xb6,0xb6,0x34,0x50,0xa5,0x5a,0x5f,0xa0,0xc8,0x14,0xd5,0x48
        };
        struct gxfp_target_calibration cal;
        assert(gxfp_derive_calibration(public_otp, &cal));
        assert(cal.tcode == 208u);
        assert(cal.fdt_delta == 41u);
        assert(cal.fdt_offset == 0u);
        assert(cal.dac_main == 0x0b68u);
        assert(cal.dac1 == 0xb7u && cal.dac2 == 0xb6u && cal.dac3 == 0xb6u);

        uint8_t bad_otp[64];
        memcpy(bad_otp, public_otp, sizeof bad_otp);
        bad_otp[50] ^= 1u;
        assert(!gxfp_derive_calibration(bad_otp, &cal));

        static const uint8_t public_otp_tcode256[64] = {
          0x53,0x32,0x38,0x37,0x33,0x34,0x2e,0x00,0x32,0x77,0x8a,0xa2,0xd4,0x95,0xca,0x05,
          0x51,0x07,0x05,0x0a,0x7d,0x0b,0xfd,0x27,0x41,0x03,0x11,0x0c,0xf1,0x7f,0x80,0x0c,
          0x38,0x81,0x30,0x34,0xa5,0x7f,0x5e,0xf4,0x06,0xc4,0xbd,0x42,0x01,0xbd,0xb7,0xb9,
          0xb7,0xb7,0xb7,0xb9,0xb7,0xb7,0x32,0x30,0xa5,0x5a,0x5e,0xa1,0x85,0x0c,0xfd,0x71
        };
        assert(gxfp_derive_calibration(public_otp_tcode256, &cal));
        assert(cal.tcode == 256u);
        assert(cal.fdt_delta == 31u);
        assert(cal.dac_main == 0x0b78u);
    }

    {
        struct gxfp_target_calibration cal = {
            .tcode = 224u, .fdt_delta = 33u, .fdt_offset = 0u,
            .dac_main = 0x0b98u, .dac1 = 0xbcu, .dac2 = 0xb9u, .dac3 = 0xb9u
        };
        uint8_t c[GXFP_CONFIG_LEN] = {0};
        c[1]=0x20; c[2]=0x00; c[3]=0x20; c[4]=0x00;
        c[5]=0x40; c[6]=0x08; c[7]=0x48; c[8]=0x04; c[9]=0x4c; c[10]=0x04;
        c[0x40]=0x5c; c[0x41]=0x00; c[0x42]=0x00; c[0x43]=0x01;
        c[0x44]=0x82; c[0x45]=0x00; c[0x46]=0x80; c[0x47]=0x15;
        c[0x48]=0x5c; c[0x49]=0x00; c[0x4a]=0x00; c[0x4b]=0x01;
        c[0x4c]=0x5c; c[0x4d]=0x00; c[0x4e]=0x00; c[0x4f]=0x01;
        gxfp_config_fix_checksum(c);
        assert(gxfp_patch_config(c, &cal));
        assert(c[0x42]==0xe0 && c[0x43]==0x00);
        assert(c[0x46]==0x80 && c[0x47]==0x21);
        assert(c[0x4a]==0xe0 && c[0x4b]==0x00);
        assert(c[0x4e]==0xe0 && c[0x4f]==0x00);
        assert(gxfp_config_checksum_valid(c));
    }

    {
        uint8_t rsp[96] = {0};
        uint8_t stale[80] = {0};
        size_t stale_len = 0;
        uint32_t wire = 0x00004000u;
        rsp[0] = 0xf2u;
        rsp[1] = 0x59u; /* 8-byte echo + 80 stale bytes + command byte */
        rsp[2] = 0x00u;
        rsp[3] = (uint8_t)wire;
        rsp[4] = (uint8_t)(wire >> 8);
        rsp[5] = (uint8_t)(wire >> 16);
        rsp[6] = (uint8_t)(wire >> 24);
        rsp[7] = 0x00u; rsp[8] = 0x01u; rsp[9] = 0x00u; rsp[10] = 0x00u;
        for (size_t i = 0; i < sizeof stale; i++)
            rsp[11 + i] = (uint8_t)(0x80u + i);
        rsp[91] = gxfp_body_checksum(rsp, 91);
        assert(gxfp_14115_parse_rejected_staging_response(
            rsp, 92u, 0x08004000u, 256u, stale, sizeof stale, &stale_len));
        assert(stale_len == sizeof stale);
        for (size_t i = 0; i < sizeof stale; i++)
            assert(stale[i] == (uint8_t)(0x80u + i));

        /* App flash is an accepted F2 range, so it must never be accepted as
         * a stale/rejected provider even if the packet shape is identical. */
        assert(!gxfp_14115_parse_rejected_staging_response(
            rsp, 92u, 0x08020000u, 256u, stale, sizeof stale, &stale_len));

        /* Echo-only responses carry no staging bytes. */
        rsp[1] = 0x09u;
        rsp[11] = gxfp_body_checksum(rsp, 11);
        assert(!gxfp_14115_parse_rejected_staging_response(
            rsp, 12u, 0x08004000u, 256u, stale, sizeof stale, &stale_len));
    }

    puts("test_target_init: OK");
    return 0;
}
