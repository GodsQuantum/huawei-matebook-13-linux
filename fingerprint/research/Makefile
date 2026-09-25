CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -Werror -pedantic -O2

BUILD_DIR ?= ../../../temp/research-build

TEST_ATTEMPT := $(BUILD_DIR)/test_milan_attempt
TEST_PACKET := $(BUILD_DIR)/test_milan_packet
TEST_TARGET_INIT := $(BUILD_DIR)/test_target_init
TEST_GOODIX_TLS_GCM := $(BUILD_DIR)/test_goodix_tls_gcm
TEST_FACTORY_PMK := $(BUILD_DIR)/test_factory_pmk
TEST_GX51_IMAGE := $(BUILD_DIR)/test_gx51_image
TEST_CAPTURE_RECIPE := $(BUILD_DIR)/test_capture_recipe
TEST_TRANSPORT_CHUNKING := $(BUILD_DIR)/test_transport_chunking
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

.PHONY: all prepare-build test clean test_target_init test_goodix_tls_gcm test_factory_pmk test_gx51_image test_capture_recipe test_transport_chunking test_driver_staging_source_safety test_fdt_runtime_source_safety test_fdt_probe_retry_source_safety test_driver_chunked_read_source_safety test_capture_cleanup_runtime_source_safety test_same_press_verify_source_safety test_warm_rebase_source_safety test_finalize_warm_teardown_source_safety test_verify_trace_protocol_source_safety test_plain_drain_short_irq_source_safety test_get_image_retry_source_safety test_get_image_ack_tls_timeout_recovery_source_safety test_driver_reset_low_source_safety test_target_response_timing_source_safety test_post_pmk_reset_source_safety test_pmk_retry_source_safety test_factory_staging_diagnostics_source_safety test_single_staging_runtime_source_safety test_runtime_gpio48_poll_source_safety test_post_pmk_stage2e_boundary_source_safety test_target_irq_quiesce_source_safety test_target_ack_retry_source_safety test_target_ack_timeout_source_safety test_pmk_cache_source_safety test_pmk_cache_retention_source_safety test_tls_only_diagnostic_source_safety test_tls_trace_source_safety test_tls_irq_poll_bounds_source_safety test_capture_once_source_safety test_capture_waiting_prompt_source_safety test_capture_press_countdown_source_safety test_capture_clear_sensor_gate_source_safety test_capture_too_early_recovery_source_safety test_capture_dump_before_cleanup_source_safety test_milan_attempt test_milan_packet test_spidev_discovery test_linux_spi test_irq_logic test_milan_rx test_milan_rx_drain test_linux_active_backend test_probe_harness test_event_driven_backend test_active_runtime_source_safety test_probe_runtime_source_safety test_live_probe_supervisor test_pio_preflight test_pio_live_probe_supervisor test_pio_source_safety test_irq_wait_source_safety test_reset_restore_source_safety test_passive_safety test_makefile_space_build_dir passive-preflight active-runtime-compile probe-runtime-compile reset-restore-compile test_prepare_soft_preclaim_source_safety test_identify_source_safety test_release_biometric_dump_guard_source_safety test_fastbrief_ransac_source_safety test_capture_nop_fastpath_source_safety test_capture_event_drain_source_safety test_capture_no_reply_timeout_source_safety test_gallery_diagnostic_source_safety test_pixel_diagnostic_source_safety test_verify_fixed_retry_source_safety test_capture_gap_nominal_source_safety test_session_local_timing_source_safety test_capture_transport_recovery_source_safety test_lifecycle_recovery_source_safety test_native_resume_recovery_source_safety test_boot_prewarm_source_safety test_fresh_warm_handoff_source_safety test_warm_keepalive_source_safety test_kde_instant_auth_source_safety test_plasma_login_dual_auth_source_safety test_windows_wakeup_identify_same_press_source_safety

all: test

prepare-build:
	@mkdir -p -- "$(BUILD_DIR)"

test_milan_attempt: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_milan_attempt.c milan_attempt.c -o "$(TEST_ATTEMPT)"
	"$(TEST_ATTEMPT)"

