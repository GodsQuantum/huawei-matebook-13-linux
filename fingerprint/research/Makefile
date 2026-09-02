CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -pedantic -O2

BUILD_DIR ?= ../../../temp/research-build

TEST_ATTEMPT := $(BUILD_DIR)/test_milan_attempt
TEST_PACKET := $(BUILD_DIR)/test_milan_packet
TEST_DISCOVERY := $(BUILD_DIR)/test_spidev_discovery
TEST_LINUX_SPI := $(BUILD_DIR)/test_linux_spi
TEST_IRQ_LOGIC := $(BUILD_DIR)/test_irq_logic
TEST_MILAN_RX := $(BUILD_DIR)/test_milan_rx
TEST_MILAN_RX_DRAIN := $(BUILD_DIR)/test_milan_rx_drain
TEST_LINUX_ACTIVE_BACKEND := $(BUILD_DIR)/test_linux_active_backend
TEST_PROBE_HARNESS := $(BUILD_DIR)/test_probe_harness
TEST_EVENT_BACKEND := $(BUILD_DIR)/test_event_driven_backend
ACTIVE_RUNTIME_OBJ := $(BUILD_DIR)/active_runtime.o
PROBE_BIN := $(BUILD_DIR)/gxfp-live-probe
RESET_RESTORE_BIN := $(BUILD_DIR)/gxfp-reset-restore
PASSIVE_BIN := $(BUILD_DIR)/gxfp-passive-preflight

.PHONY: all prepare-build test clean test_milan_attempt test_milan_packet test_spidev_discovery test_linux_spi test_irq_logic test_milan_rx test_milan_rx_drain test_linux_active_backend test_probe_harness test_event_driven_backend test_active_runtime_source_safety test_probe_runtime_source_safety test_live_probe_supervisor test_pio_preflight test_pio_live_probe_supervisor test_pio_source_safety test_irq_wait_source_safety test_reset_restore_source_safety test_passive_safety test_makefile_space_build_dir passive-preflight active-runtime-compile probe-runtime-compile reset-restore-compile

all: test

prepare-build:
	@mkdir -p -- "$(BUILD_DIR)"

test_milan_attempt: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_milan_attempt.c milan_attempt.c -o "$(TEST_ATTEMPT)"
	"$(TEST_ATTEMPT)"

test_milan_packet: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_milan_packet.c milan_packet.c -o "$(TEST_PACKET)"
	"$(TEST_PACKET)"

test_spidev_discovery: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_spidev_discovery.c linux/spidev_discovery.c -o "$(TEST_DISCOVERY)"
	TMPDIR="$(BUILD_DIR)" "$(TEST_DISCOVERY)"

test_linux_spi: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_linux_spi.c linux/linux_spi.c -o "$(TEST_LINUX_SPI)"
	"$(TEST_LINUX_SPI)"

test_irq_logic: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_irq_logic.c linux/irq_logic.c -o "$(TEST_IRQ_LOGIC)"
	"$(TEST_IRQ_LOGIC)"

test_milan_rx: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_milan_rx.c milan_rx.c -o "$(TEST_MILAN_RX)"
	"$(TEST_MILAN_RX)"

test_milan_rx_drain: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_milan_rx_drain.c milan_rx.c milan_rx_drain.c milan_attempt.c -o "$(TEST_MILAN_RX_DRAIN)"
	"$(TEST_MILAN_RX_DRAIN)"

test_linux_active_backend: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_linux_active_backend.c linux/active_backend.c linux/linux_spi.c milan_packet.c milan_rx.c milan_rx_drain.c milan_attempt.c -o "$(TEST_LINUX_ACTIVE_BACKEND)"
	"$(TEST_LINUX_ACTIVE_BACKEND)"

test_probe_harness: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_probe_harness.c probe_harness.c milan_attempt.c -o "$(TEST_PROBE_HARNESS)"
	"$(TEST_PROBE_HARNESS)"

