#include "../../driver/goodix51a0/gx51_capture_recipe.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void expect_commands(const struct gxfp_capture_recipe *r,
                            const uint8_t *cmds, size_t n)
{
    assert(r->count == n);
    for (size_t i = 0; i < n; i++)
        assert(r->steps[i].inner[0] == cmds[i]);
}

int main(void)
{
    const struct gxfp_target_calibration cal = {
        .tcode = 208u, .fdt_delta = 41u, .fdt_offset = 0u,
        .dac_main = 0x0b68u, .dac1 = 0xb7u, .dac2 = 0xb6u, .dac3 = 0xb6u
    };
    struct gxfp_capture_recipe r;
    static const uint8_t bg[] = {
        0x00,0xae,0x36,0x50,0x36,0x82,0x80,0x80,0x80,0x80,0x20
    };
    static const uint8_t finger[] = {0x36,0x32,0x00,0xae,0x32,0x20};
    static const uint8_t cleanup[] = {0x34,0x20,0x50,0x32};

    assert(gxfp_build_background_capture_recipe(&cal, &r));
    expect_commands(&r, bg, sizeof bg);
    assert(r.steps[2].inner_len == 18u);
    assert(r.steps[2].inner[1] == 0x0fu);
    assert(r.steps[2].inner[3] == 0x0du);
    assert(r.steps[6].inner[4] == 0x20u && r.steps[6].inner[5] == 0x02u);
    assert(r.steps[6].inner[6] == 0x68u && r.steps[6].inner[7] == 0x0bu);

    assert(gxfp_build_finger_capture_recipe(&r));
    expect_commands(&r, finger, sizeof finger);
    assert(r.steps[0].inner[3] == 0x0du);
    assert(r.steps[1].inner[3] == 0x0cu);
    assert(r.steps[4].inner[3] == 0x0cu);

    {
        struct gxfp_target_packet probe;
        static const uint8_t probe_zones[12] = {
            0x80,0xb1,0x80,0xc1,0x80,0xa6,0x80,0xb6,0x80,0xa5,0x80,0xb6
        };
        assert(gxfp_build_fdt_probe(&probe));
        assert(probe.inner_len == 18u);
        assert(probe.inner[0] == 0x36u && probe.inner[3] == 0x0du);
        assert(memcmp(probe.inner + 5u, probe_zones, sizeof probe_zones) == 0);
    }

    assert(gxfp_build_capture_cleanup_recipe(&r));
    expect_commands(&r, cleanup, sizeof cleanup);
    assert(r.steps[0].inner[3] == 0x0eu);
    assert(r.steps[3].inner[3] == 0x0cu);

    puts("test_capture_recipe: OK");
    return 0;
}
