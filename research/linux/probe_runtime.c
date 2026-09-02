#define _POSIX_C_SOURCE 200809L

#include "active_backend.h"
#include "kernel_irq_runtime.h"
#include "gpiod_reset.h"
#include "linux_spi.h"
#include "spidev_discovery.h"
#include "../probe_harness.h"

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define GXFP_SPI_SYSFS "/sys/bus/spi/devices/spi-GXFP51A0:00"
#define GXFP_DEV_ROOT "/dev"
#define GXFP_GPIO_CHIP "/dev/gpiochip0"
#define GXFP_IRQ_WAIT_DEV "/dev/gxfp_irq_wait"
#define GXFP_EXPECTED_HWIRQ 48u
#define GXFP_EXPECTED_TRIGGER 4u
#define GXFP_RESET_OFFSET 264u

static volatile sig_atomic_t g_cancelled;

struct preamble_ctx {
    struct gxfp_linux_active_backend *active;
    struct gxfp_attempt_backend *attempt;
};

static void on_signal(int signo)
{
    (void)signo;
    g_cancelled = 1;
}

static int cancelled_cb(void *ctx)
{
    (void)ctx;
    return g_cancelled != 0;
}

static enum gxfp_io_result reset_set_level(void *ctx, int level)
{
    struct gxfp_gpiod_reset *reset = ctx;
    int rc = gxfp_gpiod_reset_set_level(reset, level);

    printf("RESET_SET level=%d rc=%d\n", level, rc);
    fflush(stdout);
    return rc == 0 ? GXFP_IO_OK : GXFP_IO_ERROR;
}

/* Reset cleanup must not be cancelled halfway through.  EINTR is retried
 * until the full timing window has elapsed. */
static enum gxfp_io_result reset_sleep_ms(void *ctx, unsigned ms)
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

static enum gxfp_io_result preamble_send_nop(void *ctx)
{
    struct preamble_ctx *pre = ctx;
    return pre->attempt->send_nop(pre->attempt->ctx);
}

static enum gxfp_io_result preamble_send_install(void *ctx)
{
    struct preamble_ctx *pre = ctx;
    return gxfp_linux_active_backend_send_driver_install(pre->active);
}

static enum gxfp_io_result preamble_sleep(void *ctx, unsigned ms)
{
    struct preamble_ctx *pre = ctx;
    return pre->attempt->sleep_ms(pre->attempt->ctx, ms);
}

static enum gxfp_io_result preamble_wait_ack(void *ctx,
                                               uint8_t cmd0,
                                               uint8_t cmd1,
                                               unsigned timeout_ms)
{
    struct preamble_ctx *pre = ctx;
    return pre->attempt->wait_ack(pre->attempt->ctx, cmd0, cmd1, timeout_ms);
}

static void transfer_trace(void *ctx,
                           enum gxfp_linux_transfer_direction direction,
                           size_t len,
                           int rc)
{
    unsigned *seq = ctx;

    (*seq)++;
    printf("SPI_XFER seq=%u dir=%s len=%zu rc=%d\n",
           *seq,
           direction == GXFP_LINUX_TRANSFER_WRITE ? "WRITE" : "READ",
           len,
           rc);
    fflush(stdout);
}

static const char *probe_result_name(enum gxfp_probe_result result)
{
    switch (result) {
    case GXFP_PROBE_OK: return "OK";
    case GXFP_PROBE_PREAMBLE_ERROR: return "PREAMBLE_ERROR";
    case GXFP_PROBE_DRIVERSTATE_RESET_ERROR: return "DRIVERSTATE_RESET_ERROR";
    case GXFP_PROBE_ACK_TIMEOUT: return "ACK_TIMEOUT";
    case GXFP_PROBE_RESPONSE_TIMEOUT: return "RESPONSE_TIMEOUT";
    case GXFP_PROBE_CANCELLED: return "CANCELLED";
    case GXFP_PROBE_IO_ERROR: return "IO_ERROR";
    case GXFP_PROBE_CLEANUP_ERROR: return "CLEANUP_ERROR";
    case GXFP_PROBE_INVALID: return "INVALID";
    default: return "UNKNOWN";
    }
}