test_event_driven_backend: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_event_driven_backend.c linux/active_backend.c linux/linux_spi.c milan_packet.c milan_rx.c milan_rx_drain.c milan_attempt.c -o "$(TEST_EVENT_BACKEND)"
	"$(TEST_EVENT_BACKEND)"

test_active_runtime_source_safety:
	./tests/test_active_runtime_source_safety.sh

test_probe_runtime_source_safety:
	./tests/test_probe_runtime_source_safety.sh

test_live_probe_supervisor:
	./tests/test_live_probe_supervisor.sh

test_pio_preflight:
	./tests/test_pio_preflight.sh

test_pio_live_probe_supervisor:
	./tests/test_pio_live_probe_supervisor.sh

test_pio_source_safety:
	./tests/test_pio_source_safety.sh

test_irq_wait_source_safety:
	./tests/test_irq_wait_source_safety.sh

test_reset_restore_source_safety:
	./tests/test_reset_restore_source_safety.sh

test_passive_safety:
	./tests/test_passive_safety.sh

test_makefile_space_build_dir:
	./tests/test_makefile_space_build_dir.sh

test: test_milan_attempt test_milan_packet test_spidev_discovery test_linux_spi test_irq_logic test_milan_rx test_milan_rx_drain test_linux_active_backend test_probe_harness test_event_driven_backend test_active_runtime_source_safety test_probe_runtime_source_safety test_live_probe_supervisor test_pio_preflight test_pio_live_probe_supervisor test_pio_source_safety test_irq_wait_source_safety test_reset_restore_source_safety test_passive_safety test_makefile_space_build_dir

passive-preflight: prepare-build
	@major="$$(pkg-config --modversion libgpiod 2>/dev/null | cut -d. -f1)"; \
	if [ "$$major" != "2" ]; then \
		echo "ERROR: passive-preflight requires libgpiod major version 2" >&2; \
		exit 1; \
	fi
	$(CC) $(CFLAGS) -I. $$(pkg-config --cflags libgpiod) \
		linux/passive_preflight.c linux/spidev_discovery.c linux/linux_spi.c linux/gpiod_irq.c \
		$$(pkg-config --libs libgpiod) -o "$(PASSIVE_BIN)"
	@echo "$(PASSIVE_BIN)"

active-runtime-compile: prepare-build
	$(CC) $(CFLAGS) -I. -c linux/active_runtime.c -o "$(ACTIVE_RUNTIME_OBJ)"
	@echo "$(ACTIVE_RUNTIME_OBJ)"

probe-runtime-compile: prepare-build
	@major="$$(pkg-config --modversion libgpiod 2>/dev/null | cut -d. -f1)"; \
	if [ "$$major" != "2" ]; then \
		echo "ERROR: probe-runtime-compile requires libgpiod major version 2" >&2; \
		exit 1; \
	fi
	$(CC) $(CFLAGS) -I. $$(pkg-config --cflags libgpiod) \
		linux/probe_runtime.c linux/gpiod_reset.c linux/kernel_irq_runtime.c \
		linux/active_backend.c linux/linux_spi.c \
		linux/spidev_discovery.c probe_harness.c milan_packet.c milan_rx.c \
		milan_rx_drain.c milan_attempt.c \
		$$(pkg-config --libs libgpiod) -o "$(PROBE_BIN)"
	@echo "$(PROBE_BIN)"

reset-restore-compile: prepare-build
	@major="$$(pkg-config --modversion libgpiod 2>/dev/null | cut -d. -f1)"; \
	if [ "$$major" != "2" ]; then \
		echo "ERROR: reset-restore-compile requires libgpiod major version 2" >&2; \
		exit 1; \
	fi
	$(CC) $(CFLAGS) -I. $$(pkg-config --cflags libgpiod) \
		linux/reset_restore.c linux/gpiod_reset.c probe_harness.c milan_attempt.c \
		$$(pkg-config --libs libgpiod) -o "$(RESET_RESTORE_BIN)"
	@echo "$(RESET_RESTORE_BIN)"

clean:
	rm -rf -- "$(BUILD_DIR)"
