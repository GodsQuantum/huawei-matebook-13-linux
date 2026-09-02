# Cross-machine GXFP51A0 / Milan research

The purpose of this page is to track nearby hardware that can improve static protocol
understanding without assuming that two machines have identical firmware.

## Exact GXFP51A0 reports

### Huawei MateBook 14 2020

OpenGoodixSPI issue #6 reports `ACPI\GXFP51A0` on a Huawei MateBook 14 2020. A later
comment for another `GXFP51A0` Huawei system reports Windows ETL firmware string
`GF_ST411SEC_APP_14115` and the same ACPI/SPI modalias family.

Source: https://github.com/PeshalaDilshan/OpenGoodixSPI/issues/6

### Huawei/Honor systems using the 1.1.141.x branch

Public driver inventories show the Goodix SPI 1.1.141.x branch deployed on multiple
Huawei/Honor systems exposing GXFP51A0. These inventories are secondary evidence and
should be used to locate binaries or compare versions, not as protocol proof.

## Closest static sibling: GXFP51A7

The Goodix FP 1.1.141.36 INF explicitly binds both:

```text
ACPI\GXFP51A7
ACPI\GXFP51A0
```

This makes GXFP51A7 a high-priority static sibling when looking for packet/state-machine
behavior shared with GXFP51A0.

## Related Milan design: GXFP51B7

A public reverse-engineering report for the MateBook X Pro 2020 GXFP51B7 documents a
Milan command/framing family, but that machine uses an EC/MMIO mailbox rather than direct
host SPI. Its upper protocol can be useful as corroboration; its transport must not be
copied onto GXFP51A0.

Source: https://github.com/PeshalaDilshan/OpenGoodixSPI/issues/16

## Working Linux precedent: GDIX51C0

`berkekbgz/libfprint-goodix-spi` is a useful architectural precedent for a Huawei Goodix
SPI fingerprint device using userspace SPI/GPIO during reverse engineering and libfprint
integration later. It is not proof that the GXFP51A0 protocol is identical.

Source: https://github.com/berkekbgz/libfprint-goodix-spi

## Research rule

Priority order for external comparison:

```text
exact GXFP51A0 on other machines
    -> GXFP51A7 from the same 1.1.141.x driver family
    -> other Milan variants such as GXFP51B7 / GDIX51C0
    -> older GXFP5187/GXFP5197 only for historical comparison
```

Never transplant a USB firmware workflow or a different platform transport merely because
the Goodix command family looks similar.
