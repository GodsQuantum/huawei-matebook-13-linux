#!/usr/bin/env python3
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"fingerprint/driver/goodix51a0/goodix51a0.c"
TRANSPORT=ROOT/"fingerprint/driver/goodix51a0/gx51_transport.c"
HEADER=ROOT/"fingerprint/driver/goodix51a0/goodix51a0.h"
TARGET=ROOT/"fingerprint/driver/goodix51a0/gx51_target.c"
TARGET_HEADER=ROOT/"fingerprint/driver/goodix51a0/gx51_target.h"
FACTORY=ROOT/"fingerprint/driver/goodix51a0/gx51_factory_pmk.c"
FACTORY_HEADER=ROOT/"fingerprint/driver/goodix51a0/gx51_factory_pmk.h"
text=SRC.read_text(encoding="utf-8")
transport=TRANSPORT.read_text(encoding="utf-8")
header=HEADER.read_text(encoding="utf-8")
target=TARGET.read_text(encoding="utf-8")
target_header=TARGET_HEADER.read_text(encoding="utf-8")
factory=FACTORY.read_text(encoding="utf-8")
factory_header=FACTORY_HEADER.read_text(encoding="utf-8")

def fn(name):
    m=re.search(r"\b"+re.escape(name)+r"\s*\([^;{}]*\)\s*\n\{", text)
    assert m is not None,name
    pos=m.start()
    brace=text.find("{",m.end()-1); depth=0
    for i in range(brace,len(text)):
        if text[i]=="{": depth+=1
        elif text[i]=="}":
            depth-=1
            if depth==0:return text[pos:i+1]
    raise AssertionError(name)

ds=fn("gx_driverstate_install_windows")
evk=fn("gx_read_fw_version_once")
op=fn("gx_dev_open")
transport_open=fn("gx_transport_open")
cold=fn("gx_cold_prepare")
probe=fn("gx_dev_probe")
gate=fn("gx_upload_config_and_reqtls")
staging=fn("gx_factory_load_staging_pmk")
staging_read=fn("gx_factory_staging_read_cb")

assert "GX_AMORCE" in ds
assert re.search(r"g_usleep\s*\(\s*5000\s*\)",ds)
assert "wrapper < 2" in ds and "attempt < 2" in ds
assert ds.find("GX_AMORCE") < ds.find("GX_ENABLE")

assert "send_index < 2" in evk
assert "cached_n = 0" in evk
assert re.search(r"g_usleep\s*\(\s*5000\s*\)",evk)

# rel26 keeps libfprint enumeration passive. The real Claim/open owns
# first-contact preparation and must propagate a preparation failure.
# Preserve the validated Windows ordering inside gx_cold_prepare: DriverState
# must be attempted before its reviewed reset fallback.
first_ds=cold.find("gx_driverstate_install_windows")
first_reset=cold.find("gx_gpio_reset")
assert first_ds>=0 and first_reset>first_ds
assert cold.count("gx_driverstate_install_windows")==1
assert "gx_transport_open (dev, &err)" in op
assert "if (!gx_cold_prepare (self))" in op
assert "gx_transport_open (dev, &err)" in probe
assert "gx_transport_close (self)" in probe
assert "gx_cold_prepare (self)" not in probe

assert "gx_target_configure" in text
assert "gxfp_derive_calibration" in text
assert "gxfp_patch_config" in text
assert "GXFP_TARGET_BASE_CONFIG" in text
assert "gx_gpio_reset (self)" in gate
assert "gx_factory_acquire_staging_pmk (self, allow_cache)" in gate
assert "gx_target_configure (self)" in gate
assert "GX_REQTLS" in gate
assert gate.find("gx_factory_acquire_staging_pmk (self, allow_cache)") < gate.find("gx_gpio_reset (self)")
assert gate.find("gx_gpio_reset (self)") < gate.find("gx_target_configure (self)")
assert gate.find("gx_target_configure (self)") < gate.find("GX_REQTLS")
assert "gxfp_factory_load_pmk (gx_factory_mem_read_cb" not in text
assert "gxfp_factory_load_pmk_from_single_staging" in staging
assert staging.find("gxfp_factory_load_pmk_from_single_staging") < staging.find("gx_factory_e4_sanity")
assert "gxfp_14115_parse_rejected_staging_response" in staging_read
assert "gxfp_factory_load_pmk" in factory
assert "gxfp_factory_pmk_recover_first_byte" in factory
assert "CRYPTO_memcmp" in factory and "OPENSSL_cleanse" in factory
assert "GXFP_FACTORY_PMK_LEN 48u" in factory_header
assert "GXFP_FACTORY_BODY_LEN 256u" in factory_header
assert "GXFP_FACTORY_READ_LEN 80u" in factory_header
assert "gx_factory_e4_sanity" in text
assert "CRYPTO_memcmp (candidates[i], candidates[j]" in factory
assert "gxfp_parse_mem_read_response" in target
assert "GXFP_MEM_READ_ECHO_ONLY" in target
assert "gxfp_14115_parse_rejected_staging_response" in target
assert "This is a legitimate 14115 app-flash read" in target
assert "gxfp_parse_factory_hash_response" in target
assert "#define GOODIX_IMG_WIDTH   80" in header
assert "#define GOODIX_IMG_HEIGHT  64" in header
assert "const uint8_t GXFP_TARGET_BASE_CONFIG" in target
assert "GXFP_TARGET_PMK_ADDR" not in target_header
assert "GXFP_TARGET_PMK_LEN_ADDR" not in target_header
assert 10 + 4*6 == 34

assert "gx_read_psk" not in text
assert "SPI_MODE_0 | SPI_CS_HIGH" in transport_open
assert re.search(r"guint32\s+speed\s*=\s*1000000\s*;", transport_open)
assert "gx_pmk_clear (self);" in fn("gx_dev_close")
assert "OPENSSL_cleanse (self->psk" in fn("gx_pmk_clear")
assert "self->psk_ready = FALSE;" in fn("gx_pmk_clear")
assert "self->timing_scale = gx_timing_load ();" in cold
assert "self->timing_saved = self->timing_scale;" in cold
assert "gx_adapt_sweep ();" not in cold
assert "GX_ADAPT_" not in text

assert "gx51_sleep_us(300000)" in transport
assert "gx51_sleep_us(600000)" in transport
assert "val.bits = 1; /* HIGH: active reset */" in transport
assert "val.bits = 0; /* LOW: MCU runs */" in transport

print("GOODIX51A0_FIRST_CONTACT_SOURCE_TEST=PASS")
