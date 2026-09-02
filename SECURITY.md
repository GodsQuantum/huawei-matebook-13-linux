# Security policy

## What belongs in a private security report

Please report privately if you discover a vulnerability in repository code that could reasonably cause privilege escalation, arbitrary command execution, unsafe device manipulation, credential exposure, or destructive hardware behavior.

Do **not** open a public issue containing:

- credentials, API tokens or private keys;
- machine-unique Goodix PSKs or raw `_DSM`/FPDT security payloads;
- device serial numbers or machine UUIDs;
- personal file-system paths, hostnames or private network details;
- proprietary firmware/binaries that you are not permitted to redistribute.

Use GitHub's private vulnerability reporting feature when it is available for this repository. If that feature is unavailable, open a minimal public issue asking the maintainer for a private reporting channel without including the sensitive material itself.

## Hardware-safety boundary

The fingerprint work is experimental reverse-engineering. The repository does not authorize firmware flashing, erase/programming flows, speculative MMIO/pinmux writes, or unrelated vendor firmware procedures. See [`fingerprint/docs/safety.md`](fingerprint/docs/safety.md).

The GPU manager is designed to fail closed when the desktop compositor or an unexpected process owns the NVIDIA device. Do not replace that behavior with forced module removal from a live graphical workload.

## Supported versions

This is a rolling hardware-enablement project rather than a released application with long-term support branches. Security and safety fixes target the current default branch. Historical research documents remain for provenance and should not be interpreted as current operational instructions unless the current README links to them as such.
