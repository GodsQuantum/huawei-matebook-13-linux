# Final handoff — GXFP51A0 / GF3658 Milan — 2026-09-08

This file is the canonical resume point for the fingerprint work completed on
2026-09-08. It intentionally contains only sanitized public research facts.

## Executive status

A real GXFP51A0 candidate is integrated into libfprint `v1.94.100`, compiles
and links in the validation transaction, and its first-contact state machine is
aligned with the reconstructed Windows GF3658/Milan behavior.

It is **not yet a functional fingerprint driver** because Linux still receives
no first sensor-side ACK or A8/EVK response.

Current functional frontier:

```text
libfprint build/integration      PASS
Windows first-contact model     reconstructed
Linux first-contact model       aligned
SPI controller submissions      proven
sensor-side ACK                 NOT OBSERVED
A8 / EVK                        NOT OBSERVED
target config                   unresolved/gated
DSM/TLS/PSK semantics           unresolved/gated
image/enroll/verify             not yet reachable
fprintd/PAM                     not yet reachable
```

## Exact Windows binaries

```text
Goodix 1.1.141.36 gfspi.dll
SHA-256 4fc5956220cc7bd86d002437e9cae5508d724763a430e4994ba7ce64144a6d59

Goodix 1.1.141.40 gfspi.dll
SHA-256 36033fbf507620776d9fb686ecfe7847ff41fcbdee6e2afad119e28c6f81ca04
```

Reliable differential method: PE x64 `.pdata` / `RUNTIME_FUNCTION` boundaries,
bounded radare2 disassembly, semantic ABI/dataflow comparison. Do not return to
global `radiff2 -A` or string-only heuristics.

## Exact-target hardware / ACPI contract

Confirmed:

- ACPI HID `GXFP51A0`;
- GF3658 / Milan family;
- active parent `SPI1`; SPI2 fingerprint child disabled;
- SPI1 CS0;
- SPI mode 0;
- 8 bits;
- 10 MHz;
- four-wire;
- GPIO48 is level-triggered ActiveHigh readiness/IRQ;
- Linux virtual IRQ is dynamic; hardware IRQ 48 is the stable target fact;
- GPIO264 reset: HIGH 10 ms -> LOW 100 ms -> final LOW;
- GPIO112 / GPP_D16 enable hypothesis is closed and must not be touched;
- LPSS hidden fingerprint-switch search is closed.

## First-contact protocol model

### DriverState

Logical Install command:

```text
(9,3) -> packed 0x96
```

Windows-faithful silent path:

```text
NOP
5 ms
up to two wrapper calls
one identical Install retry inside each wrapper call
```

Maximum: one NOP + four Install logical frames.

After DriverState exhaustion, Windows performs the reviewed reset fallback and
continues into `init_MCU`; it does not require a second DriverState sequence.

### GetEvkVersion

```text
NOP
5 ms
A8 / A4 request
wait matching ACK
if first ACK wait times out:
    retransmit the identical A8 once
after ACK:
    wait response phase separately
```

Outer common-init:

```text
3 GetEvkVersion attempts
-> reviewed hard reset
-> 1 final GetEvkVersion
```

### Fully silent transfer count

```text
DriverState                              10 physical transfers
3 initial EVK attempts                   18
1 final EVK attempt                       6
total                                    34
```

Previously observed Linux result:

```text
SPI_TRANSFER_COUNT=34
TX_BYTES=180
IRQ_WAIT_COUNT=12
GOODIX_IRQ_EVENTS=0
RETAINED_RX_BYTES=180
RX_FF_BYTES=180
SPI controller completions=proven
SPI controller errors=none
final GPIO264=LOW
```

## DeviceInit / BESD closure

The single operation between DriverState and `init_MCU` is not missing sensor
traffic.

```text
1.1.141.36:
  _DeviceInit            0x1800174c8
  callsite               0x1800175c0
  device_action          0x180043258
  case 0x0F              0x180043990
  besdenable             0x1803aba38

1.1.141.40:
  _DeviceInit            0x180017fd8
  callsite               0x1800180d0
  device_action          0x180075b38
  case 0x0F              0x180076308
  besdenable             0x180402518
```

Effective call:

```text
device_action(0x0F, &zero, 4)
```

Selected case behavior:

```text
besdenable = 0
logging only
```

BESD xref audit:

```text
.36 xrefs=3
.40 xrefs=3
pre-ACK reachable external consumers=0
```

The previous `SENSOR_IO` label was a whole-dispatcher false positive.

## SPB / Linux transport closure

GXFP51A0 runtime internal IDs:

```text
.36 HardwareID=5
.40 HardwareID=3
```

Both select the split Milan transfer:

```text
4-byte outer header
simple SPB write
~2 ms
remaining bytes
simple SPB write
```

`SpbPeripheralExecuteSequence` exists but is not used for this target
first-contact write.

Linux candidate:

```text
SPI_IOC_MESSAGE(1) for outer 4 bytes
~2 ms
SPI_IOC_MESSAGE(1) for remainder
```

Classification:

```text
FIRST_CONTACT_SPB_WRITE=MAT​CHED_HIGH_CONFIDENCE
```

(The zero-width character in the display token above is intentional only to
avoid tooling that interprets status tokens; semantically read it as
`MATCHED_HIGH_CONFIDENCE`.)

## Candidate source

Canonical directory:

```text
fingerprint/driver/goodix51a0/
```

Important target gates:

