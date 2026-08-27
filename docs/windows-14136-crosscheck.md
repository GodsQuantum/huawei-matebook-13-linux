# Goodix FP 1.1.141.36 cross-check

This document records only reproducible static-analysis findings. Proprietary binaries,
installers, firmware, ETL files, and raw disassembly are not stored in this repository.

## Package identity

- Package: Goodix FP `1.1.141.36`
- Package SHA-256: `74052a274239e17ac8fa95314e22d8db1770a3b9df28c90c9a9178231418f435`
- `gfspi.dll` SHA-256: `4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59`
- INF version: `11/30/2020,1.1.141.36`
- INF hardware IDs: `ACPI\GXFP51A7`, `ACPI\GXFP51A0`
- Internal build path identifies `Milan_Watt/MilanSpi/.../Release_GF3658`
- Firmware strings include `GF_ST411SEC_APP_14114`
- TLS strings include `Client_identity`, `TLS-PSK-WITH-AES-128-GCM-SHA256`, and `TLS-PSK-WITH-AES-128-CBC-SHA256`

## Why this package matters

The package independently predates the 1.1.141.40 reference by years while targeting
the same GXFP51A0/GXFP51A7 Milan/GF3658 family. Matching behavior across these builds
is stronger evidence than a single-binary interpretation.

## `GetEvkVersion` payload behavior

**CONFIRMED by static analysis:** the 1.1.141.36 `GetEvkVersion` call site sends
OTHER A/4 with `payload_len=2`, but the visible function does not initialize the two
stack bytes passed as payload. This matches the 1.1.141.40 finding.

**Consequence:** there is no evidence for a mandatory fixed two-byte vendor constant.
The Linux `00 00` fixture remains deterministic test data, not a recovered Windows value.

## ACK and response state machine

**CONFIRMED by static analysis:** positive ACK timeouts below 1000 ms are clamped to
1000 ms; ACK polling occurs in approximately 15 ms slices. A first ACK timeout causes
exactly one retransmission of the same command; a second timeout fails the send.
Response waiting is a distinct phase and uses logical event 9 for `GetEvkVersion`.

## RX classification

For an outer A frame, the Windows parser treats the first body byte as the packed
command and the next two bytes as the little-endian inner length. It derives:

```text
cmd0 = packed >> 4
cmd1 = (packed & 0x0e) >> 1
```

For the GetEvkVersion path:

```text
cmd0=B, cmd1=0
    -> message/ACK handler
    -> payload[0] identifies the packed command being acknowledged
    -> payload[0] == A8 means ACK for OTHER A/4

cmd0=A, cmd1=4
    -> OTHER response dispatcher
    -> clears the 64-byte EVK response buffer
    -> copies response payload
    -> signals logical event 9
```

ACK and response are therefore separate logical frames, not two guaranteed GPIO edges.
They can be processed consecutively while a level-triggered IRQ remains asserted.

## Firmware/version correlation

A public report for another Huawei laptop exposing the exact `GXFP51A0` HID extracted
`GF_ST411SEC_APP_14115` from a Windows ETL trace. The 1.1.141.36 binary carries
`GF_ST411SEC_APP_14114`. This is evidence of a closely related ST411SEC/Milan firmware
line, but it does not prove identical firmware or justify copying firmware procedures.

## Safety boundary

No executable from the package was run during this analysis. No firmware operation is
inferred or recommended. The binary is used only as static interoperability evidence.
