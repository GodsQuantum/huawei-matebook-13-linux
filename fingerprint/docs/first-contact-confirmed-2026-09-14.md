# GXFP51A0 first Linux contact confirmed — 2026-09-14

## Result

A real Goodix GXFP51A0 on a Huawei MateBook 13 2021 now replies under Linux.
This independently reproduces the first-contact discovery published by
[`szlukabence/goodix-fingerprint-spi-linux`](https://github.com/szlukabence/goodix-fingerprint-spi-linux).

The two required conditions are:

```text
GPIO264 LOW while MCU runs
SPI mode 0 + SPI_CS_HIGH (Linux mode bit 0x04)
```

The bounded confirmation used 1 MHz, reset HIGH for 300 ms, then LOW with a
600 ms settle.

## Positive evidence

A8 alone returned the checksum-valid ACK:

```text
a0 06 00 a6 b0 03 00 a8 03 4c
```

NOP -> A8 -> chip-ID traffic followed by a bounded read returned:

```text
a0 1a 00 ba a8 17 00 47 46 5f 53 54 34 31 31 53
45 43 5f 41 50 50 5f 31 34 31 31 35 00
```

which contains:

```text
GF_ST411SEC_APP_14115
```

A repeated positive case returned the same firmware string.

## Controls

The same NOP/A8/chip-ID sequence with normal Linux chip-select polarity and
GPIO264 LOW returned no non-idle protocol bytes.

With `SPI_CS_HIGH` but GPIO264 HIGH, the MCU was held in reset and remained
silent.

Therefore both runtime LOW on GPIO264 and `SPI_CS_HIGH` are required for this
Linux first-contact path on the tested integration.

## Corrections to the previous project boundary

The previous 34-transfer Linux run used normal CS polarity. Its all-`0xff`
result remains a valid historical control but does not imply a dead SPI path.

GPIO264 is not a power-enable line in the previous sense. Hardware evidence now
supports:

```text
HIGH = active MCU reset
LOW  = MCU running
```

The candidate uses the conservative confirmed reset timing:

```text
HIGH 300 ms -> LOW -> settle 600 ms -> final LOW
```

The currently proven Linux SPI rate is 1 MHz. ACPI/Windows advertise 10 MHz,
but increasing the Linux rate is a separate optimization experiment and is not
combined with the first-contact fix.

## Current boundary

First contact is no longer the blocker. The next exact-target stages are:

1. confirm/read chip identity and ChicagoHS target state cleanly;
2. integrate the exact GXFP51A0 sensor configuration;
3. resolve target TLS/PSK semantics without assuming GXFP5187 constants;
4. capture an image;
5. enrol/verify;
6. integrate with fprintd/PAM.

No firmware update is required or authorized by this result.