test_milan_packet: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_milan_packet.c milan_packet.c -o "$(TEST_PACKET)"
	"$(TEST_PACKET)"

test_target_init: prepare-build
	$(CC) $(CFLAGS) -I. tests/test_target_init.c ../driver/goodix51a0/gx51_target.c -o "$(TEST_TARGET_INIT)"
	"$(TEST_TARGET_INIT)"

test_goodix_tls_gcm: prepare-build
	$(CC) $(CFLAGS) -I../driver/goodix51a0 $$(pkg-config --cflags gio-2.0 openssl) \
		tests/test_goodix_tls_gcm.c ../driver/goodix51a0/goodix_tls.c \
		$$(pkg-config --libs gio-2.0 openssl) -pthread -o "$(TEST_GOODIX_TLS_GCM)"
	"$(TEST_GOODIX_TLS_GCM)"

test_factory_pmk: prepare-build
	$(CC) $(CFLAGS) -I../driver/goodix51a0 $$(pkg-config --cflags openssl) \
		tests/test_factory_pmk.c ../driver/goodix51a0/gx51_factory_pmk.c \
		$$(pkg-config --libs openssl) -o "$(TEST_FACTORY_PMK)"
	"$(TEST_FACTORY_PMK)"

test_gx51_image: prepare-build
	$(CC) $(CFLAGS) -I../driver/goodix51a0 tests/test_gx51_image.c ../driver/goodix51a0/gx51_image.c -o "$(TEST_GX51_IMAGE)"
	"$(TEST_GX51_IMAGE)"

test_capture_recipe: prepare-build
	$(CC) $(CFLAGS) -I../driver/goodix51a0 tests/test_capture_recipe.c ../driver/goodix51a0/gx51_capture_recipe.c ../driver/goodix51a0/gx51_target.c -o "$(TEST_CAPTURE_RECIPE)"
	"$(TEST_CAPTURE_RECIPE)"

test_transport_chunking: prepare-build
	$(CC) $(CFLAGS) -I../driver/goodix51a0 tests/test_transport_chunking.c ../driver/goodix51a0/gx51_transport.c -o "$(TEST_TRANSPORT_CHUNKING)"
	"$(TEST_TRANSPORT_CHUNKING)"

test_driver_staging_source_safety:
	./tests/test_driver_staging_source_safety.sh

test_fdt_runtime_source_safety:
	./tests/test_fdt_runtime_source_safety.sh

test_fdt_probe_retry_source_safety:
	./tests/test_fdt_probe_retry_source_safety.sh

test_driver_chunked_read_source_safety:
	./tests/test_driver_chunked_read_source_safety.sh

test_capture_cleanup_runtime_source_safety:
	./tests/test_capture_cleanup_runtime_source_safety.sh

test_same_press_verify_source_safety:
	./tests/test_same_press_verify_source_safety.sh

test_warm_rebase_source_safety:
	./tests/test_warm_rebase_source_safety.sh

test_finalize_warm_teardown_source_safety:
	./tests/test_finalize_warm_teardown_source_safety.sh

test_verify_trace_protocol_source_safety:
	./tests/test_verify_trace_protocol_source_safety.sh

test_plain_drain_short_irq_source_safety:
	./tests/test_plain_drain_short_irq_source_safety.sh

test_get_image_retry_source_safety:
	./tests/test_get_image_retry_source_safety.sh

test_get_image_ack_tls_timeout_recovery_source_safety:
	./tests/test_get_image_ack_tls_timeout_recovery_source_safety.sh

test_driver_reset_low_source_safety:
	./tests/test_driver_reset_low_source_safety.sh

test_target_response_timing_source_safety:
	./tests/test_target_response_timing_source_safety.sh

test_post_pmk_reset_source_safety:
	./tests/test_post_pmk_reset_source_safety.sh

test_pmk_retry_source_safety:
	./tests/test_pmk_retry_source_safety.sh

test_factory_staging_diagnostics_source_safety:
	./tests/test_factory_staging_diagnostics_source_safety.sh

test_single_staging_runtime_source_safety:
	./tests/test_single_staging_runtime_source_safety.sh

test_runtime_gpio48_poll_source_safety:
	./tests/test_runtime_gpio48_poll_source_safety.sh

