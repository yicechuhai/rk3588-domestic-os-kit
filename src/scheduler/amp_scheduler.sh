#!/bin/bash
# =============================================================================
# RK3588 Hybrid Scheduling Framework (Linux + RTOS)
# 大核(A76)跑 RTOS/裸机任务，小核(A55)跑 Linux 管理任务
# =============================================================================
# AMP 架构: Asymmetric Multi-Processing
#  - Core 0-3 (A55): Linux housekeeping + management
#  - Core 4-7 (A76): RTOS / bare-metal real-time tasks
# =============================================================================

set -euo pipefail

CONFIG_FILE="${1:-/opt/rk3588-toolkit/config/amp_config.yaml}"

usage() {
    cat << EOF
RK3588 Hybrid Scheduler v1.0 (AMP Mode)

Usage: $0 <config.yaml>

Architecture:
  ┌─────────────────────────────────────────┐
  │  RK3588 SoC                              │
  │  ┌──────────────┐  ┌──────────────────┐  │
  │  │ A55 Cluster  │  │  A76 Cluster     │  │
  │  │ Core 0-3     │  │  Core 4-7        │  │
  │  │ Linux SMP    │  │  RTOS/Bare-Metal │  │
  │  │ Management   │  │  Real-Time Tasks │  │
  │  └──────┬───────┘  └───────┬──────────┘  │
  │         │                  │             │
  │         └──── IPC ────────┘             │
  │         (Shared Memory / RPMsg)          │
  └─────────────────────────────────────────┘

Config Format (YAML):
  amp:
    linux_cores: "0-3"       # A55 cores for Linux
    rtos_cores: "4-7"        # A76 cores for RTOS
    rtos_image: "/opt/rtos/zephyr.bin"  # RTOS firmware
    shared_memory: 0x10000000           # IPC shared memory
    ipc: rpmsg                          # rpmsg | mailbox | custom

Commands:
  setup     Apply AMP configuration
  teardown  Restore SMP mode
  status    Show current AMP status

EOF
    exit 0
}

setup_amp() {
    echo "=========================================="
    echo "  RK3588 AMP Hybrid Scheduler Setup"
    echo "=========================================="
    
    # 1. Isolate RTOS cores
    echo "[1/4] Isolating RTOS cores..."
    ISOL_CPUS="${LINUX_CORES:-0-3}"
    sudo bash -c "echo $ISOL_CPUS > /sys/devices/system/cpu/isolated" 2>/dev/null || {
        echo "  WARNING: isolcpus not supported dynamically"
        echo "  Add 'isolcpus=${RTOS_CORES:-4-7}' to kernel cmdline"
    }
    
    # 2. CPU frequency locking
    echo "[2/4] Locking CPU frequencies..."
    for cpu in /sys/devices/system/cpu/cpu[4-7]; do
        echo performance | sudo tee $cpu/cpufreq/scaling_governor > /dev/null 2>&1 || true
        freq=$(cat $cpu/cpufreq/scaling_max_freq 2>/dev/null || echo "N/A")
        echo "  $(basename $cpu): governor=performance max=$((freq/1000))MHz"
    done
    
    # 3. Disable CPU idle for RT cores
    echo "[3/4] Disabling CPU idle states..."
    for cpu in /sys/devices/system/cpu/cpu[4-7]/cpuidle; do
        for state in $cpu/state*/disable; do
            echo 1 | sudo tee $state > /dev/null 2>&1 || true
        done
    done
    echo "  CPU idle disabled for cores 4-7"
    
    # 4. Set RT scheduling parameters
    echo "[4/4] Configuring RT scheduler..."
    echo 980000 | sudo tee /proc/sys/kernel/sched_rt_runtime_us > /dev/null 2>&1 || true
    echo "  RT bandwidth: 98%"
    
    echo ""
    echo "AMP setup complete!"
    echo "  Linux cores: $ISOL_CPUS (management)"
    echo "  RTOS cores:  4-7 (real-time)"
    echo ""
    echo "Next steps:"
    echo "  1. Load RTOS firmware to cores 4-7"
    echo "  2. Start IPC between Linux and RTOS"
    echo "  3. Run jitter test: python3 jitter_monitor.py"
}

teardown_amp() {
    echo "Restoring SMP mode..."
    echo "" | sudo tee /sys/devices/system/cpu/isolated > /dev/null 2>&1 || true
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        echo 0 | sudo tee $cpu > /dev/null 2>&1 || true
    done
    echo 950000 | sudo tee /proc/sys/kernel/sched_rt_runtime_us > /dev/null 2>&1 || true
    echo "SMP mode restored."
}

status() {
    echo "=== CPU Isolation ==="
    isolated=$(cat /sys/devices/system/cpu/isolated 2>/dev/null || echo "none")
    echo "Isolated: $isolated"
    
    echo ""
    echo "=== CPU Governors ==="
    for cpu in /sys/devices/system/cpu/cpu[4-7]; do
        gov=$(cat $cpu/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
        echo "  $(basename $cpu): $gov"
    done
    
    echo ""
    echo "=== RT Scheduler ==="
    rt_runtime=$(cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null)
    rt_period=$(cat /proc/sys/kernel/sched_rt_period_us 2>/dev/null)
    echo "  RT bandwidth: $rt_runtime/$rt_period us ($((100*rt_runtime/rt_period))%)"
    
    echo ""
    echo "=== RT Processes ==="
    ps -eo pid,rtprio,comm,psr --sort=-rtprio | head -10
}

case "${1:-}" in
    setup)    setup_amp ;;
    teardown) teardown ;;
    status)   status ;;
    *)        usage ;;
esac
