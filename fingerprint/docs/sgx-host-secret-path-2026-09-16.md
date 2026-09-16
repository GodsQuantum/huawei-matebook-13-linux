# GXFP51A0 host-secret / SGX path — 2026-09-16

This document records the current non-secret interoperability boundary for the
GXFP51A0 / GF3658 Milan driver. It intentionally excludes raw ACPI material,
sealed data, PMK/PSK bytes, proprietary enclave binaries and bulk vendor
disassembly.

## Status summary

The sensor-side initialization path is no longer the blocker:

- Linux first contact is confirmed with mode 0 + `SPI_CS_HIGH` at 1 MHz;
- target firmware identifies as `GF_ST411SEC_APP_14115`;
- chip ID `0x2504`, OTP parsing and OTP-derived calibration are confirmed;
- the exact target configuration path is accepted by the sensor;
- target TLS is TLS 1.2 / `PSK-AES128-GCM-SHA256` (`0x00A8`), host server and
  sensor client.

The Windows compatibility route still leads through a type-13 / 48-byte host
secret. For a Linux-only driver this is no longer assumed to be mandatory:
current same-die Goodix work supports provisioning a Linux-owned 32-byte TLS PSK
directly to the sensor. See `fast-track-assessment-2026-09-16.md`.

## F2 PMK route is closed

The Milan F2 command can address target memory, including RAM on the 14115
family. New same-firmware evidence corrects the earlier claim that its readable
domain was limited to application flash.

The reason F2 is not a practical route to the existing Windows PMK is timing:
the firmware decrypts the protected flash blob during boot, stages the plaintext
briefly, then reuses that RAM before the normal command loop is available. A
later F2 read therefore does not recover the boot-time plaintext PMK.

Some F2 tooling also sees an 8-byte echo of the request (`addr32 + len32`) before
returned memory. Future diagnostic readers must validate the complete response
shape and a known target vector before trusting a dump. The historical Pegasus
vector read at `0x08020000` matched the known firmware vector exactly, so that
successful calibration is retained; the old "F2 cannot read SRAM" conclusion is
not.

Do not resume untimed F2 PMK hunting or GXFP5187 RAM-address assumptions without
new exact-target evidence.

## Windows host-secret path

Evidence from the matching Windows stack shows a different architecture: a
machine-specific ACPI `_DSM` payload is passed through a signed Intel SGX
enclave and unsealed there. The successful Goodix record has semantic type
`13` and payload length `48` bytes.

The public repository must never contain the machine-specific `_DSM` payload,
the resulting PMK, sealing material, private keys, proprietary enclave binary
or raw proprietary disassembly.

## Legacy SGX compatibility

The target CPU exposes SGX but not flexible Launch Control. The ordinary current
Linux SGX device path therefore cannot be used as-is for this legacy Windows
SGX enclave.

A controlled compatibility path has been validated:

1. a one-shot boot masks native-kernel SGX ownership while raw CPUID SGX stays
   visible;
2. a Linux-7.2-compatible legacy `isgx` module loads and exposes `/dev/isgx`;
3. the EPC is discovered by the legacy driver;
4. the Intel production Launch Enclave reaches EINIT through the legacy path;
5. the temporary one-shot boot entry is consumed and cleaned automatically.

This proves the hardware path through EPC allocation and Launch Enclave EINIT.
It does not yet prove Goodix WBDI EINIT.

## Goodix WBDI enclave format

The matching Goodix enclave is a PE32+ x86-64 SGX image. Non-secret structural
facts established by the strict local parser are:

- no PE import directory;
- exported enclave entry point;
- Intel trusted-runtime family `2.7.101.2`;
- legacy SGX metadata version `1.2`;
- `sgxmeta` VirtualSize `0x754`, PE RawSize `0x800`;
- a `0x44`-byte legacy prefix followed by a standard `0x710`-byte SIGSTRUCT;
- zero PE file-alignment padding after the virtual metadata;
- 8 threads, SSA frame size 1, TCS NSSA 2;
- 1 MiB stack and 4 MiB heap geometry.

The private/offline loader now has a strict PE32+ parser, legacy
metadata/SIGSTRUCT parser, malformed-input tests, SHA-256 helper and an exact
structure gate against the locally owned target image. The complete unit suite
and ASan/UBSan suite pass.

## Windows uRTS page-loader evidence

The matching Windows SGX runtime identifies the enclave creator implementation
as the Microsoft/Windows backend from the Intel SGX 2.7 generation. Comparison
with the public Intel Linux 2.7 interface maps its methods to create, add-page,
init and destroy operations.

The add-page path was traced to `enclave_load_data()` and submits exactly one
4 KiB page per call. The initialization path consumes a standard `0x710`-byte
SIGSTRUCT. This gives a concrete page-loading oracle without publishing vendor
code or relying on heuristic string matches.

## WBDI fallback gate: exact MRENCLAVE reproduction

If the SGX fallback is resumed, no Goodix enclave execution is attempted until the Linux loader independently
reconstructs the exact page stream authenticated by the enclave SIGSTRUCT.
Current work is therefore:

1. recover the exact Windows SGX 2.7 PE page-materialization rules;
2. reproduce ECREATE parameters;
3. reproduce every 4 KiB EADD/EEXTEND page, permissions and ordering;
4. materialize TCS/SSA/stack/heap exactly as the Windows loader does;
5. recompute MRENCLAVE offline;
6. require a byte-for-byte match with the signed SIGSTRUCT measurement.

Only after this fallback gate passes would work proceed to Goodix WBDI EINIT,
launch-token handling and the minimum ECALL/OCALL bridge needed for unsealing.
This is no longer the blocking dependency for the Linux-only driver.

## Preferred Linux integration

The preferred path is now the APP-mode PSK fast track documented separately:
read-only preset-PSK compatibility probe, exact-target validation of the same-die
white-box/provisioning contract, Linux-owned 32-byte PSK, then the existing TLS
1.2 PSK-GCM path and the tested ChicagoHS capture/matcher stack. WBDI/SGX stays
as a fallback and Windows-compatibility research path.

## Safety / closed branches

Do not resume these without new exact-target evidence:

- F2 PMK retrieval;
- GXFP5187 PMK-address assumptions;
- GPIO112 / GPP_D16 experiments;
- speculative MMIO or pinmux writes;
- sensor firmware flashing or modification;
- WinPE/QEMU as a primary path while the native SGX route remains viable.

Any future active sensor experiment must leave GPIO264 LOW on exit.
