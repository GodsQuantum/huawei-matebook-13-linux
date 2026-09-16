# Current handoff — GXFP51A0 / GF3658 Milan

**Updated: 2026-09-16 after target-config/TLS integration and SGX host-secret validation.**

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
APP-mode preset-PSK compatibility         CURRENT BOUNDARY
WBDI MRENCLAVE reproduction               FALLBACK RESEARCH
image/capture                             NOT REACHED
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

F2 is no longer a candidate PMK transport: exact-target analysis shows its read
window is application flash and cannot expose the required host-secret storage.
Do not spend more time on F2 for PMK retrieval.

The matching Windows path instead obtains machine-specific ACPI `_DSM` data and
uses a signed SGX enclave to unseal the host secret. The successful Goodix
record semantics are type `13`, length `48`. Raw `_DSM`, PMK and enclave-derived
secret bytes remain private and must never enter this repository.

On the target machine, a one-shot legacy SGX boot has been validated: native
SGX ownership is masked, the compatible legacy `isgx` driver exposes
`/dev/isgx`, discovers EPC, and the Intel production Launch Enclave reaches
EINIT. The one-shot boot entry cleans itself and the following reboot returns
to the normal setup.

The Goodix WBDI image is PE32+ x86-64 with legacy SGX metadata 1.2. Its
`sgxmeta` is VirtualSize `0x754` / RawSize `0x800`: a `0x44`-byte legacy prefix
followed immediately by a standard `0x710`-byte SIGSTRUCT. Strict offline
parsing, malformed-input tests and the private exact-structure gate pass.

Matching Windows uRTS analysis additionally proves one 4 KiB page is submitted
per `enclave_load_data()` call. Current work is to reproduce the complete
ECREATE/EADD/EEXTEND stream and exact signed MRENCLAVE offline before any Goodix
enclave EINIT attempt.

## Software validation

```bash
make -C fingerprint verify
```

Fresh validation on 2026-09-16 passed the complete research suite, source
manifest, libfprint v1.94.100 build, privacy scan and `git diff --check` with no
sensor I/O, GPIO/MMIO write or firmware action.

## Next boundary

The shortest route has changed after comparison with the hardware-tested
GDIX51C0 driver, which uses the same `0x2504` / ChicagoHS profile. Work in this
order:

1. add a read-only APP-mode preset-PSK/hash probe on the exact `14115` target;
2. if compatible, validate the GDIX51C0 Linux-owned PSK provisioning contract
   against exact-target evidence, without firmware modification;
3. establish the existing TLS 1.2 PSK-GCM path with the provisioned Linux key;
4. adapt/reuse the proven ChicagoHS capture, calibration and matcher layers;
5. reach first 80x64 frame, then enrol/verify and fprintd/PAM integration;
6. keep WBDI/SGX reconstruction as fallback if APP-mode provisioning is not
   supported by this firmware.

## Do not reopen without new evidence

- DMA versus PIO;
- runtime PM as primary cause;
- Linux IRQ mapping;
- DeviceInit `besdenable` as missing sensor I/O;
- GPIO112/GPP_D16 or hidden LPSS switch;
- unchanged normal-CS replay;
- GXFP5187 PMK address assumptions;
- F2 PMK retrieval;
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
