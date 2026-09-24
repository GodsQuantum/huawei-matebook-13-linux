[Reading 167 lines from start (total: 167 lines, 0 remaining)]

# Goodix GXFP51A0 / GF3658 ST411 Linux 驱动

面向 Huawei MateBook 13 2021 系列中 SPI Goodix GXFP51A0 的实验性原生 libfprint 驱动。

> **English: [README.md](README.md)** · **Français : [README.FR.md](README.FR.md)**

## 状态 — 2026-09-24

已验证硬件目标：

- ACPI HID：`GXFP51A0`
- Goodix GF3658 / ST411，chip ID `0x2504`
- 已验证固件：`GF_ST411SEC_APP_14115`
- SPI mode 0 + `SPI_CS_HIGH`，1 MHz
- GPIO48 readiness/IRQ，GPIO264 active-HIGH MCU reset
- TLS 1.2 `PSK-AES128-GCM-SHA256`
- 80×64 有效指纹图像
- 固定 libfprint 基线：`v1.94.100`

生产路径：

```text
GXFP51A0 → libfprint → fprintd → desktop PAM / CLI
```

### 已完成人工冷启动验证：rel40

在 MateBook 13 2021 参考机上，使用原有 enrollment 的真实 cold-boot 图形
登录已经成功。Plasma Login Manager 走的是 `Identify`：第一轮同一手指图像
分数为 `2/3/3`；下一次按压的第一张图像被 quality gate 拒绝，而**同一次
物理按压的第二张图像得到 7/7**，随后成功进入会话。

rel40 因此同时验证了：

- Windows 精确 `WakeupMCU`：原始 SPI `0f 00 00 0e` + 5 ms；
- warm context 硬件重验证与 `WARM_REBASE`；
- `Verify` 和多模板 `Identify`；
- 每次物理按压最多 3 张独立图像（`RetryCaptureIMG`）；
- 固定阈值 **7**，绝不累加或融合多个弱分数；
- 最多 3 次物理按压后才终止拒绝；
- 20-view enrollment 与 template-v4/SIGFM-v3 兼容；
- 有界 transport recovery、boot prewarm 和 deep-sleep resume prewarm；
- 不再使用周期性 synthetic Claim keepalive；
- release build 不含生物特征 dump writer。

### rel42 候选：仅会话内自适应 + 跨发行版安装

rel42 不改变 rel40 已验证的生物识别路径。它移除了 rel24–rel40 的持久化
timing 文件，因为 lifecycle/prewarm 失败可能把 pacing 永久推高。每个新
lifecycle 都从已验证的 100% 名义 timing 开始，只在 RAM 中自适应：

- lifecycle/prewarm 失败绝不改变 capture pacing；
- 连续 3 次“靠第二次 GET_IMAGE retry 才成功”的完整采集，提高当前
  daemon 的 capture pacing 一个 50 点步长；
- 8 次 clean capture 后向 100% 回落一个步长；
- 真正的生物识别 transport desync 可以提高当前 session pacing，并触发
  已验证的完整 session recovery；
- protocol/TLS timing 也只在当前 session 中自适应，绝不写盘。

rel42 软件测试和可重复 libfprint build 已通过；portable build/ABI gate 也已在干净的 Debian stable、Fedora current、openSUSE Tumbleweed、Arch Linux 与 Alpine edge/musl 容器中通过。在 rel42 自己的 cold-boot 人工验证完成前，rel40 仍然是 runtime 基准。

## 安装

推荐从源码 checkout 执行：

```bash
./fingerprint/install-linux.sh
```

安装器自动识别 Arch/CachyOS、Debian/Ubuntu、Fedora/RHEL-family、
openSUSE 与 Alpine。Arch/CachyOS 使用原生 pacman 包；systemd 系统通过
service-local `LD_LIBRARY_PATH` **只让 fprintd 使用** `/usr/local`
libfprint。非 systemd 系统通过 `/etc/dbus-1/system-services` 中更高优先级
的 D-Bus activation wrapper 实现同样隔离，不修改全局 `ld.so.conf`。
Meson `libdir` 会动态检测（Debian multiarch、`lib64`、普通 `lib`），且在
修改系统文件之前会用发行版自己的 fprintd 验证 staged candidate 的 ABI。

