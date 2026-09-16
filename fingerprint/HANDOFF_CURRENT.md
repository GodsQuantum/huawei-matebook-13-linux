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
factory 256-byte redundant loader          SOFTWARE BUILD PASS
TLS EMS disabled                           REGRESSION PASS
oversized ~22 kB AES-GCM record decrypt    REGRESSION PASS
live TLS on GXFP51A0/14115                CONFIRMED EXTERNAL
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

F2 can address the relevant flash (and can address RAM), but direct PMK hunting
in runtime RAM remains closed. Pegasus historically returned the direct
`F2|len|data|checksum` response shape, while another 14115 unit prepends an
8-byte request echo; the driver parser accepts only those two exact forms with
strict length/checksum validation. Factory headers must be read from the aligned
record base: an unaligned `base+3` read on Pegasus reflected request metadata into
the apparent payload and produced bogus address-shaped lengths. Each factory copy
has an 8-byte header whose declared body length is `0x100` (256 bytes). The body is 16 bytes of salt plus
240 bytes of AES-128-CBC ciphertext. F2 may corrupt the first byte of a read, so
the loader recovers that byte by requiring a unique type-`0x000d` / length-48
decrypt candidate, then requires matching PMKs from at least two of the three
redundant factory copies. E4 is retained only as an exact-14115 sanity check; it
is not treated as a SHA-256 of the body or PMK. PMK bytes exist only in memory
and are cleansed on close/failure; they are never logged or stored by the driver.

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

Work in this order:

1. run the read-only factory→PMK-in-RAM→config→D0→TLS probe on Pegasus;
2. require 2-of-3 redundant factory-copy PMK consensus and successful TLS 1.2
   `PSK-AES128-GCM-SHA256` handshake with EMS disabled;
3. verify a small encrypted FDT `0x36` exchange before asking for an image;
4. reach the first ChicagoHS image record and validate the oversized-record GCM
   path already covered by the 22,176-byte software regression;
5. reach the first decoded 80x64 frame, then enrol/verify and fprintd/PAM;
6. resume WBDI/SGX only if the factory-secret path fails exact-target validation.

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
