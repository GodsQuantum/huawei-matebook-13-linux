# Safety policy

This policy is mandatory for GXFP51A0 / GF3658 Milan research.

## Absolute prohibitions

Do not perform firmware flashing or UPFW, firmware erase, bootloader programming, vendor firmware-management flows, unmodified OpenGoodixSPI full-device procedures, unmodified `goodix-fp-dump` full-device procedures, or unrelated USB `27c6:5110` / `5117` firmware procedures.

Windows firmware-management paths may be documented statically but are not instructions to reproduce them.

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
- **12-second** wall-clock timeout;
- terminate the probe process group;
- TERM followed by KILL-after-2-seconds when required;
- internal cleanup accepted only with `CLEANUP_RESULT=0` and `GPIO264_AFTER=0`;
- GPIO264-only external restore if internal cleanup cannot be confirmed;
- unconditional spidev unbind / override cleanup;
- restoration of original spidev module state;
- no automatic retry of the complete hardware experiment.

## Current hardware gate

Probe #3 has already been executed. Do not rerun probe #3.

Probe #4 is **not authorized yet**. It must not be defined until static evidence identifies exactly one justified missing variable.

## ACPI `_DSM` / PSK privacy

The Goodix `_DSM` function 1 returns a 2048-byte machine-specific buffer used by the Windows stack as a PSK source.

Never commit or publish the raw `_DSM` buffer, PSKs or derived authentication material, or dumps containing such data.

## Repository privacy

Never commit local usernames, personal filesystem paths, private machine nicknames, boot IDs, local IP addresses, unrelated hardware serials, proprietary Windows binaries, raw generated disassembly or unredacted local diagnostics.
