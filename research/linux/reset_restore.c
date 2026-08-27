#define _POSIX_C_SOURCE 200809L

#include "gpiod_reset.h"
#include "../probe_harness.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <time.h>

#define GXFP_GPIO_CHIP "/dev/gpiochip0"
#define GXFP_RESET_OFFSET 264u

static enum gxfp_io_result restore_set_level(void *ctx, int level)
{
    return gxfp_gpiod_reset_set_level(ctx, level) == 0 ?
           GXFP_IO_OK : GXFP_IO_ERROR;
}

static enum gxfp_io_result restore_sleep_ms(void *ctx, unsigned ms)
{
    struct timespec req;
    struct timespec rem;
    (void)ctx;

    req.tv_sec = (time_t)(ms / 1000u);
    req.tv_nsec = (long)(ms % 1000u) * 1000000L;
    while (nanosleep(&req, &rem) < 0) {
        if (errno != EINTR)
            return GXFP_IO_ERROR;
        req = rem;
    }
    return GXFP_IO_OK;
}

int main(void)
{
    struct gxfp_gpiod_reset *reset = NULL;
    struct gxfp_probe_reset_ops ops;
    enum gxfp_io_result result;
    int after;

    /* Once invoked as a fail-safe, do not let terminal signals interrupt the
     * tiny restore sequence. SIGKILL/power loss remain outside userspace control. */
    if (signal(SIGINT, SIG_IGN) == SIG_ERR ||
        signal(SIGTERM, SIG_IGN) == SIG_ERR) {
        fprintf(stderr, "GPIO264_RESTORE_SIGNAL_GUARD=FAIL\n");
        return 1;
    }

    if (gxfp_gpiod_reset_open_as_is(&reset,
                                     GXFP_GPIO_CHIP,
                                     GXFP_RESET_OFFSET) != 0) {
        fprintf(stderr, "GPIO264_RESTORE_OPEN=FAIL\n");
        return 2;
    }

    ops = (struct gxfp_probe_reset_ops){
        .ctx = reset,
        .set_level = restore_set_level,
        .sleep_ms = restore_sleep_ms,
    };

    result = gxfp_probe_restore_reset(&ops);
    after = gxfp_gpiod_reset_get_level(reset);

    printf("GPIO264_RESTORE_RESULT=%d\n", result);
    printf("GPIO264_RESTORE_AFTER=%d\n", after);
    fflush(stdout);

    gxfp_gpiod_reset_close(reset);
    return (result == GXFP_IO_OK && after == 0) ? 0 : 3;
}
