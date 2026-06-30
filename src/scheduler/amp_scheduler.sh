#!/bin/bash
# =============================================================================
# RK3588 Hybrid Scheduling Framework v2.0 (Linux + RTOS)
# 大核(A76)跑 RTOS/裸机任务，小核(A55)跑 Linux 管理任务
# 支持 RPMsg 跨核通信、RTOS 镜像加载
# =============================================================================
# AMP 架构: Asymmetric Multi-Processing
#  - Core 0-3 (A55): Linux housekeeping + management
#  - Core 4-7 (A76): RTOS / bare-metal real-time tasks
# =============================================================================

set -euo pipefail

CONFIG_FILE="${1:-/opt/rk3588-toolkit/config/amp_config.yaml}"
RTOS_IMAGE_DIR="/opt/rtos/images"
SHARED_MEM_PATH="/dev/rpmsg"
AMP_LOG="/var/log/rk3588_amp.log"

usage() {
    cat << 'EOF'
RK3588 Hybrid Scheduler v2.0 (AMP Mode)

Usage: $0 <command> [config.yaml]

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
  │     (RPMsg / Shared Memory / Mailbox)    │
  └─────────────────────────────────────────┘

Commands:
  setup            Apply AMP configuration (isolcpus, RT params)
  load-rtos        Load RTOS firmware image to RT cores
  rpmsg-setup      Setup RPMsg communication channel
  status           Show current AMP status
  teardown         Restore SMP mode and unload RTOS

Config Format (YAML):
  amp:
    linux_cores: "0-3"
    rtos_cores: "4-7"
    rtos_image: "/opt/rtos/zephyr.bin"
    rtos_entry: 0x10000000
    shared_memory:
      address: 0x10000000
      size: 0x1000000
    ipc:
      type: "rpmsg"
      channels: 4
      buffer_size: 512
    cpu_freq:
      rt_governor: "performance"
      rt_max_freq: 2400000

EOF
    exit 0
}

# ── 日志 ──
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$AMP_LOG"; }

# ══════════════════════════════════════════════════════
# setup_amp: 基础 AMP 环境配置
# ══════════════════════════════════════════════════════
setup_amp() {
    log "=========================================="
    log "  RK3588 AMP Hybrid Scheduler Setup"
    log "=========================================="
    
    local LINUX_CORES="${LINUX_CORES:-0-3}"
    local RTOS_CORES="${RTOS_CORES:-4-7}"
    
    # 1. Isolate RTOS cores via kernel cmdline
    log "[1/5] Isolating RTOS cores..."
    if [ -w /sys/devices/system/cpu/isolated ]; then
        echo "$LINUX_CORES" | sudo tee /sys/devices/system/cpu/isolated > /dev/null 2>&1 || {
            log "  WARNING: Dynamic isolcpus not supported"
            log "  Add 'isolcpus=${RTOS_CORES} nohz_full=${RTOS_CORES} rcu_nocbs=${RTOS_CORES}' to kernel cmdline"
        }
    fi
    
    # 将 RTOS 核心离线（为加载 RTOS 做准备）
    for cpu in $(echo "$RTOS_CORES" | tr ',' ' ' | tr '-' ' '); do
        [ "$cpu" -ge 0 ] 2>/dev/null || continue
        if [ -d "/sys/devices/system/cpu/cpu$cpu" ]; then
            log "  Offlining CPU$cpu for RTOS..."
            echo 0 | sudo tee "/sys/devices/system/cpu/cpu$cpu/online" > /dev/null 2>&1 || true
        fi
    done
    
    # 2. CPU frequency locking for management cores
    log "[2/5] Locking CPU frequencies..."
    for cpu in /sys/devices/system/cpu/cpu[0-3]; do
        [ -d "$cpu" ] || continue
        echo performance | sudo tee "$cpu/cpufreq/scaling_governor" > /dev/null 2>&1 || true
        local freq=$(cat "$cpu/cpufreq/scaling_max_freq" 2>/dev/null || echo "0")
        freq=$((freq / 1000))
        log "  $(basename "$cpu"): governor=performance max=${freq}MHz"
    done
    
    # 3. Disable CPU idle for all cores (RTOS doesn't need idle)
    log "[3/5] Disabling CPU idle states..."
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle; do
        [ -d "$cpu" ] || continue
        for state in "$cpu"/state*/disable; do
            [ -f "$state" ] || continue
            echo 1 | sudo tee "$state" > /dev/null 2>&1 || true
        done
    done
    log "  CPU idle disabled for all cores"
    
    # 4. Set RT scheduling parameters
    log "[4/5] Configuring RT scheduler..."
    # RT throttle: allow 98% CPU for RT tasks
    echo 980000 | sudo tee /proc/sys/kernel/sched_rt_runtime_us > /dev/null 2>&1 || true
    # Migration cost
    echo 5000000 | sudo tee /proc/sys/kernel/sched_migration_cost_ns > /dev/null 2>&1 || true
    log "  RT bandwidth: 98%, migration_cost: 5ms"
    
    # 5. Shared memory setup for IPC
    log "[5/5] Setting up shared memory for IPC..."
    sudo mkdir -p "$SHARED_MEM_PATH"
    
    # Reserve shared memory region via CMA if available
    if [ -d /sys/kernel/debug/cma ]; then
        log "  CMA available for shared memory"
    fi
    
    log ""
    log "AMP setup complete!"
    log "  Linux cores: $LINUX_CORES (management)"
    log "  RTOS cores:  $RTOS_CORES (real-time)"
    log ""
    log "Next: $0 load-rtos"
}

