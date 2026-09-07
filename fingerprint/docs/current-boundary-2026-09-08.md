# GXFP51A0 current boundary — 2026-09-08

This document supersedes `current-boundary-2026-09-07.md` for ongoing work.

## Executive state

The project now has a **real libfprint 1.94.100 buildable GXFP51A0 candidate**,
but it is **not a functional fingerprint driver yet** because communication
with the target MCU/sensor has still not been established under Linux.

Build closure achieved on 2026-09-08:

- the reviewed ACPI IRQ helper compiles when Kbuild uses the same LLVM/Clang
  toolchain as the tested CachyOS kernel (`LLVM=1`);
- the GXFP51A0 driver is registered canonically through libfprint `drivers_info`
  as SPI with `udev` and `openssl` helpers;
- Meson 1.12.0 configures libfprint `v1.94.100`;
- Ninja compiles with zero driver compile errors;
- the GXFP51A0 object is present;
- `fpi_device_goodix51a0_get_type` is present in the driver archive;
- the GXFP51A0 driver string is present in the linked shared library.

Therefore the **software/build integration blocker is closed**.

## Candidate driver architecture

The compiled candidate is preserved under `fingerprint/driver/goodix51a0/`.

It reuses the LGPL high-level TLS/capture/matcher/enroll/verify architecture
from `Sigfrodr/libfprint-goodixtls`, while replacing/gating target-specific
pieces according to GXFP51A0 evidence:

- ACPI HID `GXFP51A0`;
- SPI mode 0, 8-bit, 10 MHz;
- mode-5 write boundary: outer 4 bytes -> ~2 ms -> separate inner write;
- reviewed IRQ bridge `/dev/gxfp_irq_wait`;
- GPIO264 reset HIGH 10 ms -> LOW 100 ms -> final LOW;
- target NOP checksum `0xA5`;
- DriverState install `0x96` retry/fallback policy;
- `GetEvkVersion` (`0xA8`) three tries -> reset -> one final try;
- GXFP5187 RAM-PSK access disabled;
- GXFP5187 config/TLS activation disabled until same-device evidence exists.

The candidate opens in **first-contact mode** only. Compilation is not evidence
of working capture/enrollment.

## Exact ST411 state

Published exact-target ST411 fragments reconstruct a valid Cortex-M vector:

```text
SP               = 0x20020000
Reset_Handler    = 0x08033198
application base = 0x08020000
```

This remains consistent with the STM32F4/ST411 bridge interpretation.

No SPI1/SPI2/RCC literal was recovered from the published fragments. That is
**not evidence of peripheral absence**; the fragments do not cover enough of
the relevant initialization graph.

The earlier model of one contiguous 14115 image embedded in `gfspi.dll` is not
supported; the published extraction is fragmentary/modular.

## Exact Windows r2ghidra pass

Analyzed Goodix FP `1.1.141.36`:

```text
gfspi.dll SHA-256:
4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59
```

radare2/r2ghidra analyzed 1323 functions and successfully decompiled:

- `ProductionReadPSKDataFromBios @ 0x18002415c`;
- `GetHostOriginalPSKData @ 0x180027c80`;
- `GetPSKFromDSMMethod @ 0x180028258`;
- `tlsapp_get_psk_data @ 0x18003bab0`;
- sibling/file-cache path `0x18003c09c`.

### Corrected `_DSM` outer framing

`GetPSKFromDSMMethod` is more resolved than the earlier fixed-48-byte
classifier indicated.

The exact assembly shows:

1. output capacity starts at `0x1000` (4096 bytes);
2. a heap buffer of that capacity is allocated;
3. the vendor ASL helper evaluates `_DSM`;
4. the first returned DWORD is byte-swapped;
5. the low 16 bits of that swapped DWORD become the caller's payload length;
6. exactly that many bytes are copied from returned-buffer offset `+4`;
7. success is rejected when payload length is <= 4.

Equivalent extraction from the original little-endian DWORD:

```text
payload_len = raw_byte[3] | (raw_byte[2] << 8)
payload     = returned_buffer + 4
```

This establishes the **outer DSM result framing**. It does not yet establish the
internal TLS material representation.

Important correction: no target-specific fixed **48-byte** copy was recovered.
The candidate's `GOODIX_PSK_LEN=48` is inherited from GXFP5187 and remains
target-gated; it must not be treated as a GXFP51A0 fact.

`ProductionReadPSKDataFromBios` supplies a 2048-byte destination, calls
`GetPSKFromDSMMethod`, then forwards its variable returned length.
`tlsapp_get_psk_data` likewise forwards the length returned by
`GetHostOriginalPSKData`.

No raw DSM payload, PSK or derived key belongs in this repository.

## Milan_DlCfg / target config

The focused r2ghidra pass recovered no unique `Milan_DlCfg` xref/function and
no same-device configuration sequence safe to promote.

```text
TARGET_CONFIG_SEQUENCE_VALIDATED=NO
```

Do not import GXFP5187 or another Milan model's config blob.

## Current communication boundary

The already-complete Windows-faithful Linux common-init remains:

- 34 physical target SPI transfers;
- 180 TX bytes;
- 12 waits;
- 34 concrete target iDMA completions in the DMA run;
- 0 Goodix IRQ events;
- 180 retained same-wire RX bytes, all `0xFF`;
- no trace loss;
- both reviewed fallback resets complete;
- final GPIO264 LOW.

DMA vs PIO, runtime-PM, Linux IRQ mapping, mode-5 split timing/CS and same-wire
RX have been discriminated already. Reimplementing the same sequence inside
libfprint does not create a new hardware hypothesis.

## Finished vs unfinished

Finished:

- target transport reconstruction;
- Windows common-init control-flow reconstruction;
- Linux controller/DMA/PIO/runtime-PM closure;
- exact IRQ/reset behavior;
- buildable libfprint 1.94.100 GXFP51A0 candidate;
- buildable reviewed IRQ helper;
- downstream TLS/capture/matcher/enroll/verify architecture present but gated;
- outer Windows `_DSM` response framing partially reconstructed.

Not finished:

- first accepted GXFP51A0 command/ACK under Linux;
- first A8/EVK response under Linux;
- exact target-specific config sequence;
- exact target TLS/PSK material semantics/length;
- image capture;
- enroll/verify;
- real fprintd/PAM validation.

## Next high-value evidence

Do **not** repeat the unchanged Linux common-init.

Highest-value evidence:

1. working-Windows **SpbCx/WDF/WPP/ETW trace** on the same GXFP51A0, from
   D0Entry through first successful DriverState/GetEvkVersion traffic;
2. if software tracing does not expose the missing platform transition, compare
   **CS/SCLK/MOSI/MISO/IRQ** electrically between working Windows and Linux;
3. only after identifying one new same-device action, run one bounded
   fresh-boot Linux experiment changing exactly that action;
4. after the first real ACK/A8 response, resolve target config/DSM/TLS and
   enable capture/enroll progressively.

## Safety locks

Still forbidden:

- firmware flash/upload/erase;
- PSK writes;
- speculative MMIO/pinmux writes;
- generic borrowed wake commands;
- sibling force-binding;
- hardcoded Linux virtual IRQ;
- repeating a closed active experiment on a consumed boot.

Every future active experiment must end with GPIO264 LOW.
