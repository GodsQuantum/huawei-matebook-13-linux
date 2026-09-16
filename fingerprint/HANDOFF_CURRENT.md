# Current handoff — GXFP51A0 / GF3658 Milan

**Updated: 2026-09-16 after factory-PMK integration and oversized TLS-GCM support.**

This is the shortest canonical resume point. First-contact evidence is in
[docs/first-contact-confirmed-2026-09-14.md](docs/first-contact-confirmed-2026-09-14.md),
target configuration in
[docs/target-config-confirmed-2026-09-14.md](docs/target-config-confirmed-2026-09-14.md),
the SGX host-secret research in
[docs/sgx-host-secret-path-2026-09-16.md](docs/sgx-host-secret-path-2026-09-16.md),
and the latest fast-track reassessment in
[docs/fast-track-assessment-2026-09-16.md](docs/fast-track-assessment-2026-09-16.md).

## Current state

```text
candidate libfprint v1.94.100 build       PASS
research unit/safety suite                PASS
first real sensor ACK under Linux         CONFIRMED
firmware                                  GF_ST411SEC_APP_14115
chip ID / OTP calibration                 CONFIRMED
target config                             CONFIRMED ON HARDWARE
TLS profile                               TLS1.2 / PSK-AES128-GCM-SHA256
F2 PMK retrieval                          CLOSED_NOT_APPLICABLE
legacy /dev/isgx path                     PASS
Intel production Launch Enclave EINIT     PASS
WBDI PE / SGX metadata parser             PASS
WBDI exact private structure gate         PASS
GDIX51C0 same-die Linux path              CONFIRMED REFERENCE
E4 14115 AAAA/32-byte variant             CONFIRMED ON PEGASUS
E0 Linux-owned PSK provisioning           CLOSED_NO_HANDLER
factory flash PMK decrypt                 IMPLEMENTED + TESTED OFFLINE
factory redundant-prefix loader           SOFTWARE BUILD PASS
TLS EMS disabled                           REGRESSION PASS
oversized ~22 kB AES-GCM record decrypt    REGRESSION PASS
manual GCM sequence handling               CONFIRMED + REGRESSION PASS
live TLS on GXFP51A0/14115                CONFIRMED EXTERNAL
Pegasus kernel / spidev module match        PASS (7.2.5)
Pegasus factory-read hardware probe         CLOSED_BY_F2_WINDOW
Pegasus PMK + live TLS                     CURRENT BOUNDARY
WBDI MRENCLAVE reproduction               FALLBACK RESEARCH
image/capture hardware                     NOT REACHED
```

## Confirmed sensor-side recipe

```text
GPIO264 HIGH 300 ms        active MCU reset
GPIO264 LOW                MCU running
settle after LOW           600 ms
SPI CPOL/CPHA              mode 0
Linux CS mode bit          SPI_CS_HIGH (0x04)
SPI rate                   1 MHz (currently proven rate)
final GPIO264              LOW
```

A8 ACK and EVK response are confirmed. Target config performs A2 reset, chip ID
`0x2504`, 64-byte OTP parsing, OTP-derived tcode/FDT/DAC calibration and exact
0x90 config upload.

Target TLS is pinned to suite `0x00A8`, `PSK-AES128-GCM-SHA256`, TLS 1.2,
sensor client / host server, identity `Client_identity`. Software GCM handshake
and large-record regression pass.

## Host PMK boundary

The previous APP-mode provisioning fast track is now closed for exact firmware
14115. A read-only Pegasus `E4` probe returned status `0`, type `0x0000aaaa` and
32 bytes; exact-target static analysis reproduces that response and shows the
corresponding `E0`/operation-0 entry is a no-op. Do not attempt the GDIX51C0
`0xbb010003` write on this firmware.

The shortest path is instead the existing factory flash record. Independent
work on another GXFP51A0/14115 has recovered its complete decrypt scheme and
used the resulting 48-byte PSK for a successful live TLS 1.2
`PSK-AES128-GCM-SHA256` handshake. The flash decrypt is AES-128-CBC with a
SHA-256-derived key and salt-derived IV; the plaintext record is type `0x000d`,
length `0x30`, followed by the full 48-byte PSK.

Exact 14115 handler analysis now explains the Pegasus hardware result: F2
read operation 1 accepts only the application-flash window from `0x08020000`
through `0x08040000`. The factory records below that range are rejected before
copy-out, which is why Pegasus returns the request echo but no memory data.
The driver therefore must not use F2 as a factory-PMK provider on this target.
The strict F2 parser remains useful for the validated application-flash window.
The offline factory-record decryptor and redundant-copy consensus tests remain in
the repository as compatibility research, but the GXFP51A0 runtime no longer
invokes them on Pegasus. E4 remains only an exact-14115 sanity check and is not
treated as a hash of the factory record or PMK. Any future PMK provider must keep
key bytes in memory only and cleanse them on close/failure.

The previously validated legacy SGX/WBDI work remains useful as a fallback and
Windows-compatibility path, but it is no longer on the critical path to a Linux
driver.

## Software validation

```bash
make -C fingerprint verify
```

Fresh validation on 2026-09-16 passed the complete research suite, source
manifest, libfprint v1.94.100 build, privacy scan and `git diff --check` with no
sensor I/O, GPIO/MMIO write or firmware action.

## Next boundary

Pegasus is booted on kernel 7.2.5 with a matching in-tree `spidev` module.
The read-only factory-window probe has completed and restored GPIO264 LOW; its
result is now explained by the exact firmware F2 address gate above.

Work in this order:

1. keep factory-via-F2 disabled on Pegasus; the exact 14115 address window closes it;
2. resolve the remaining 48-byte PMK through a validated host-side provider
   (or a newly proven alternate sensor path), never from guessed F2 addresses;
3. establish TLS 1.2 `PSK-AES128-GCM-SHA256` with EMS disabled;
4. verify a small encrypted FDT `0x36` exchange before asking for an image;
5. reach the first ChicagoHS image record and validate the oversized-record GCM
   path already covered by the 22,176-byte software regression;
6. reach the first decoded 80x64 frame, then enrol/verify and fprintd/PAM.

## Do not reopen without new evidence

- DMA versus PIO;
- runtime PM as primary cause;
- Linux IRQ mapping;
- DeviceInit `besdenable` as missing sensor I/O;
- GPIO112/GPP_D16 or hidden LPSS switch;
- unchanged normal-CS replay;
- GXFP5187 PMK address assumptions;
- untimed F2 runtime-RAM PMK hunting;
- WinPE/QEMU while the native SGX route remains viable.

## Canonical files

1. `HANDOFF_CURRENT.md`
2. `docs/fast-track-assessment-2026-09-16.md`
3. `docs/sgx-host-secret-path-2026-09-16.md`
4. `docs/target-config-confirmed-2026-09-14.md`
5. `docs/first-contact-confirmed-2026-09-14.md`
6. `driver/goodix51a0/README.md`
7. `docs/research-log.md`
8. `docs/safety.md`
9. `FINAL_HANDOFF_2026-09-08.md` (historical checkpoint)

## Public-repository locks

No proprietary binaries/firmware, raw DSM material, PMK/PSK or derived keys,
private machine identifiers, local user paths or bulk proprietary disassembly.

No firmware write, speculative MMIO/pinmux write or GPIO112 write without new
exact-target evidence. Every active sensor experiment must leave GPIO264 LOW.
