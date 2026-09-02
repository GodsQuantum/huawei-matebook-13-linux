# Safety policy

This policy is mandatory for GXFP51A0 / GF3658 Milan research.

## Absolute prohibitions

Do not perform firmware flashing or UPFW, firmware erase, bootloader programming, vendor firmware-management flows, unmodified OpenGoodixSPI full-device procedures, unmodified `goodix-fp-dump` full-device procedures, or unrelated USB `27c6:5110` / `5117` firmware procedures.

Windows firmware-management paths may be documented statically but are not instructions to reproduce them.

Do not make speculative pinmux writes or force platform/runtime-PM state without a reviewed same-device reason.

## RX invariants

- Wait for readiness before reading.
- Read exactly four outer-header bytes.
- Validate the header and announced body length.
- Read exactly the announced body.
- Stop immediately on `FF FF FF FF`.
- Never add a speculative second read.
- Fail closed on malformed, oversized or ambiguous frames.

## GPIO invariants

GPIO48 is treated as a level-oriented ActiveHigh readiness input. Do not reconfigure its trigger mode or firmware-locked pinmux.

GPIO264 is reset/control. The proven restoration sequence is:

```text
HIGH 10 ms
LOW 100 ms
final LOW
```

## Active-experiment policy

Every hardware experiment must define one hypothesis, minimum required writes, expected readiness/RX behavior, a bounded timeout, an explicit stop condition, cleanup behavior and independent recovery behavior.

Do not add opportunistic protocol commands after the experiment starts.

## Supervisor requirements

A live probe must run only through the independent supervisor, never by invoking the probe binary directly.

Required invariants:

- explicit reviewed-probe token;
- device initially unbound;
- empty `driver_override`;
- supervisor-owned temporary spidev binding;
- 20-second wall-clock timeout for the corrected common-init research harness; any change requires a new reviewed probe design;
- terminate the probe process group on failure/timeout;
- internal cleanup accepted only when final GPIO264 LOW is confirmed;
- GPIO264-only external restore if internal cleanup cannot be confirmed;
- unconditional spidev unbind / override cleanup;
- restoration of original spidev module state;
- no automatic retry of the complete hardware experiment.

## Current hardware gate

Probe #3 has already been executed. Do not rerun Probe #3.

Probe #4 has also been executed once under the reviewed native-IRQ design. It produced:

```text
SPI_TRANSFER_COUNT=16
IRQ_WAIT_COUNT=6
IRQ_EVENT_COUNT=0
SPI reads=0
DRIVERSTATE_RESULT=ACK_TIMEOUT
cleanup=successful
```

Do not rerun Probe #4.

The native IRQ result rejects the userspace-polling hypothesis. No new Goodix protocol command is currently authorized.

Probe #5 tracing attempts did not reach new sensor protocol traffic and are not hardware evidence. Ftrace is currently deprioritized.

Before any new active probe, first close the static GF3658 transport-mode / final-SPB-helper questions or establish another single discriminating variable. If software transaction boundaries remain correct, prefer physical SPI observability over another speculative protocol sequence.

## ACPI `_DSM` / PSK privacy

The Goodix `_DSM` function 1 returns a 2048-byte machine-specific buffer used by the Windows stack as a PSK source.

Never commit or publish the raw `_DSM` buffer, PSKs or derived authentication material, or dumps containing such data.

## Repository privacy

Never commit local usernames, personal filesystem paths, private machine nicknames, boot IDs, local IP addresses, unrelated hardware serials, proprietary Windows binaries, raw generated disassembly or unredacted local diagnostics.

<!-- pio-gate-safety-2026-09-02 -->
## PIO experiment safety

A PIO comparison is authorized only when the dedicated preflight proves the
controller entered the kernel's native PIO fallback before any sensor traffic.

Do not dynamically remove IDMA64 or rebind the PXA2xx controller immediately
before a fingerprint probe merely to force the desired state.

Use a fresh boot with IDMA64 blocked from loading, prove native PIO, then run
the unchanged bounded fingerprint probe once.

A failed PIO preflight consumes no active fingerprint probe. Once the active
PIO supervisor starts sensor traffic, that boot is consumed.