- GXFP5187 RAM PSK access remains disabled;
- GXFP5187 config/TLS activation remains blocked;
- `GOODIX_PSK_LEN=48` is inherited precedent, not a proven GXFP51A0 fact;
- no target config is promoted without exact same-device evidence;
- firmware update paths are not authorized.

The candidate now corrects four former fidelity defects:

1. removes unconditional initial reset before DriverState;
2. restores DriverState NOP + 5 ms;
3. performs fallback reset then continues without replaying DriverState;
4. restores one same-attempt exact A8 retransmission.

Regression test:

```text
python3 tests/test-goodix51a0-first-contact.py
```

Research suite:

```text
make -C fingerprint/research test
```

CI runs the first-contact source regression in addition to the existing
repository quality checks.

## Build validation

Validation target:

```text
libfprint v1.94.100
drivers=goodix51a0
introspection=false
doc=false
installed-tests=false
```

The transaction that commits this handoff is designed to abort and roll back
unless:

- BESD closure passes for both reviewed Windows DLLs;
- first-contact regression passes;
- the entire `fingerprint/research` test suite passes;
- libfprint Meson setup succeeds;
- Ninja compiles and links the GXFP51A0 candidate;
- target safety gates remain blocked;
- privacy scan passes;
- `git diff --check` and staged `git diff --check` pass;
- the pushed remote SHA equals the local committed SHA.

## Closed hypotheses — do not repeat unchanged

Closed or rejected as primary explanation:

- DMA versus deterministic PIO;
- runtime PM;
- Linux native IRQ mapping;
- userspace GPIO polling versus native IRQ wait;
- mode-5 split timing;
- first-contact split SPB transaction/CS boundary;
- reviewed reset permutations;
- same-wire MISO retention;
- GPIO112 / GPP_D16 enable;
- hidden LPSS fingerprint switch;
- `.40`-only `WdfInterruptCreate`;
- `.40` logging helper as wake/bootstrap action;
- DeviceInit intermediate operation as missing sensor I/O;
- fixed 48-byte GXFP51A0 PSK assumption;
- unchanged common-init replay.

## Still unresolved

The following remain genuine blockers:

1. why the target produces no first ACK under Linux;
2. whether CS/SCLK/MOSI electrically reach the Goodix MCU exactly as under
   working Windows;
3. whether MISO and GPIO48 physically respond under working Windows;
4. exact GXFP51A0 `Milan_DlCfg` / target config;
5. exact `_DSM` TLS/PSK material semantics and length;
6. first image acquisition;
7. enroll / verify;
8. fprintd / PAM / desktop integration.

## Highest-value next work

Do **not** begin with another protocol permutation.

Preferred sequence:

1. on a working Windows boot of the same target, obtain the strongest available
   read-only SPB/SpbCx/WDF/WPP/ETW evidence from D0Entry through the first
   successful DriverState/GetEvkVersion;
2. compare physical `CS/SCLK/MOSI/MISO/GPIO48` behavior between Windows and
   Linux using a logic analyzer/oscilloscope if software tracing cannot prove
   the platform transition;
3. if Windows and Linux differ electrically, isolate the exact
   controller/pinctrl/power/ownership difference before any write;
4. only after one exact new same-device prerequisite is identified, perform one
   bounded fresh-boot Linux experiment changing only that prerequisite;
5. after the first real ACK/A8, resolve target config then DSM/TLS, followed by
   image, enroll/verify and fprintd.

## Safety / public-repository rules

Never commit or expose:

- proprietary Windows DLL/CAB/firmware;
- raw `_DSM` payloads;
- PSKs or derived keys;
- local usernames or personal paths;
- private IP addresses;
- boot IDs;
- unrelated personal hardware inventory;
- bulk proprietary disassembly.

Never perform without new exact-target evidence:

- firmware flash/upload/erase;
- PSK writes;
- speculative MMIO/pinmux writes;
- GPIO112/GPP_D16 writes;
- generic borrowed wake commands.

Every active experiment must end with GPIO264 LOW.

## Canonical files to read next

1. `FINAL_HANDOFF_2026-09-08.md` — this file;
2. `docs/current-boundary-2026-09-08.md`;
3. `docs/deviceinit-besd-spb-closure-2026-09-08.md`;
4. `docs/windows-14136-14140-differential-2026-09-08.md`;
5. `driver/goodix51a0/README.md`;
6. `docs/research-log.md`;
7. `PROJECT_HANDOFF.md`.

Functional target remains:

```text
first ACK
-> A8/EVK
-> exact target config
-> exact DSM/TLS/PSK
-> image capture
-> enroll
-> verify
-> fprintd
-> PAM/desktop
```

<!-- contributor-tooling-postscript-2026-09-08 -->

## Postscript: public contributor baseline

After the first-contact fidelity commit, the repository was consolidated so a
new contributor does not need this chat/session to reproduce the software
state.

Canonical first command:

```bash
make -C fingerprint verify
```

This performs software-only regressions, verifies the source manifest and
builds the GXFP51A0 candidate against libfprint `v1.94.100` using pinned
Meson/Ninja versions.

Additional public tools:

```text
fingerprint/scripts/build-libfprint-v1.94.100.sh
fingerprint/scripts/verify-software-baseline.sh
fingerprint/scripts/passive-linux-observability.sh
fingerprint/scripts/windows/gxfp51a0_windows_observability.ps1
```

The current development installation has no Windows boot. Windows observability
is therefore an external-contributor path, not a locally executed result.

See `HANDOFF_CURRENT.md` for the shortest resume point.
