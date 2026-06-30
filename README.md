# RK3588 Domestic OS Adaptation Kit

## 国产操作系统深度适配套件

支持麒麟OS、统信UOS、Deepin 等国产操作系统在 RK3588 上的完整适配。

## Components

| Module | Path | Description |
|--------|------|-------------|
| Driver Checker | src/driver-layer/compat_checker.py | 驱动兼容性检测 + 自动修复 |
| AMP Scheduler | src/scheduler/amp_scheduler.sh | Linux+RTOS 混合调度 |
| Peripheral Install | src/peripheral/one_click_install.sh | RS485/CAN/GPIO 一键安装 |
| Certification | src/cert/ | 信创认证支持包 |

## Quick Start

\\\ash
# 1. Check driver compatibility
sudo python3 src/driver-layer/compat_checker.py

# 2. Install industrial peripherals
sudo bash src/peripheral/one_click_install.sh

# 3. Setup hybrid scheduling
sudo bash src/scheduler/amp_scheduler.sh setup
\\\

## Supported OS

- 麒麟OS (Kylin) V10 SP1
- 统信UOS (UnionTech) 20/21
- Deepin 20+