static const char *driver_state_result_name(enum gxfp_driver_state_result result)
{
    switch (result) {
    case GXFP_DRIVER_STATE_OK: return "OK";
    case GXFP_DRIVER_STATE_ACK_TIMEOUT: return "ACK_TIMEOUT";
    case GXFP_DRIVER_STATE_CANCELLED: return "CANCELLED";
    case GXFP_DRIVER_STATE_IO_ERROR: return "IO_ERROR";
    case GXFP_DRIVER_STATE_INVALID: return "INVALID";
    default: return "UNKNOWN";
    }
}

int main(void)
{
    static const uint8_t a4_payload[2] = {0x00, 0x00};
    struct sigaction sa;
    char spi_path[256];
    struct gxfp_spi spi;
    struct gxfp_gpiod_reset *reset = NULL;
    struct gxfp_kernel_irq_runtime runtime;
    struct gxfp_linux_level_ops level_ops;
    struct gxfp_linux_active_backend active;
    struct gxfp_attempt_backend attempt;
    struct preamble_ctx pre_ctx;
    struct gxfp_probe_reset_ops reset_ops;
    struct gxfp_probe_preamble_ops preamble_ops;
    struct gxfp_probe_report report;
    enum gxfp_discovery_result discovery;
    enum gxfp_probe_result result;
    const uint8_t *response;
    size_t response_len = 0;
    unsigned transfer_seq = 0;
    int reset_after;
    int rc = 1;
    size_t i;

    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGINT, &sa, NULL) < 0 ||
        sigaction(SIGTERM, &sa, NULL) < 0) {
        fprintf(stderr, "signal setup failed\n");
        return 1;
    }

    discovery = gxfp_find_spidev_node(GXFP_SPI_SYSFS,
                                      GXFP_DEV_ROOT,
                                      spi_path,
                                      sizeof(spi_path));
    if (discovery != GXFP_DISCOVERY_OK) {
        fprintf(stderr, "spidev discovery failed: %d\n", discovery);
        return 1;
    }

    if (gxfp_spi_open_configure(&spi, spi_path, NULL) != 0) {
        fprintf(stderr, "SPI open/configure failed\n");
        return 1;
    }

    if (gxfp_gpiod_reset_open_as_is(&reset,
                                     GXFP_GPIO_CHIP,
                                     GXFP_RESET_OFFSET) != 0) {
        fprintf(stderr, "GPIO264 as-is output request failed\n");
        goto out_spi;
    }

    if (!gxfp_kernel_irq_runtime_open(&runtime, GXFP_IRQ_WAIT_DEV,
                                      cancelled_cb, NULL)) {
        fprintf(stderr, "kernel IRQ runtime open failed\n");
        goto out_reset;
    }
    if (runtime.info.hwirq != GXFP_EXPECTED_HWIRQ ||
        runtime.info.trigger_type != GXFP_EXPECTED_TRIGGER) {
        fprintf(stderr, "kernel IRQ contract mismatch\n");
        goto out_runtime;
    }
    gxfp_kernel_irq_runtime_get_level_ops(&runtime, &level_ops);

    if (!gxfp_linux_active_backend_init(&active, &spi, &level_ops,
                                        gxfp_kernel_irq_runtime_sleep_ms,
                                        &runtime) ||
        !gxfp_linux_active_backend_attempt(&active, &attempt)) {
        fprintf(stderr, "active backend init failed\n");
        goto out_runtime;
    }

    gxfp_linux_active_backend_set_trace(&active,
                                        transfer_trace,
                                        &transfer_seq);

    pre_ctx.active = &active;
    pre_ctx.attempt = &attempt;
    preamble_ops = (struct gxfp_probe_preamble_ops){
        .ctx = &pre_ctx,
        .send_nop = preamble_send_nop,
        .send_driver_install = preamble_send_install,
        .sleep_ms = preamble_sleep,
        .wait_ack = preamble_wait_ack,
    };
    reset_ops = (struct gxfp_probe_reset_ops){
        .ctx = reset,
        .set_level = reset_set_level,
        .sleep_ms = reset_sleep_ms,
    };

    printf("PROBE_BEGIN\n");
    printf("SPI_NODE=%s\n", spi_path);
    printf("SPI_MODE=%u\n", GXFP_SPI_MODE);
    printf("SPI_BITS=%u\n", GXFP_SPI_BITS_PER_WORD);
    printf("SPI_MAX_SPEED_HZ=%u\n", spi.max_speed_hz);
    printf("IRQ_SOURCE=KERNEL_ACPI_GPIOINT\n");
    printf("MAPPED_IRQ=%u\n", runtime.info.linux_irq);
    printf("MAPPED_HWIRQ=%llu\n", (unsigned long long)runtime.info.hwirq);
    printf("IRQ_TRIGGER=LEVEL_HIGH\n");
    printf("GPIO264_MODE=AS_IS_ALREADY_OUTPUT\n");
    printf("INITIAL_RESET=NO\n");
    printf("DRIVERSTATE_ACK_TARGET=96\n");
    printf("DRIVERSTATE_ACK_TIMEOUT_MS=1000\n");
    printf("A4_PAYLOAD_FIXTURE=00 00\n");
    printf("COMMON_INIT_RETRY_COUNT=3\n");
    printf("COMMON_INIT_RETRY_COUNT_PROVENANCE=PROVEN_COMPILED_DEFAULT_14136\n");
    printf("COMMON_INIT_FALLBACK=HARD_RESET_THEN_ONE_FINAL_ATTEMPT\n");
    fflush(stdout);

    result = gxfp_probe_run(&reset_ops, &preamble_ops, &attempt,
                            a4_payload, &report);

    reset_after = gxfp_gpiod_reset_get_level(reset);
    response = gxfp_linux_active_backend_response(&active, &response_len);

    printf("PROBE_RESULT=%s\n", probe_result_name(result));
    printf("PRIMARY_RESULT=%s\n", probe_result_name(report.primary_result));
    printf("DRIVERSTATE_RESULT=%s\n", driver_state_result_name(report.driver_state_result));
    printf("DRIVERSTATE_RESET_PERFORMED=%s\n", report.driver_state_reset_performed ? "YES" : "NO");
    printf("DRIVERSTATE_RESET_RESULT=%d\n",
           report.driver_state_reset_result);
    printf("COMMON_INIT_RESET_PERFORMED=%s\n",
           report.common_init_reset_performed ? "YES" : "NO");
    printf("COMMON_INIT_RESET_RESULT=%d\n",
           report.common_init_reset_result);
    printf("EVK_ATTEMPT_RESULT=%d\n", report.evk_result);
    printf("CLEANUP_RESULT=%d\n", report.cleanup_result);
    printf("SPI_TRANSFER_COUNT=%u\n", spi.transfer_count);
    printf("IRQ_WAIT_COUNT=%u\n", runtime.wait_count);
    printf("IRQ_EVENT_COUNT=%u\n", runtime.event_count);
    printf("GPIO264_AFTER=%d\n", reset_after);
    printf("EVK_RESPONSE_LEN=%zu\n", response_len);
    printf("EVK_RESPONSE_HEX=");
    if (response != NULL) {
        for (i = 0; i < response_len; i++)
            printf("%02X", response[i]);
    }
    putchar('\n');
    fflush(stdout);

    if (report.cleanup_result != GXFP_IO_OK || reset_after != 0) {
        fprintf(stderr, "SAFETY_FAILURE: final GPIO264 LOW not confirmed\n");
        rc = 2;
    } else if (result == GXFP_PROBE_OK) {
        rc = 0;
    } else {
        rc = 3;
    }

out_runtime:
    gxfp_kernel_irq_runtime_close(&runtime);
out_reset:
    gxfp_gpiod_reset_close(reset);
out_spi:
    gxfp_spi_close(&spi);
    return rc;
}
