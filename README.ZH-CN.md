# Huawei MateBook 13 Linux 支持

> 面向 Huawei MateBook 13 系列的 Linux 实用说明、修复与逆向工程。
>
> **English: [README.md](README.md)** · **Français : [README.FR.md](README.FR.md)**

在已验证的 Intel + NVIDIA MX250 MateBook 13 上，Linux 日常使用已经很成熟。本仓库主要解决两个仍然影响体验的问题：

1. **GPU 与电源管理**：只在需要时启用 NVIDIA MX250，空闲时让独显真正退出 PCI，以提高电池续航。
2. **指纹识别**：为 Goodix GXFP51A0 / GF3658 ST411 提供实验性的原生 libfprint 驱动。

## 当前状态

| 模块 | 状态 | 本仓库提供 |
| --- | --- | --- |
| **GPU / 电源 — NVIDIA MX250** | **已在参考配置上正常工作** | 完整 Intel-only 空闲、应用级热启用、PRIME Render Offload、自动卸载/PCI remove、Plasma/KWin 隔离、桌面应用与 Steam 管理 |
| **指纹 — Goodix GXFP51A0 / GF3658** | **原生实验驱动已在参考硬件上工作** | libfprint/fprintd/KDE 原生路径、TLS/PMK、80×64 采集、FAST/BRIEF/RANSAC 匹配、20 次 enrollment 与有界验证重试 |

## 已验证的 GPU 配置

- Intel 集成显卡；
- NVIDIA GeForce MX250 / GP108M（PCI `10de:1d13`）；
- KDE Plasma Wayland；
- NVIDIA 专有 **R580** 驱动分支。

NVIDIA 590+ 已停止支持 Pascal，因此 MX250 必须使用 R580 分支。

## 1. GPU 与电源 — 按需 MX250

**从这里开始：** [`gpu-power/`](gpu-power/)

目标不是保持 Hybrid 常驻，而是让机器在空闲时真正回到 Intel：

    完整 Intel-only 空闲
            ↓
    PCI rescan
            ↓
    加载 NVIDIA R580
            ↓
    只为选中的应用 PRIME Render Offload
            ↓
    应用退出
            ↓
    卸载 NVIDIA
            ↓
    PCI remove
            ↓
    再次回到完整 Intel-only

KWin 固定使用 Intel，避免在 MX250 热添加时自动占用 NVIDIA render node。

### 快速开始

    cd gpu-power
    chmod +x huawei-matebook-13-gpu-manager.sh
    ./huawei-matebook-13-gpu-manager.sh --lang zh install

重启后：

    GPU-control
    GPU-control add
    GPU-control steam-all-on
    GPU-control status
    GPU-control doctor
    GPU-control test

`GPU-control` 默认显示不会唤醒独显的只读概览。未列出的应用继续使用 Intel；Steam 客户端本身也保持在 Intel。

完整说明：[`gpu-power/README.ZH-CN.md`](gpu-power/README.ZH-CN.md)

## 2. 指纹 — Goodix GXFP51A0 / GF3658 Milan

**rel20 安装包：** [GitHub release](https://github.com/GodsQuantum/huawei-matebook-13-linux/releases/tag/fingerprint-gxfp51a0-rel20)

Release 包含 Arch/CachyOS 原生包、可移植 Linux 源码 bundle、安装说明以及 SHA-256 校验清单。

**文档/源码：** [`fingerprint/`](fingerprint/)

当前参考目标为 MateBook 13 2021 上的 `GXFP51A0` / GF3658 / ST411。生产路径：

    GXFP51A0
    -> libfprint
    -> fprintd
    -> KDE / GNOME / PAM / CLI

已验证路径包含 TLS/PMK、80×64 主机侧图像、20 次 enrollment、FAST/BRIEF/RANSAC 匹配以及固定、有界的验证重试。驱动不会刷写指纹固件，也不需要专用桌面 UI。

详细安装、安全边界和硬件范围：[`fingerprint/README.ZH-CN.md`](fingerprint/README.ZH-CN.md)

## 硬件范围

Huawei 使用 MateBook 13 名称发布了多个硬件版本。不能假定所有型号都有相同的 NVIDIA GPU、ACPI 或指纹控制器。

GPU 工具要求 MX250 PCI ID `10de:1d13`，默认拒绝不匹配的硬件。指纹项目明确针对 `ACPI\\GXFP51A0` / GF3658 Milan。

## 隐私与安全

这是公开硬件仓库。请不要提交：

- 用户名、个人 home 路径或主机名；
- 设备序列号、机器 UUID；
- 无必要的私有/公网 IP；
- 密码、API token、私钥；
- 原始 Goodix `_DSM` payload、PSK、PMK 或其他设备唯一的指纹安全材料；
- 专有 Windows 二进制、固件镜像或大段原始反汇编；
- 指纹采集图像或 enrollment 模板。

## 贡献

参见 [CONTRIBUTING.md](CONTRIBUTING.md)。报告结果时请区分 **CONFIRMED**、**INFERRED** 和 **HYPOTHESIS**。安全问题参见 [SECURITY.md](SECURITY.md)。

## 许可证

仓库根目录代码为 GPL-2.0-only（见 [LICENSE](LICENSE)）。指纹生产驱动子树按文件 SPDX 标记使用 LGPL-2.1-or-later。
