# Project handoff — GXFP51A0 / GF3658 Milan Linux driver research

## Canonical current state

Read first:

- [State of research — 2026-08-31](docs/state-of-research-2026-08-31.md)
- [Hardware evidence](docs/hardware.md)
- [Protocol evidence](docs/protocol.md)
- [Safety policy](docs/safety.md)
- [Research log](docs/research-log.md)

There is no working Linux fingerprint driver yet.

The intended end state remains:

```text
validated Milan transport
-> libfprint
-> fprintd
-> desktop/PAM integration
```

## Strongest confirmed facts

- Goodix `GXFP51A0`, GF3658 / Milan family.
- ACPI `\_SB.PCI0.SPI1.SPBA`.
- SPI1 CS0, mode 0, 8-bit, 10 MHz, four-wire.
- GPIO48 is level-triggered ActiveHigh readiness/IRQ.
- GPIO264 reset is HIGH 10 ms -> LOW 100 ms -> final LOW.
- Milan writes use separate outer/inner SPI transactions with a 2 ms gap.
- DriverState:Install is logical `(9,3)`, packed `0x96`.
- B/0 `payload[0]` identifies the command being acknowledged.
- A silent DriverState path can submit at most four Install packets before its conditional hard reset.
- `GetEvkVersion` is NOP -> 5 ms -> A/4, with one exact A/4 retransmission after first ACK timeout and a separate response-event phase after ACK.
- Linux A/4 `00 00` is only a deterministic fixture.

## Latest active result

Probe #3 was executed on a fresh boot with no unconditional initial reset.

Result:

```text
DriverState: ACK timeout
conditional DriverState reset: performed
GPIO48: remained LOW
SPI reads: zero
GetEvkVersion: ACK timeout
total physical SPI transactions: 16
cleanup: successful
temporary spidev state: restored
```

This rejects the hypothesis that the previous silence was caused solely by the pre-DriverState reset.

Do not rerun probe #3.

## ACPI / DSM

SPBA `_INI` uses Intel `HOSTSW_OWN` setup through `SHPO`; it is not a Goodix wake command.

The Goodix-specific `_DSM` UUID is:

```text
cc58b68a-4479-4893-a8bb-961209db59e5
```

Function 1 returns a 2048-byte `HWFP/FPDT` buffer. A minimal read-only Linux evaluator successfully retrieved it.

Windows static analysis identifies this DSM data as a PSK source. The raw buffer is private per-machine material and must never be committed.

## Windows startup order

The current static model is:

```text
MilanEvtDeviceD0Entry
  -> _StartInitThread
      -> create thread(entry = InitThread)
          -> _DeviceInit
              -> send_driver_install_to_MCU
                  -> SetDriverState(9,3 / 0x96)
              -> intermediate operation
              -> init_MCU
                  -> GetEvkVersionWithRetry
          -> later SGX/TLS/PSK/FDT work
```

Consequences:

1. DriverState genuinely precedes `GetEvkVersion`.
2. The ACPI PSK/TLS branch is not the prerequisite for the first DriverState send.
3. A named Windows `WakeupMCU` exists but is not currently placed on this first startup path.
4. Do not prepend unrelated generic Goodix wake commands.

## Exact next boundary

Do not define probe #4 from guesswork.

Continue statically with:

1. `MilanEvtDevicePrepareHardware`;
2. Windows SPI target/controller creation and configuration;
3. Windows interrupt/readiness registration;
4. the intermediate `_DeviceInit` operation between DriverState and `init_MCU`;
5. any platform/controller state established before `_StartInitThread`.

Only after one missing variable is proven should probe #4 be designed.

## Privacy rules

Never commit:

- local usernames or filesystem paths;
- private machine nicknames or boot IDs;
- IP addresses or unrelated inventory;
- raw `_DSM` payloads or PSKs;
- proprietary Windows binaries or firmware;
- raw generated disassembly.

Only sanitized, generic research facts belong in the public repository.

## Safety

No firmware flashing, UPFW, erase, bootloader or firmware-management procedure is authorized.

Any future active probe must use the independent supervisor, exact-length RX, one reviewed hypothesis, bounded writes and unconditional final GPIO264 LOW restoration.
