# GPU 与电源 — 按需 NVIDIA MX250

> **English: [README.md](README.md)** · **Français : [README.FR.md](README.FR.md)**

本节解决 Huawei MateBook 13（Intel iGPU + NVIDIA GeForce MX250）上的一个具体问题：**空闲时让独显真正退出工作状态，同时在需要时无需注销或重启即可让指定应用使用 NVIDIA。**

## 为什么不保持 Hybrid 常驻？

在已验证的 MateBook 13 / MX250 上，即使 NVIDIA 看起来处于 idle，只要它持续可见，就会影响电池续航。因此目标空闲状态比普通 PRIME Hybrid 更严格：

    Intel iGPU：存在并驱动桌面
    MX250：从 PCI 移除
    NVIDIA：内核模块已卸载
    PCIe root port：在硬件允许时 runtime-suspended

受管应用启动时，GPU 被热重新枚举，加载 NVIDIA R580，并只给该应用注入 PRIME Render Offload 环境。最后一个受管负载结束后，NVIDIA 模块会卸载，MX250 再次从 PCI 移除。

## 已验证配置

- Huawei MateBook 13，Intel + NVIDIA GeForce MX250；
- MX250 PCI ID `10de:1d13` / GP108M（Pascal）；
- KDE Plasma Wayland；
- NVIDIA 专有 R580 分支。

脚本动态发现 Intel GPU、MX250 与 PCIe root port。默认拒绝非 Huawei 硬件，并始终要求 MX250 PCI ID 匹配。

### 驱动要求：R580

NVIDIA 590 及以后分支已停止支持 Pascal。MX250 用户必须使用专有 legacy R580。安装器支持 Arch/CachyOS、Fedora、Debian/Ubuntu 的对应安装路径，但不会静默启用第三方仓库。

### 不要叠加多个 GPU/CPU 电源管理器

本管理器安装后负责 MX250 的 PCI/模块生命周期。不要同时用 `optimus-manager`、EnvyControl、supergfxctl 模式切换或其他会装载/卸载/移除 NVIDIA 的工具。

CPU/平台电源策略建议只保留一个桌面集成提供者，例如 `power-profiles-daemon`。GPU Control 只报告当前 profile，不会覆盖全局策略；重负载应用可以单独通过 `powerprofilesctl launch` 在自己的生命周期内临时保持 `performance`。

## 架构

### 空闲 / 启动

安装器创建：

- 阻止 NVIDIA/nouveau 自动加载的 modprobe 策略；
- 最小权限 root helper；
- 启动服务，在图形登录前尽量卸载 NVIDIA 并移除 MX250；
- 稳定的 Intel DRM alias；
- Plasma/KWin systemd user drop-in，固定 KWin 使用 Intel；
- 周期 cleanup timer，处理崩溃或短暂脱离 launcher 的进程。

### 启动受管应用

`huawei-matebook-dgpu-run` 获取一个 lease。第一个 lease 会：

1. 执行 PCI rescan；
2. 动态定位 `10de:1d13`；
3. 加载 `nvidia`、`nvidia_modeset`、`nvidia_drm`、`nvidia_uvm`；
4. 检查桌面/合成器没有意外占用 NVIDIA；
5. 使用 PRIME Render Offload 启动应用。

多个受管应用可共享同一个 dGPU。只有没有有效 lease 且没有进程仍占用 NVIDIA 设备节点时，GPU 才会被卸载并移除。

## 安装

使用普通用户运行，不要直接用 root：

    chmod +x huawei-matebook-13-gpu-manager.sh
    ./huawei-matebook-13-gpu-manager.sh --lang zh install

首次安装后建议重启，以应用启动策略、当前内核对应的 NVIDIA 模块和 KWin 环境。

安装器还会创建：

- `~/.local/bin/GPU-control`
- `~/.local/bin/gpu-control`

直接运行 `GPU-control` 会显示不会唤醒 dGPU 的只读 dashboard：Intel/NVIDIA 状态、PCIe runtime 状态、当前电源 profile、**当前正在运行内核**的 NVIDIA 可用性，以及允许启动 MX250 的应用列表。

## 添加/移除应用

    GPU-control
    GPU-control add
    GPU-control add DaVinciResolve.desktop
    GPU-control remove DaVinciResolve.desktop
    GPU-control list

管理器会创建用户级 `.desktop` override，并保存原始 launcher。`DBusActivatable=false` 会确保桌面真正执行被修改的 `Exec=`。

## 单次命令

    GPU-control run -- glxinfo -B
    GPU-control run -- blender

## Steam

Steam 客户端本身保持在 Intel。游戏可通过 runner 按需使用 MX250：

    GPU-control steam-add 730
    GPU-control steam-remove 730
    GPU-control steam-all-on

`steam-all-on` 会管理已安装游戏，但排除已知 Valve 兼容组件，例如 Proton 和 Steam Linux Runtime。Steam 必须完全退出后才能修改 `localconfig.vdf`；每次编辑前都会创建时间戳备份。

## 状态与测试

    GPU-control
    GPU-control status
    GPU-control doctor
    GPU-control test

Dashboard 和诊断故意不使用 `nvidia-smi` 作为 idle probe，因为主动查询 NVIDIA 不适合“尽可能保持独显断电”的目标。它们还会区分：

- 健康的 Intel-only 空闲；
- NVIDIA 已为其他内核安装，但当前运行内核没有对应模块的 DKMS/kernel mismatch。

健康空闲应显示 MX250 absent、NVIDIA 模块未加载、PCIe root port suspended。`GPU-control test` 是主动测试，会短暂启动 NVIDIA renderer，然后必须回到完整 Intel-only。

## Plasma / KWin

现代 Plasma Wayland 可能自动打开新出现的 render node。管理器安装：

    KWIN_DRM_DEVICES=/dev/dri/huawei-matebook-intel
    KWIN_RENDER_NODES=

这样 KWin 保持在 Intel。root helper 也会在每次 hot-add 后验证结果；如果合成器意外抓住 NVIDIA，启动会 fail closed，而不是强行卸载正在使用的 GPU。

## 卸载

    GPU-control uninstall

卸载会恢复受管桌面 launcher，移除 helper/services/KWin override，但保留 NVIDIA 软件包。之后建议重启。

## 安全与报告

脚本不会刷写固件、GPU ROM 或 ACPI table。报告问题时请提供通用硬件 ID、发行版、内核、桌面环境以及 `GPU-control status` 输出，不要提交序列号、UUID、个人路径或无关系统 dump。