常用模式：

```bash
./fingerprint/install-linux.sh --build-only
./fingerprint/install-linux.sh --no-install-deps
./fingerprint/install-linux.sh --no-desktop-integration
```

回滚：

```bash
sudo /var/lib/gxfp51a0-local-install/uninstall.sh
```

Arch/CachyOS 也可以直接执行：

```bash
./fingerprint/install-arch.sh
```

安装器不会删除 enrollment，也不会删除已经验证的 PMK cache。rel42 升级
只清理 rel24–rel40 遗留的非敏感 timing 整数。

对于 Plasma Login Manager 6.7.5，本仓库还提供已验证的密码/指纹分离认证
兼容包：输入密码不会再等待指纹 timeout。其他桌面继续使用各自原生
fprintd/PAM 集成。

### 可选的隐私保护 matcher 验证

Benjamin Allègre（Sigfrodr）在 Sigfrodr/libfprint-goodixtls 中发布了 tools/eval/fp_eval.py，作为 Milan-SPI 系列的本地统一评估工具。它使用互不重叠的 enrol/probe 划分，只输出 EER、FAR/FRR、分数分布和 d-prime 等聚合统计；原始指纹图像和模板始终留在测试者自己的机器上。该工具适合为 SIGFM 提供可用于 upstream 的多用户验证，但不是驱动的运行时依赖；release build 仍不包含生物特征 capture dump 功能。

## 历史演进

### rel24-rc1：慢速传输兼容候选版

首个确认的 MateBook 13 2020 ST411/14115 用户报告表明：rel23 在该机型上可以正确认证，但传输层有时会进入非常慢的 GET_IMAGE/FDT 重试状态。rel24-rc1 仍以已验证的 30 ms 采集间隔为默认值；只有在 GET_IMAGE 完整失败后，才独立学习 100–300% 的采集 pacing。该值与 TLS/初始化 timing scale 完全分离，并且只有在一次完整指纹采集成功后才持久化。`no ACK/TLS` 与“收到 ACK 但重试后仍无 TLS 图像”都会触发完整 MCU/session 恢复；传输失败不会消耗三次固定生物识别尝试中的任何一次。

枚举阶段的 prewarm 也被刻意限制为短路径：一次外层尝试、最多两次 cached-PMK TLS 尝试，并且不执行 fresh-staging fallback。即使该优化失败，fprintd 仍会正常可用，真正的生物识别 open 路径仍保留完整的有界恢复。rel24-rc1 不改变 template v4、SIGFM v3、RANSAC 阈值 7、20 个 enrollment view 或最多三次独立验证按压。

Release 包含：

- Arch/CachyOS 原生安装包；
- 可移植 Linux 源码 bundle；
- 安装说明；
- SHA-256 校验。

### Arch / CachyOS

从仓库根目录执行：

    ./fingerprint/install-arch.sh

安装器会检查 GXFP51A0、构建并安装审核过的 libfprint/fprintd、仅增加驱动所需的 gpiochip 权限，并安装 boot/resume prewarm。仅在 Plasma 6.7.5 上，它还会应用 package-managed、幂等且可回滚的 KDE/Plasma Login Manager 兼容集成；其他桌面继续使用自己的原生 fprintd/PAM 集成。之后可使用桌面标准设置，或：

    fprintd-enroll -f right-index-finger
    fprintd-verify
    fprintd-list "$USER"

驱动要求 20 次 enrollment 按压。每次轻微移动手指，让 80×64 小传感器覆盖不同区域。

### 旧开发模板

当前磁盘格式为 driver template v4 / SIGFM v3。如果之前安装过本仓库的早期开发版本，可能需要一次性删除旧模板并重新 enrollment：

    fprintd-delete "$USER"

