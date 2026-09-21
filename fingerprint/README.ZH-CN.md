# Goodix GXFP51A0 / GF3658 ST411 Linux 驱动

面向 Huawei MateBook 13 2021 系列中 SPI Goodix GXFP51A0 的实验性原生 libfprint 驱动。

> **English: [README.md](README.md)** · **Français : [README.FR.md](README.FR.md)**

## 状态 — 2026-09-20

已验证硬件目标：

- ACPI HID：`GXFP51A0`；
- Goodix GF3658 / ST411，chip ID `0x2504`；
- 已验证固件：`GF_ST411SEC_APP_14115`；
- SPI mode 0 + `SPI_CS_HIGH`，1 MHz；
- GPIO48 readiness/IRQ，GPIO264 MCU reset；
- TLS 1.2 `PSK-AES128-GCM-SHA256`；
- 有效指纹图像 80×64；
- libfprint 基线：`v1.94.100`。

生产路径：

    GXFP51A0 → libfprint → fprintd → KDE / GNOME / PAM / CLI

无需设备专用桌面 UI、PAM 重写、固件替换或 Goodix 专有 runtime。

### 已验证内容

在参考 GXFP51A0/GF3658/ST411 设备上：

- KDE/fprintd 标准 enrollment 可完成 **20 次接受的按压**；
- FAST-9 + BRIEF-256 + rigid RANSAC 匹配完全在主机侧 C 代码中执行；
- 接受阈值固定为 **7 个 RANSAC inliers**；
- 成功验证立即返回；
- no-match 最多可要求 **3 次完整、独立的按压** 后终止拒绝；重试次数固定，不会根据分数接近阈值的程度变化；
- `identify` 保持单次采集；
- target/TLS 短暂失同步使用有界恢复和持久化的初始化 timing scale；
- 图像采集仍使用已验证的名义 30 ms command gap；
- release build 不包含生物特征 dump writer。

3 次按压策略用于降低这个很小的 partial-print 传感器因手指位置变化造成的误拒，不会降低阈值，也不会把多个弱分数组合为一次成功。

## 安装

### 下载已打包的 rel23 release

对于已验证的 GXFP51A0 / GF3658 ST411，最简单的稳定版本起点是 [GitHub rel23 release](https://github.com/GodsQuantum/huawei-matebook-13-linux/releases/tag/fingerprint-gxfp51a0-rel23)。rel23 完全使用 libfprint 原生 SPI 路径：生成的 udev 规则支持 `acpi:GXFP51A0:GXFP51A0:` 这类 ACPI 后缀并直接绑定 `spidev`，不再需要 GXFP 专用 systemd binder。标准 fprintd 随 graphical boot transaction 启动并使用 `--no-timeout`；libfprint `probe()` 预热 TLS、背景和 FDT 状态。完整 warm context 在 Claim/Release 之间保留，同时关闭 SPI/GPIO handle；下次 Claim 会先做硬件重新验证，若传感器状态丢失则自动回退到有界 cold path。现有 template-v4 enrollment 保持兼容。

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

安装器会：

1. 如果系统不存在 `GXFP51A0` SPI/ACPI 设备则拒绝运行；
2. 本地构建已审核的 libfprint patch；
3. 安装 `libfprint-goodix51a0` 和 `fprintd`；
4. 只授予 fprintd 此驱动需要的 gpiochip 设备权限；
5. reload udev 并重启 fprintd。

它**不会修改 PAM、KDE 或 GNOME 配置**。之后可使用桌面标准设置，或：

    fprintd-enroll -f right-index-finger
    fprintd-verify
    fprintd-list "$USER"

驱动要求 20 次 enrollment 按压。每次轻微移动手指，让 80×64 小传感器覆盖不同区域。

### 旧开发模板

当前磁盘格式为 driver template v4 / SIGFM v3。如果之前安装过本仓库的早期开发版本，可能需要一次性删除旧模板并重新 enrollment：

    fprintd-delete "$USER"

全新安装不需要此步骤。

### Debian / Ubuntu / Fedora / 其他 Linux

可移植源码安装器会重建精确固定的 libfprint candidate，并将替换隔离在 `/usr/local`：

    ./fingerprint/install-linux.sh

支持 Arch/CachyOS、Debian/Ubuntu、Fedora、openSUSE 的构建依赖。Arch/CachyOS 会委托给原生 pacman 包；其他支持系统通过 systemd drop-in 只让 fprintd 使用本地 libfprint，并保存 rollback manifest。

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

PMK cache 与学习到的 timing 值位于 `/var/lib/fprint/`，不会被打包或版本控制。v4 fprintd 模板属于生物特征数据，应按敏感认证数据保护。驱动不会刷写传感器固件。

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
