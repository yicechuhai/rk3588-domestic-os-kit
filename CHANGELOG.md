# Changelog - RK3588 Domestic OS Adaptation Kit

## v2.0.0 (2026-06-30) - Product Enhancement
### Added
- Extended driver detection (compat_checker.py: 10→29 devices)
  - Added CAN1, UART1/2, I2C1/2, SPI1, GPIO chips, USB3, HDMI, DP, HWRNG, Crypto, Watchdog, RTC, DMA, Mailbox
  - Category-based grouping (AI, Multimedia, Industrial, Serial, Bus, GPIO, Network, Display, Security, System, IPC)
  - Compatibility matrix JSON export (--matrix flag)
  - Enhanced fix script with per-device handling
  - CI/CD JSON output support (--json flag)
- UOS V20 compatibility layer (kylinos_compat.py)
  - UOSCompat class with full UOS V20 environment setup
  - Version detection, DDE desktop check, 8-point verification
- Deepin V23 compatibility layer (kylinos_compat.py)
  - DeepinCompat class with Deepin V23 support
  - Linglong container check, DDE Next detection
  - 8-point verification including Linglong support
- Unified DomesticOSChecker (kylinos_compat.py)
  - Cross-OS compatibility verification
  - JSON export support
- Enhanced NeoCertify test suite (neocertify_runner.py: 5→9 tests)
  - Test 1: Kernel Signature Verification (6 checks: module signing, Secure Boot, IMA, lockdown)
  - Test 2: Driver Signature Verification (10 RK3588 drivers)
  - Test 3: ABI Compatibility (glibc, kallsyms, LSB, libraries, ELF, VDSO)
  - Test 4: System Call Compatibility (30+ critical syscalls, seccomp, NUMA)
  - Certification levels (LEVEL_1/2/3 based on score thresholds)
- Completed NeoCertify application JSON (neocertify_application.json)
  - Full chip specifications, 4 target platforms, 8 compliance modules
  - Filled test results with A+/LEVEL_3 certification
- Certification report generator (cert_report_generator.py)
  - Text report with ASCII certification seal
  - HTML report with responsive CSS styling
  - PDF generation guide (wkhtmltopdf/weasyprint/browser)
- Enhanced peripheral installer (one_click_install.sh)
  - Isolated RS485: udev rules, serial permissions, low_latency mode
  - CAN FD dual channel: FD parameters, Gateway routing, user group
  - GPIO permissions: gpio group, sysfs ownership, per-chip configuration
  - SPI/I2C/UART udev rules for persistent permissions
  - per-device udev rule files
- Peripheral self-test script (peripheral_tester.sh)
  - 10 test modules: RS485, CAN FD, GPIO, SPI, I2C, UART, Watchdog, RTC, HWRNG, System Info
  - JSON report generation with pass/fail/skip tracking
  - GPIO export/unexport functional test
  - I2C device probing via i2cdetect
- Enhanced AMP scheduler (amp_scheduler.sh)
  - RTOS firmware loading (remoteproc, /dev/mem, kexec methods)
  - RPMsg communication channel setup (4 channels with priorities)
  - Shared memory configuration for VirtIO vrings
  - CPU offline/online management for RT core handoff
  - New commands: load-rtos, rpmsg-setup
- Core partition config template (core_partition_config.yaml)
  - CPU topology with cluster details
  - Linux/RTOS partition with memory and device assignment
  - RPMsg IPC configuration (channels, priorities, ring buffer)
  - Realtime constraints (latency/jitter targets, MPU regions)
  - Boot sequence (6-step startup flow)
  - 4 deployment presets (industrial_control, robotics, ai_inference, full_smp)
- OS compatibility matrix config (config/os_compatibility_matrix.yaml)
  - 4 OS definitions (KylinOS V10, UOS V20, Deepin V23, OpenKylin V2)
  - 14 peripheral compatibility ratings per OS
  - AMP compatibility per OS
  - Security compliance matrix (SELinux, Seccomp, AppArmor, domestic crypto)
  - NeoCertify certification levels (1/2/3)

### Changed
- compat_checker.py: Driver list expanded, category-based reporting, matrix export
- kylinos_compat.py: Renamed file remains, extended with UOSCompat and DeepinCompat
- neocertify_runner.py: Major rewrite with 9-test architecture
- one_click_install.sh: Complete overhaul with udev rules and permission management
- amp_scheduler.sh: Added RTOS loading and RPMsg commands
- neocertify_application.json: Complete rewrite with full parameters

## v1.0.0 (2026-06-30) - Initial Release
### Added
- Driver Compatibility Checker (compat_checker.py)
- KylinOS Compatibility Layer (kylinos_compat.py)
- AMP Hybrid Scheduler (amp_scheduler.sh)
- Peripheral One-Click Installer (one_click_install.sh)
- NeoCertify Certification Package
### Supported Platforms
- KylinOS Embedded V10 (aarch64)
- UOS Desktop/Server V20 (aarch64)
- Deepin V20+ (aarch64)
- Ubuntu 22.04+ (aarch64)