全新安装不需要此步骤。

### Debian / Ubuntu / Fedora / openSUSE / Alpine / 其他 Linux

可移植源码安装器会重建精确固定的 libfprint candidate，并将替换隔离在 `/usr/local`：

    ./fingerprint/install-linux.sh

支持 Arch/CachyOS、Debian/Ubuntu、Fedora、openSUSE、Alpine 的构建依赖。Arch/CachyOS 委托给原生 pacman 包；其他系统先 stage candidate 并验证发行版 fprintd ABI，再通过 systemd drop-in 或 D-Bus activation wrapper 只让 fprintd 使用本地 libfprint，同时保存 rollback manifest。

回滚：

    sudo /var/lib/gxfp51a0-local-install/uninstall.sh

只验证构建而不安装：

    ./fingerprint/install-linux.sh --build-only

## Matcher

生产 matcher 使用：

- 自适应背景减除；
- percentile normalization + unsharp；
- 两级 multi-scale FAST-9 keypoints；
- 非定向 BRIEF-256 descriptors；
- mutual-best cross-check + Lowe ratio filter；
- 200 次 rigid RANSAC，2 px inlier tolerance；
- 最小二乘 rigid refinement；
- 在 20 个 enrollment view 中取最佳分数。

驱动不会在失败后降低阈值、累加多个弱分数，也不会从失败/低置信验证中学习。`GXFP_MATCH_DIAGNOSTICS` 下的 pixel/ZNCC scorer 仅供研究，不参与认证决策。

## 贡献者验证

    make -C fingerprint verify

主要 release gate 包括：

    SOURCE_MANIFEST=PASS
    LIBFPRINT_BUILD=PASS
    GOODIX51A0_OBJECT_COMPILED=YES
    GOODIX51A0_FASTBRIEF_RANSAC_IN_LIBRARY=YES
    GOODIX51A0_IDENTIFY_PATH_IN_LIBRARY=YES
    RELEASE_BIOMETRIC_DUMP_HOOK=ABSENT
    SOFTWARE_BUILD_READY=YES
    ACTIVE_SENSOR_IO=NONE
    GPIO_WRITES=NONE
    MMIO_WRITES=NONE
    FIRMWARE_ACTIONS=NONE

验证 target 不执行主动传感器传输、GPIO/MMIO 写入或固件操作。普通用户不需要 `fingerprint/tools/` 下的维护诊断。

## 安全与隐私

请勿提交或发布：

- 指纹采集图像或 enrollment 模板；
- PMK/PSK/密钥材料或设备专用 fixture；
- Goodix/Huawei 专有二进制或固件；
- 序列号或私有机器标识。

已验证的 PMK cache 仍作为受保护的 runtime 状态保存在 `/var/lib/fprint/`。rel42 不再持久化任何自适应 timing；升级时只删除旧版留下的非敏感 timing 整数。v4 fprintd 模板属于生物特征数据，应按敏感认证数据保护。驱动不会刷写传感器固件。

## 支持范围

已证明的目标是上述 GXFP51A0 / GF3658 / ST411 精确组合。即使 ACPI HID 相同，其他机器仍可能有不同的 GPIO 接线、固件或主板集成。

这是 reverse-engineered 的实验性生物识别软件。当前验证主要来自参考设备和同一用户的跨手指负样本，不等同于大规模跨人群生物识别认证。不要把指纹单独视为高保证级安全因素。

更多信息：

- [桌面原生集成](docs/native-desktop-integration.md)
- [provenance](PROVENANCE.md)
- [驱动源码](driver/goodix51a0/)
- [research log](docs/research-log.md)
- [当前 handoff](HANDOFF_CURRENT.md)

生产驱动子树使用 `LGPL-2.1-or-later`，具体以各文件 SPDX 标记和 [PROVENANCE.md](PROVENANCE.md) 为准。

[executed on device: Pegasus (8a6eeb21-0158-4e6d-b3ea-91d580f8a223)]