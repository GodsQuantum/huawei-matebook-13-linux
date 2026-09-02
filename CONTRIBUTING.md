# Contributing

Thanks for helping make the Huawei MateBook 13 a better Linux laptop.

This repository has two distinct technical areas:

- **GPU & power management** — reproducible user-facing fixes for Intel + NVIDIA MX250 systems.
- **Fingerprint research** — experimental reverse-engineering of the Goodix GXFP51A0 / GF3658 Milan sensor.

Keep contributions scoped to one area whenever possible.

## Before opening an issue or pull request

Provide only the system information needed to reproduce the result:

- MateBook 13 model/revision if known;
- distro and kernel;
- desktop environment and Wayland/X11 session;
- relevant PCI or ACPI hardware IDs;
- exact commands or script version;
- expected result and actual result;
- concise logs that have been reviewed for private data.

Never publish serial numbers, machine UUIDs, account/user names, home-directory paths, hostnames, LAN/public IP addresses, credentials, API keys, private keys, raw Goodix `_DSM` payloads, PSKs, proprietary firmware/binaries, or raw disassembly.

## GPU & power contributions

The supported reference target is an Intel + NVIDIA GeForce MX250 (`10de:1d13`) MateBook 13 using the proprietary NVIDIA R580 legacy branch.

For changes to `gpu-power/`:

1. preserve the **full Integrated idle** invariant — when no managed workload exists, the MX250 must be removable from PCI and no NVIDIA module/process may be left active;
2. fail closed when the compositor unexpectedly opens the hot-added NVIDIA GPU;
3. do not silently enable third-party package repositories;
4. preserve existing Desktop `Exec=` arguments and Steam Launch Options;
5. keep install/uninstall paths reversible;
6. keep English and French user-facing documentation semantically synchronized.

Before submitting:

```bash
bash -n gpu-power/huawei-matebook-13-gpu-manager.sh
shellcheck gpu-power/huawei-matebook-13-gpu-manager.sh
```

When hardware testing is involved, state whether the test returned to an idle state with the dGPU absent after the last workload exited.

## Fingerprint research contributions

The original Goodix project is preserved under [`fingerprint/`](fingerprint/).

Technical claims must be labelled **CONFIRMED**, **INFERRED**, or **HYPOTHESIS**. Include machine/kernel context, exact reproduction or static-analysis provenance, expected and actual results, and concise reproducible logs.

Follow [`fingerprint/docs/safety.md`](fingerprint/docs/safety.md). In particular:

- do not flash/upload/erase firmware;
- do not add speculative MMIO, pinmux or power writes;
- do not hardcode machine-specific Linux virtual IRQ values;
- do not publish raw ACPI/DSM machine-unique security material;
- do not reintroduce unrelated OpenGoodixSPI or USB firmware procedures.

## Pull requests

Prefer focused commits and a pull request that explains:

- what problem is being solved;
- hardware/software scope;
- tests performed;
- rollback or safety implications;
- whether documentation needs an EN/FR update.

Use the pull-request template and do not mark a hardware result as generally supported from a single unreviewed test.

## License

Contributions are accepted under the repository's GPL-2.0-only license.
