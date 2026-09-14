#!/usr/bin/env python3
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"fingerprint/driver/goodix51a0/goodix51a0.c"
TRANSPORT=ROOT/"fingerprint/driver/goodix51a0/gx51_transport.c"
HEADER=ROOT/"fingerprint/driver/goodix51a0/goodix51a0.h"
TARGET=ROOT/"fingerprint/driver/goodix51a0/gx51_target.c"
TARGET_HEADER=ROOT/"fingerprint/driver/goodix51a0/gx51_target.h"
text=SRC.read_text(encoding="utf-8")
transport=TRANSPORT.read_text(encoding="utf-8")
header=HEADER.read_text(encoding="utf-8")
target=TARGET.read_text(encoding="utf-8")
target_header=TARGET_HEADER.read_text(encoding="utf-8")

def fn(name):
    pos=text.find(name+" (")
    if pos<0: pos=text.find(name+"(")
    assert pos>=0,name
    brace=text.find("{",pos); depth=0
    for i in range(brace,len(text)):
        if text[i]=="{": depth+=1
        elif text[i]=="}":
            depth-=1
            if depth==0:return text[pos:i+1]
    raise AssertionError(name)

ds=fn("gx_driverstate_install_windows")
evk=fn("gx_read_fw_version_once")
op=fn("gx_dev_open")
gate=fn("gx_upload_config_and_reqtls")

assert "GX_AMORCE" in ds
assert re.search(r"g_usleep\s*\(\s*5000\s*\)",ds)
assert "wrapper < 2" in ds and "attempt < 2" in ds
assert ds.find("GX_AMORCE") < ds.find("GX_ENABLE")

assert "send_index < 2" in evk
assert "cached_n = 0" in evk
assert re.search(r"g_usleep\s*\(\s*5000\s*\)",evk)

first_ds=op.find("gx_driverstate_install_windows")
first_reset=op.find("gx_gpio_reset")
assert first_ds>=0 and first_reset>first_ds
assert op.count("gx_driverstate_install_windows")==1

assert "gx_target_configure" in text
assert "gxfp_derive_calibration" in text
assert "gxfp_patch_config" in text
assert "GXFP_TARGET_BASE_CONFIG" in text
assert "gx_target_configure (self)" in gate
assert "GXFP51A0: target config gate blocked pending live hardware validation" not in gate
assert "GXFP51A0: PMK/PSK gate blocked pending exact target key source" in gate
assert "return FALSE;" in gate
assert "#define GOODIX_IMG_WIDTH   80" in header
assert "#define GOODIX_IMG_HEIGHT  64" in header
assert "const uint8_t GXFP_TARGET_BASE_CONFIG" in target
assert "GXFP_TARGET_PMK_ADDR" not in target_header
assert "GXFP_TARGET_PMK_LEN_ADDR" not in target_header
assert 10 + 4*6 == 34

psk=fn("gx_read_psk")
for spi_setup in (op, psk):
    assert "SPI_MODE_0 | SPI_CS_HIGH" in spi_setup
    assert re.search(r"guint32\s+speed\s*=\s*1000000\s*;", spi_setup)

assert "gx51_sleep_us(300000)" in transport
assert "gx51_sleep_us(600000)" in transport
assert "val.bits = 1; /* HIGH: active reset */" in transport
assert "val.bits = 0; /* LOW: MCU runs */" in transport

print("GOODIX51A0_FIRST_CONTACT_SOURCE_TEST=PASS")
