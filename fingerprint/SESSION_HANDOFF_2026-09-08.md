# Session handoff — 2026-09-08

Canonical state:
[`docs/current-boundary-2026-09-08.md`](docs/current-boundary-2026-09-08.md).

## One-line state

A **real GXFP51A0 libfprint 1.94.100 candidate now compiles and links
successfully**, but the sensor is still not communicative under Linux.
The driver is build-complete, **not functionally complete**.

## Build closure

```text
MESON_CONFIGURE=PASS
UPSTREAM_LIBFPRINT_BUILD=PASS
COMPILE_ERROR_GROUPS=0
GOODIX51A0_OBJECT_COMPILED=YES
GOODIX51A0_TYPE_SYMBOL_IN_DRIVER_ARCHIVE=YES
GOODIX51A0_STRING_IN_SHARED_LIBRARY=YES
SOFTWARE_BUILD_READY=YES
```

The reviewed IRQ helper also builds for the tested CachyOS kernel with
`LLVM=1`. Earlier GCC failures were toolchain mismatch, not module defects.

Canonical libfprint metadata:

```meson
'goodix51a0': { 'spi': true, 'helper': ['udev', 'openssl'], 'optional': true },
```

Exact buildable source is preserved under `driver/goodix51a0/`.

## Static closure

Exact ST411 vector:

```text
SP            0x20020000
Reset_Handler 0x08033198
base          0x08020000
```

Exact Goodix FP 1.1.141.36 `gfspi.dll` SHA-256:

```text
4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59
```

The r2ghidra pass resolves the outer `_DSM` result envelope:

- capacity 0x1000;
- first returned DWORD byte-swapped;
- low 16-bit becomes variable payload length;
- payload copied from offset +4;
- length <= 4 rejected.

A fixed 48-byte GXFP51A0 PSK is **not proven**. `GOODIX_PSK_LEN=48` in the
candidate is inherited from the GXFP5187 precedent and remains safely gated.

No unique same-device `Milan_DlCfg` sequence was recovered.

## Do not regress

Already exhausted:

- 34-transfer common-init;
- 180/180 retained RX bytes = `0xFF`;
- 0 Goodix IRQ;
- controller completion proven;
- DMA vs PIO closed;
- runtime-PM closed;
- native IRQ mapping closed;
- mode-5 split write/CS closed;
- reviewed resets complete, final GPIO264 LOW.

Do not rerun the same common-init merely because it now exists in libfprint.

## Next evidence

Highest-value missing evidence is a **working Windows SpbCx/WDF/WPP/ETW trace**
on this same GXFP51A0, ideally D0Entry through the first successful
DriverState/GetEvkVersion.

If that cannot expose the missing transition, compare
CS/SCLK/MOSI/MISO/IRQ electrically under Windows vs Linux.

Only then authorize one new fresh-boot Linux experiment based on one precise
same-device action.

## Privacy / safety

Never commit raw `_DSM`, PSKs, derived keys, vendor binaries/firmware, private
paths/IPs/boot IDs or proprietary full disassembly.

No firmware writes, PSK writes, speculative MMIO/pinmux, generic wake guesses
or sibling force-binding.
