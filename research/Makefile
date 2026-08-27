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
ACTIVE_RUNTIME_OBJ := $(BUILD_DIR)/active_runtime.o
PASSIVE_BIN := $(BUILD_DIR)/gxfp-passive-preflight

.PHONY: all prepare-build test clean test_milan_attempt test_milan_packet test_spidev_discovery test_linux_spi test_irq_logic test_milan_rx test_milan_rx_drain test_linux_active_backend test_active_runtime_source_safety test_passive_safety test_makefile_space_build_dir passive-preflight active-runtime-compile

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

test_active_runtime_source_safety:
	./tests/test_active_runtime_source_safety.sh

test_passive_safety:
	./tests/test_passive_safety.sh

test_makefile_space_build_dir:
	./tests/test_makefile_space_build_dir.sh

test: test_milan_attempt test_milan_packet test_spidev_discovery test_linux_spi test_irq_logic test_milan_rx test_milan_rx_drain test_linux_active_backend test_active_runtime_source_safety test_passive_safety test_makefile_space_build_dir

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

clean:
	rm -rf -- "$(BUILD_DIR)"