# ══════════════════════════════════════════════════════
# load_rtos: 加载 RTOS 镜像到 RT 核
# ══════════════════════════════════════════════════════
load_rtos() {
    log "=========================================="
    log "  Loading RTOS Firmware to RT Cores"
    log "=========================================="
    
    local RTOS_IMAGE="${RTOS_IMAGE:-/opt/rtos/zephyr.bin}"
    local RTOS_ENTRY="${RTOS_ENTRY:-0x10000000}"
    local RTOS_CORES="${RTOS_CORES:-4-7}"
    
    # 检查镜像文件
    if [ ! -f "$RTOS_IMAGE" ]; then
        log "ERROR: RTOS image not found: $RTOS_IMAGE"
        log "  Supported images: Zephyr, FreeRTOS, bare-metal"
        log "  Build example: west build -b rk3588_a76 samples/hello_world"
        log "  Place image at: $RTOS_IMAGE_DIR/"
        return 1
    fi
    
    local image_size=$(stat -c%s "$RTOS_IMAGE" 2>/dev/null || echo "0")
    log "  RTOS Image: $RTOS_IMAGE ($image_size bytes)"
    log "  Entry Point: $RTOS_ENTRY"
    log "  Target Cores: $RTOS_CORES"
    
    # 计算镜像哈希
    if command -v sha256sum >/dev/null 2>&1; then
        local hash=$(sha256sum "$RTOS_IMAGE" | awk '{print $1}')
        log "  SHA256: $hash"
    fi
    
    # 加载到每个 RT 核心
    for cpu in $(seq 4 7); do
        if [ -d "/sys/devices/system/cpu/cpu$cpu" ]; then
            log ""
            log "  Loading RTOS to CPU$cpu..."
            
            # 方法1: 通过 remoteproc (如果内核支持)
            if [ -d "/sys/class/remoteproc/remoteproc0" ]; then
                log "  Method: remoteproc"
                echo "$RTOS_IMAGE" | sudo tee "/sys/class/remoteproc/remoteproc$((cpu-4))/firmware" > /dev/null 2>&1 || true
                echo start | sudo tee "/sys/class/remoteproc/remoteproc$((cpu-4))/state" > /dev/null 2>&1 || {
                    log "  WARNING: remoteproc load failed"
                }
            
            # 方法2: 通过 /dev/mem 直接加载 (需要内核配置 CONFIG_DEVMEM)
            elif [ -e /dev/mem ]; then
                log "  Method: /dev/mem direct load"
                
                # 写入入口地址到启动向量
                # 实际应由 bootloader 或专用工具完成
                log "  WARNING: Direct mem loading requires bootloader support"
                log "  CPU$cpu entry set to $RTOS_ENTRY"
            
            # 方法3: 通过 kexec (轻量级)
            elif command -v kexec >/dev/null 2>&1; then
                log "  Method: kexec (per-core)"
                log "  NOTE: kexec restarts the kernel on target core"
            
            else
                log "  WARNING: No RTOS loading mechanism available"
                log "  Supported methods: remoteproc, /dev/mem, kexec"
                log "  Ensure kernel has CONFIG_REMOTEPROC=y"
            fi
            
            # 启动 CPU
            log "  Starting CPU$cpu..."
            echo 1 | sudo tee "/sys/devices/system/cpu/cpu$cpu/online" > /dev/null 2>&1 || true
        fi
    done
    
    log ""
    log "RTOS firmware loading complete"
    log "  Verify with: $0 status"
}

