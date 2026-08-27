# Safety policy

This policy is mandatory. The static fallback gate is complete, but the current
state authorizes only static work and preparation/review of a minimal fallback
experiment. Hardware execution requires that review to be complete first.

## Absolute prohibitions

Do not perform firmware flashing, UPFW, firmware erase, bootloader programming, or any firmware-management procedure. Do not run the current OpenGoodixSPI main, unmodified `goodix-fp-dump`, PopulusYang `full_test` or `ProgramStart`, or USB `27c6:5110`/`5117` firmware procedures. They are rejected procedures, not instructions to follow.

## Required controls

- Use IRQ-driven exact-length reads: four-byte header, validation, then one exactly-sized body read; never over-read or read again after `FF FF FF FF`.
- Kernel code must use DMA-safe allocations: `kmalloc`, `kzalloc`, or `kmemdup`.
- Work static-analysis-first and test one hypothesis with the minimum writes.
- Do not interact with the power button unless explicitly required by an approved hypothesis.
- After every active experiment restore Windows reset: GPIO264 HIGH 10 ms, GPIO264 LOW 100 ms, ending LOW.

## Active-experiment checklist

Record the hypothesis, minimum writes, expected IRQ/read result, stop condition, logging, and final reset restoration (HIGH 10 ms, LOW 100 ms, final state LOW). Stop at the condition; do not add opportunistic commands, firmware operations, or a second read.

## Live-probe harness execution gate

The independent external supervisor/restore gate has passed
off-hardware. A live probe, if run, must be launched only through that
supervisor and never by invoking `gxfp-live-probe` directly.

Required execution invariants:

- explicit reviewed-probe confirmation token;
- target initially unbound with empty `driver_override`;
- supervisor-owned temporary spidev bind/unbind;
- 8-second hard timeout with process-group termination;
- internal cleanup accepted only with both `CLEANUP_RESULT=0` and
  `GPIO264_AFTER=0`;
- otherwise separate GPIO264-only restore after probe termination;
- unconditional unbind/override cleanup and restoration of spidev module
  pre-state;
- exactly one reviewed probe; no automatic retry of the overall experiment.

This protects against ordinary probe crashes, hangs and handled terminal
signals. Power loss or SIGKILL of the supervisor itself remain outside
userspace guarantees.
