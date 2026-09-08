# Contributing to the GXFP51A0 fingerprint research

Start with the canonical software baseline:

```bash
make -C fingerprint verify
```

A contribution that changes the candidate driver, integration patch or
first-contact model should not be proposed unless this command passes.

## Evidence labels

Label technical claims explicitly:

- **CONFIRMED** — directly supported by exact-device static or measured evidence.
- **INFERRED** — strongly supported but not directly measured on the target.
- **HYPOTHESIS** — a testable possibility that is not yet established.

Include exact reproduction context, expected/actual result and concise logs.

## Safe contributor commands

```bash
make -C fingerprint verify
make -C fingerprint build
make -C fingerprint research
make -C fingerprint passive-audit
```

`verify`, `build` and `research` are software-only. `passive-audit` performs
read-only Linux platform observation.

Historical active probes under `research/` are preserved for auditability, not
as default contributor commands. Closed experiments must not be replayed
unchanged.

## Useful external contribution

The current development installation has no Windows boot. A contributor with a
working GXFP51A0 Windows installation can use:

```text
fingerprint/scripts/windows/gxfp51a0_windows_observability.ps1
```

A contributor with access to a logic analyzer/oscilloscope can also provide
Windows-vs-Linux CS/SCLK/MOSI/MISO/GPIO48 evidence.

## Privacy and proprietary material

Never commit or attach:

- proprietary CAB/DLL/firmware;
- raw ACPI `_DSM` payloads;
- PSKs or derived keys;
- serial numbers;
- local usernames or personal filesystem paths;
- private IP addresses;
- boot IDs;
- unrelated personal hardware inventory;
- bulk proprietary disassembly.

Use hashes and the smallest necessary sanitized excerpts instead.

## Safety

Follow [docs/safety.md](docs/safety.md).

Do not introduce:

- firmware flash/upload/erase;
- PSK writes;
- speculative MMIO/pinmux writes;
- GPIO112/GPP_D16 writes;
- generic borrowed wake commands;
- forced sibling-driver binding;
- hardcoded Linux virtual IRQs.

Any future hardware-active experiment requires a new exact-device hypothesis,
bounded writes, explicit stop conditions and final GPIO264 LOW restoration.

## Documentation

Keep `README.md` and `README.FR.md` semantically synchronized. Update
[HANDOFF_CURRENT.md](HANDOFF_CURRENT.md) whenever the current boundary changes.