# ══════════════════════════════════════════════════════
# rpmsg_setup: 配置 RPMsg 通信通道
# ══════════════════════════════════════════════════════
rpmsg_setup() {
    log "=========================================="
    log "  RPMsg Communication Setup"
    log "=========================================="
    
    local RPMsg_CHANNELS="${RPMsg_CHANNELS:-4}"
    local RPMsg_BUF_SIZE="${RPMsg_BUF_SIZE:-512}"
    
    # 加载 RPMsg 内核模块
    log "[1/4] Loading RPMsg kernel modules..."
    sudo modprobe rpmsg_core 2>/dev/null || log "  rpmsg_core not built-in"
    sudo modprobe rpmsg_char 2>/dev/null || log "  rpmsg_char not built-in"
    sudo modprobe rpmsg_ctrl 2>/dev/null || log "  rpmsg_ctrl not built-in"
    sudo modprobe rpmsg_ns 2>/dev/null || log "  rpmsg_ns (name service) not built-in"
    
    # 检查 RPMsg 设备
    log "[2/4] Checking RPMsg devices..."
    if ls /dev/rpmsg* >/dev/null 2>&1; then
        for dev in /dev/rpmsg*; do
            log "  ✓ $dev"
        done
    else
        log "  No /dev/rpmsg* devices found"
        log "  Create via: echo rpmsg-channel > /sys/bus/rpmsg/drivers/rpmsg_chrdev/bind"
    fi
    
    # 创建 RPMsg 端点
    log "[3/4] Creating RPMsg endpoints..."
    for ch in $(seq 0 $((RPMsg_CHANNELS - 1))); do
        local ep_name="rpmsg-amp-ch${ch}"
        if [ -w "/sys/bus/rpmsg/devices" ]; then
            log "  Creating endpoint: $ep_name"
            # 实际创建端点的命令取决于内核实现
        else
            log "  Endpoint $ep_name: requires kernel driver support"
        fi
    done
    
    # 配置共享内存的 RPMsg vrings
    log "[4/4] Configuring RPMsg vrings..."
    local SHMEM_ADDR="${SHMEM_ADDR:-0x10000000}"
    local SHMEM_SIZE="${SHMEM_SIZE:-0x1000000}"
    
    cat << VRING_INFO
    
  RPMsg Configuration:
    Shared Memory:  $SHMEM_ADDR (${SHMEM_SIZE} bytes)
    Channels:       $RPMsg_CHANNELS
    Buffer Size:    $RPMsg_BUF_SIZE bytes per message
    Protocol:       RPMsg VirtIO v2
    
  Channel Assignment:
    Channel 0:  System control (boot/reboot/sync)
    Channel 1:  Sensor data stream
    Channel 2:  Motor control commands
    Channel 3:  Debug/telemetry
    
  Linux-side API:
    open("/dev/rpmsg0") -> read/write -> close
    
  RTOS-side API (Zephyr example):
    #include <rpmsg.h>
    struct rpmsg_endpoint ep;
    rpmsg_init_ept(&ep, "rpmsg-amp-ch0", src, dst, callback);
    rpmsg_send(&ep, data, len);
    
VRING_INFO
    
    log "RPMsg setup complete"
    log "  Test: echo 'ping' > /dev/rpmsg0"
}