test_post_pmk_stage2e_boundary_source_safety:
	./tests/test_post_pmk_stage2e_boundary_source_safety.sh

test_target_irq_quiesce_source_safety:
	./tests/test_target_irq_quiesce_source_safety.sh

test_target_ack_retry_source_safety:
	./tests/test_target_ack_retry_source_safety.sh

test_target_ack_timeout_source_safety:
	./tests/test_target_ack_timeout_source_safety.sh

test_pmk_cache_source_safety:
	./tests/test_pmk_cache_source_safety.sh

test_pmk_cache_retention_source_safety:
	./tests/test_pmk_cache_retention_source_safety.sh

test_tls_only_diagnostic_source_safety:
	./tests/test_tls_only_diagnostic_source_safety.sh

test_tls_trace_source_safety:
	./tests/test_tls_trace_source_safety.sh

test_tls_irq_poll_bounds_source_safety:
	./tests/test_tls_irq_poll_bounds_source_safety.sh

test_capture_once_source_safety:
	./tests/test_capture_once_source_safety.sh

test_capture_waiting_prompt_source_safety:
	./tests/test_capture_waiting_prompt_source_safety.sh

test_capture_press_countdown_source_safety:
	./tests/test_capture_press_countdown_source_safety.sh

test_capture_clear_sensor_gate_source_safety:
	./tests/test_capture_clear_sensor_gate_source_safety.sh

test_capture_too_early_recovery_source_safety:
	./tests/test_capture_too_early_recovery_source_safety.sh

test_capture_dump_before_cleanup_source_safety:
	./tests/test_capture_dump_before_cleanup_source_safety.sh

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

test: test_milan_attempt test_milan_packet test_target_init test_goodix_tls_gcm test_factory_pmk test_gx51_image test_capture_recipe test_transport_chunking test_driver_staging_source_safety test_fdt_runtime_source_safety test_fdt_probe_retry_source_safety test_driver_chunked_read_source_safety test_capture_cleanup_runtime_source_safety test_same_press_verify_source_safety test_warm_rebase_source_safety test_finalize_warm_teardown_source_safety test_verify_trace_protocol_source_safety test_plain_drain_short_irq_source_safety test_get_image_retry_source_safety test_get_image_ack_tls_timeout_recovery_source_safety test_driver_reset_low_source_safety test_target_response_timing_source_safety test_post_pmk_reset_source_safety test_pmk_retry_source_safety test_factory_staging_diagnostics_source_safety test_single_staging_runtime_source_safety test_runtime_gpio48_poll_source_safety test_post_pmk_stage2e_boundary_source_safety test_target_irq_quiesce_source_safety test_target_ack_retry_source_safety test_target_ack_timeout_source_safety test_pmk_cache_source_safety test_pmk_cache_retention_source_safety test_tls_only_diagnostic_source_safety test_tls_trace_source_safety test_tls_irq_poll_bounds_source_safety test_capture_once_source_safety test_capture_waiting_prompt_source_safety test_capture_press_countdown_source_safety test_capture_clear_sensor_gate_source_safety test_capture_too_early_recovery_source_safety test_capture_dump_before_cleanup_source_safety test_spidev_discovery test_linux_spi test_irq_logic test_milan_rx test_milan_rx_drain test_linux_active_backend test_probe_harness test_event_driven_backend test_active_runtime_source_safety test_probe_runtime_source_safety test_live_probe_supervisor test_pio_preflight test_pio_live_probe_supervisor test_pio_source_safety test_irq_wait_source_safety test_reset_restore_source_safety test_passive_safety test_makefile_space_build_dir test_template_versioning_source_safety test_production_clean_calibration_source_safety test_kde_enroll_ui_feedback_source_safety test_portable_preclaim_prepare_source_safety test_portable_installer_source_safety test_verify_early_report_source_safety test_prepare_soft_preclaim_source_safety test_identify_source_safety test_release_biometric_dump_guard_source_safety test_fastbrief_ransac_source_safety test_capture_nop_fastpath_source_safety test_capture_event_drain_source_safety test_capture_no_reply_timeout_source_safety test_gallery_diagnostic_source_safety test_pixel_diagnostic_source_safety test_verify_fixed_retry_source_safety test_capture_gap_nominal_source_safety test_session_local_timing_source_safety test_capture_transport_recovery_source_safety test_lifecycle_recovery_source_safety test_native_resume_recovery_source_safety test_boot_prewarm_source_safety test_fresh_warm_handoff_source_safety test_warm_keepalive_source_safety test_kde_instant_auth_source_safety test_plasma_login_dual_auth_source_safety test_windows_wakeup_identify_same_press_source_safety test_prepare_pacing_neutral_source_safety test_retry_assisted_capture_calibration_source_safety test_adaptive_identify_pose_budget_source_safety test_gq_sigfm_fpeval_source_safety

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

