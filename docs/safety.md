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

The single-purpose live-probe harness may be committed and compiled while
remaining **not authorized for execution**. Before the first live run, an
independent parent supervisor must be validated off-hardware.

The supervisor must:

- own the temporary spidev bind and clear it afterward;
- impose a hard wall-clock timeout;
- treat the probe's `CLEANUP_RESULT=0` plus `GPIO264_AFTER=0` markers as the
  only normal-cleanup confirmation;
- if those markers are missing, wait until the probe process is terminated,
  then invoke a separate GPIO264-only restore helper;
- restore GPIO264 using HIGH 10 ms -> LOW 100 ms -> final LOW;
- unbind spidev and clear `driver_override` on every exit path;
- contain no Milan packet, SPI transfer, firmware, enrollment or libfprint logic.

This external layer protects against a crash/hang of the probe process. It
cannot guarantee cleanup after system power loss or SIGKILL of the supervisor
itself; userspace cannot make such a guarantee.
