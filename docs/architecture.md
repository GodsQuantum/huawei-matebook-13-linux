# Architecture

```text
ACPI GXFP51A0 discovery and ownership
    -> temporary minimal SPI/libgpiod research transport
    -> validated Milan transport and state machine
    -> libfprint device integration
    -> fprintd
    -> KDE/GNOME/PAM login and sudo
```

Userspace GPIO/SPI is a controlled reverse-engineering phase, not necessarily the upstream endpoint. It may begin only after the static fallback questions are answered and committed. Use narrow transport/protocol interfaces, bounded exact-length I/O, explicit state transitions, cancellation, and timeouts. No layer may expose a firmware-management API.

The temporary transport must demonstrate reliable IRQ/read behavior before the validated Milan state-machine gate. libfprint then precedes fprintd and desktop/PAM use. Cross-distribution packaging waits for reliable enroll/verify behavior.

[`berkekbgz/libfprint-goodix-spi`](https://github.com/berkekbgz/libfprint-goodix-spi) is the transport precedent. [`buxel/libfprint-27c6-5110`](https://github.com/buxel/libfprint-27c6-5110) applies only to higher GF3658 image/matcher/TLS layers, never its USB firmware workflow.

## Current research implementation

`research/` contains restricted NOP/A4 packet builders, a one-attempt
`GetEvkVersion` state machine tested against a simulated backend, spidev
discovery/configuration primitives, exact-length one-message SPI primitives,
and level-oriented IRQ wait logic tested off-hardware. The A/4 payload is
mandatory caller input; no value is invented.

The target laptop has completed the passive spidev/libgpiod preflight with zero SPI transfers.
The real libgpiod adapter is intentionally narrower than the future active backend:
its passive gate requests GPIO48 as an input and reads the current level only.
It does not arm edge detection, expose GPIO264, perform reset, run the full
common-init fallback, or expose firmware-management operations.

The next gate is an off-hardware exact-length IRQ/RX drain adapter that composes
level-oriented IRQ waiting, four-byte header reads, exact body reads, B/0 ACK(A8)
classification, A/4 response classification, timeout/retransmission behavior, and
cancellation. Only after that model is fully tested and reviewed may a single active
`GetEvkVersion` experiment be designed.