test_template_versioning_source_safety:
	./tests/test_template_versioning_source_safety.sh

test_production_clean_calibration_source_safety:
	./tests/test_production_clean_calibration_source_safety.sh

test_kde_enroll_ui_feedback_source_safety:
	./tests/test_kde_enroll_ui_feedback_source_safety.sh

test_portable_preclaim_prepare_source_safety:
	./tests/test_portable_preclaim_prepare_source_safety.sh

test_verify_early_report_source_safety:
	./tests/test_verify_early_report_source_safety.sh

test_prepare_soft_preclaim_source_safety:
	./tests/test_prepare_soft_preclaim_source_safety.sh

test_identify_source_safety:
	./tests/test_identify_source_safety.sh

test_release_biometric_dump_guard_source_safety:
	./tests/test_release_biometric_dump_guard_source_safety.sh

test_fastbrief_ransac_source_safety:
	./tests/test_fastbrief_ransac_source_safety.sh

test_capture_nop_fastpath_source_safety:
	./tests/test_capture_nop_fastpath_source_safety.sh

test_capture_event_drain_source_safety:
	./tests/test_capture_event_drain_source_safety.sh

test_capture_no_reply_timeout_source_safety:
	./tests/test_capture_no_reply_timeout_source_safety.sh

test_gallery_diagnostic_source_safety:
	./tests/test_gallery_diagnostic_source_safety.sh


test_pixel_diagnostic_source_safety:
	./tests/test_pixel_diagnostic_source_safety.sh

test_verify_fixed_retry_source_safety:
	./tests/test_verify_fixed_retry_source_safety.sh

test_capture_gap_nominal_source_safety:
	./tests/test_capture_gap_nominal_source_safety.sh

test_capture_transport_recovery_source_safety:
	./tests/test_capture_transport_recovery_source_safety.sh

test_lifecycle_recovery_source_safety:
	./tests/test_lifecycle_recovery_source_safety.sh

test_native_resume_recovery_source_safety:
	./tests/test_native_resume_recovery_source_safety.sh

test_boot_prewarm_source_safety:
	./tests/test_boot_prewarm_source_safety.sh

test_fresh_warm_handoff_source_safety:
	./tests/test_fresh_warm_handoff_source_safety.sh

test_warm_keepalive_source_safety:
	./tests/test_warm_keepalive_source_safety.sh

test_kde_instant_auth_source_safety:
	./tests/test_kde_instant_auth_source_safety.sh


test_plasma_login_dual_auth_source_safety:
	./tests/test_plasma_login_dual_auth_source_safety.sh


test_windows_wakeup_identify_same_press_source_safety:
	./tests/test_windows_wakeup_identify_same_press_source_safety.sh


test_session_local_timing_source_safety:
	./tests/test_session_local_timing_source_safety.sh


test_portable_installer_source_safety:
	./tests/test_portable_installer_source_safety.sh

test_prepare_pacing_neutral_source_safety:
	./tests/test_prepare_pacing_neutral_source_safety.sh


test_retry_assisted_capture_calibration_source_safety:
	./tests/test_retry_assisted_capture_calibration_source_safety.sh


test_adaptive_identify_pose_budget_source_safety:
	./tests/test_adaptive_identify_pose_budget_source_safety.sh


test_gq_sigfm_fpeval_source_safety:
	./tests/test_gq_sigfm_fpeval_source_safety.sh