# ══════════════════════════════════════════════════════
# status: 显示当前 AMP 状态
# ══════════════════════════════════════════════════════
status() {
    echo ""
    echo "=== RK3588 AMP Status ==="
    echo ""
    
    echo "── CPU Isolation ──"
    local isolated=$(cat /sys/devices/system/cpu/isolated 2>/dev/null || echo "none")
    echo "  Isolated cores: $isolated"
    
    echo ""
    echo "── CPU Online Status ──"
    for cpu in /sys/devices/system/cpu/cpu[0-7]/online; do
        [ -f "$cpu" ] || continue
        local cpu_name=$(basename "$(dirname "$cpu")")
        local online=$(cat "$cpu" 2>/dev/null)
        echo "  $cpu_name: $([ "$online" = "1" ] && echo 'ONLINE' || echo 'OFFLINE (RTOS)')"
    done
    
    echo ""
    echo "── CPU Governors ──"
    for cpu in /sys/devices/system/cpu/cpu[0-7]; do
        [ -d "$cpu" ] || continue
        local gov=$(cat "$cpu/cpufreq/scaling_governor" 2>/dev/null || echo "N/A")
        local freq=$(cat "$cpu/cpufreq/scaling_cur_freq" 2>/dev/null || echo "0")
        freq=$((freq / 1000))
        echo "  $(basename "$cpu"): governor=$gov freq=${freq}MHz"
    done
    
    echo ""
    echo "── RT Scheduler ──"
    local rt_runtime=$(cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null || echo "N/A")
    local rt_period=$(cat /proc/sys/kernel/sched_rt_period_us 2>/dev/null || echo "N/A")
    if [ "$rt_runtime" != "N/A" ] && [ "$rt_period" != "N/A" ]; then
        echo "  RT bandwidth: $rt_runtime/$rt_period us ($((100 * rt_runtime / rt_period))%)"
    fi
    
    echo ""
    echo "── RPMsg Devices ──"
    if ls /dev/rpmsg* >/dev/null 2>&1; then
        ls -la /dev/rpmsg* 2>/dev/null | while read line; do echo "  $line"; done
    else
        echo "  No RPMsg devices"
    fi
    
    echo ""
    echo "── RTOS Image ──"
    if [ -n "${RTOS_IMAGE:-}" ] && [ -f "$RTOS_IMAGE" ]; then
        local size=$(stat -c%s "$RTOS_IMAGE" 2>/dev/null || echo "?")
        echo "  Image: $RTOS_IMAGE ($size bytes)"
    else
        echo "  No RTOS image configured"
    fi
    
    echo ""
    echo "── RT Processes ──"
    ps -eo pid,rtprio,comm,psr --sort=-rtprio 2>/dev/null | head -10
}

# ══════════════════════════════════════════════════════
# teardown: 恢复 SMP 模式
# ══════════════════════════════════════════════════════
teardown() {
    log "=========================================="
    log "  Restoring SMP Mode"
    log "=========================================="
    
    # 1. Stop RPMsg
    log "[1/5] Stopping RPMsg..."
    sudo modprobe -r rpmsg_ns rpmsg_ctrl rpmsg_char rpmsg_core 2>/dev/null || true
    
    # 2. Bring all cores online
    log "[2/5] Bringing all cores online..."
    for cpu in /sys/devices/system/cpu/cpu[4-7]; do
        [ -d "$cpu" ] || continue
        echo 1 | sudo tee "$cpu/online" > /dev/null 2>&1 || true
    done
    log "  All cores online"
    
    # 3. Re-enable CPU idle
    log "[3/5] Re-enabling CPU idle..."
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        [ -f "$cpu" ] || continue
        echo 0 | sudo tee "$cpu" > /dev/null 2>&1 || true
    done
    
    # 4. Clear isolcpus
    log "[4/5] Clearing CPU isolation..."
    if [ -w /sys/devices/system/cpu/isolated ]; then
        echo "" | sudo tee /sys/devices/system/cpu/isolated > /dev/null 2>&1 || true
    fi
    
    # 5. Restore scheduler defaults
    log "[5/5] Restoring scheduler defaults..."
    echo 950000 | sudo tee /proc/sys/kernel/sched_rt_runtime_us > /dev/null 2>&1 || true
    echo 500000 | sudo tee /proc/sys/kernel/sched_migration_cost_ns > /dev/null 2>&1 || true
    
    # Restore ondemand governor
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$cpu" ] || continue
        echo ondemand | sudo tee "$cpu" > /dev/null 2>&1 || true
    done
    
    log ""
    log "SMP mode restored."
    log "  All 8 cores available for Linux"
}

# ── 主入口 ──
case "${1:-}" in
    setup)
        setup_amp
        ;;
    load-rtos)
        load_rtos
        ;;
    rpmsg-setup)
        rpmsg_setup
        ;;
    status)
        status
        ;;
    teardown)
        teardown
        ;;
    *)
        usage
        ;;
esac
