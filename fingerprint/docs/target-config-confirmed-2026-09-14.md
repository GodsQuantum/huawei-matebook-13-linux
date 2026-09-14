# GXFP51A0 target configuration confirmed on Linux — 2026-09-14

This note records the next hardware boundary after first contact. The exact
GXFP51A0 / ChicagoHS initialization path was executed on the MateBook 13 2021
target at 1 MHz, SPI mode 0 + `SPI_CS_HIGH`, with GPIO264 released LOW.

No firmware update, PMK write, `_DSM` mutation, MMIO write or GPIO112 action
was performed.

## Hardware result

The target answered every prerequisite in sequence:

```text
EVK firmware                 GF_ST411SEC_APP_14115
A2 reset response            0x010008
chip ID                      0x2504
OTP length                   64 bytes
OTP CRC validation           PASS
tcode                        256
FDT delta                    33
DAC main / 1 / 2 / 3         0x0b68 / 0xb8 / 0xb6 / 0xb6
```
The four DAC register writes were acknowledged with successful ACK state
(`0x03` before TLS). The exact 256-byte target configuration was then uploaded
with command `0x90`.

The sensor returned:

```text
CONFIG_ACK_STATUS       0x03
CONFIG_RESPONSE_STATUS  0x01
TARGET_CONFIG           PASS
GPIO264 final           LOW
```

The ACK status is accepted when bit 0 is set. Status `0x03` therefore means the
command succeeded while the pre-TLS gate bit remains set; it is not a failure.
The separate `0x90` response status `0x01` confirms the configuration itself was
accepted.

## Candidate impact

The libfprint candidate may now use this same-device target-config path before
TLS. The implementation validates the OTP, derives calibration values, patches
the target config, recomputes its internal checksum and requires the `0x90`
response status `0x01`.
## Next boundary

TLS is still deliberately blocked until the target PMK is read and validated.
Exact ST411 firmware analysis identifies a dedicated PMK buffer and length
state used directly by the TLS setup routine, so the next active experiment is
a bounded `0xF2` read of that target-owned state.

The public repository must not contain the recovered PMK bytes. A successful
probe should retain only non-secret metadata such as length, stability and a
one-way digest; any raw key material remains private and local.

Do not substitute the GXFP5187 RAM address or any fixed key from sibling parts.
Do not enable firmware or PMK write paths.
