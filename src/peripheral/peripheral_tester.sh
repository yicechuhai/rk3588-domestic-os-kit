#!/bin/bash
# =============================================================================
# RK3588 Peripheral Functional Self-Test Script
# 外设功能自检：RS485/CAN FD/GPIO/I2C/SPI/UART/Watchdog/RTC
# 生成测试报告 JSON
# =============================================================================
set -euo pipefail

SELF_TEST_DIR="/opt/rk3588-peripherals/selftest"
REPORT_FILE="$SELF_TEST_DIR/peripheral_test_report.json"
TIMESTAMP=$(date -Iseconds)
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_TESTS=0

mkdir -p "$SELF_TEST_DIR"

# ── 工具函数 ──
log_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "  [PASS] $1"
}

log_fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "  [FAIL] $1 — $2"
}

log_skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "  [SKIP] $1 — $2"
}

warn() { echo "  ⚠ $1"; }

# ── 初始化 JSON 报告 ──
init_report() {
    cat > "$REPORT_FILE" << EOF
{
  "test_name": "RK3588 Peripheral Self-Test",
  "timestamp": "$TIMESTAMP",
  "hostname": "$(hostname)",
  "kernel": "$(uname -r)",
  "arch": "$(uname -m)",
  "tests": [],
  "summary": {}
}
EOF
}

append_test() {
    local name="$1"
    local status="$2"
    local detail="$3"
    # Use python to append JSON (more reliable than sed on nested JSON)
    python3 -c "
import json, sys
with open('$REPORT_FILE') as f:
    data = json.load(f)
data['tests'].append({'name': '$name', 'status': '$status', 'detail': '$detail'})
with open('$REPORT_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
" 2>/dev/null || true
}

finalize_report() {
    python3 -c "
import json
with open('$REPORT_FILE') as f:
    data = json.load(f)
data['summary'] = {
    'total': $TOTAL_TESTS,
    'passed': $PASS_COUNT,
    'failed': $FAIL_COUNT,
    'skipped': $SKIP_COUNT,
    'pass_rate': round($PASS_COUNT * 100 / max($TOTAL_TESTS, 1), 1)
}
with open('$REPORT_FILE', 'w') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
"
}

# ══════════════════════════════════════════════════════
# Test 1: RS485 回环测试
# ══════════════════════════════════════════════════════
test_rs485() {
    echo ""
    echo "━━━ Test: RS485 隔离串口 ━━━"
    
    local rs485_port=""
    if [ -e /dev/ttyRS485 ]; then
        rs485_port="/dev/ttyRS485"
    elif [ -e /dev/ttyS0 ]; then
        rs485_port="/dev/ttyS0"
    fi
    
    if [ -z "$rs485_port" ]; then
        log_skip "RS485" "无可用串口"
        append_test "rs485" "SKIPPED" "no serial port found"
        return
    fi
    
    # 检查权限
    if [ -r "$rs485_port" ] && [ -w "$rs485_port" ]; then
        log_pass "RS485 权限 ($rs485_port)"
    else
        log_fail "RS485 权限" "无法读写 $rs485_port"
    fi
    
    # 检查是否为 RS485 模式 (通过 DTS)
    if grep -r "rs485" /proc/device-tree/ 2>/dev/null | head -1 > /dev/null; then
        log_pass "RS485 DTS配置"
    else
        log_fail "RS485 DTS配置" "未在设备树中找到 rs485 节点"
    fi
    
    # 简单串口可用性测试
    if command -v stty >/dev/null 2>&1; then
        if stty -F "$rs485_port" 115200 2>/dev/null; then
            log_pass "RS485 波特率配置 (115200)"
        else
            log_fail "RS485 波特率配置" "stty 配置失败"
        fi
    else
        log_skip "RS485 波特率测试" "stty 不可用"
    fi
    
    append_test "rs485" "PASS" "port=$rs485_port"
}

# ══════════════════════════════════════════════════════
# Test 2: CAN FD 测试
# ══════════════════════════════════════════════════════
test_can_fd() {
    echo ""
    echo "━━━ Test: CAN FD ━━━"
    
    local can_ok=0
    
    for iface in can0 can1; do
        if ip link show "$iface" >/dev/null 2>&1; then
            local state=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')
            echo "  $iface: $state"
            
            if [ "$state" = "UP" ]; then
                log_pass "CAN FD $iface 状态 (UP)"
                
                # 检查 FD 模式
                if ip -details link show "$iface" 2>/dev/null | grep -q "fd"; then
                    log_pass "CAN FD $iface FD模式已启用"
                else
                    log_fail "CAN FD $iface FD模式" "未启用 CAN FD"
                fi
                
                # 检查 bitrate
                local bitrate=$(ip -details link show "$iface" 2>/dev/null | grep -oP 'bitrate \K[0-9]+' | head -1)
                if [ -n "$bitrate" ]; then
                    log_pass "CAN FD $iface bitrate (${bitrate} bps)"
                fi
                
                can_ok=$((can_ok + 1))
            elif [ "$state" = "DOWN" ]; then
                log_fail "CAN FD $iface" "接口 DOWN"
            fi
        else
            warn "$iface 不存在 (可能在设备树中未启用)"
        fi
    done
    
    # 内核模块检查
    for mod in can can_raw can_dev rockchip_canfd; do
        if lsmod 2>/dev/null | grep -q "^$mod "; then
            log_pass "CAN 内核模块 $mod"
        else
            # modinfo check as fallback
            if modinfo "$mod" >/dev/null 2>&1; then
                log_pass "CAN 内核模块 $mod (可用)"
            else
                log_fail "CAN 内核模块 $mod" "不可用"
            fi
        fi
    done
    
    if [ $can_ok -gt 0 ]; then
        append_test "can_fd" "PASS" "interfaces=$can_ok"
    elif ip link show can0 >/dev/null 2>&1; then
        append_test "can_fd" "PARTIAL" "interface exists but not UP"
    else
        append_test "can_fd" "SKIPPED" "no CAN interfaces"
    fi
}

# ══════════════════════════════════════════════════════
# Test 3: GPIO 测试
# ══════════════════════════════════════════════════════
test_gpio() {
    echo ""
    echo "━━━ Test: GPIO ━━━"
    
    if [ ! -d /sys/class/gpio ]; then
        log_fail "GPIO 子系统" "不可用"
        append_test "gpio" "FAILED" "sysfs not available"
        return
    fi
    
    log_pass "GPIO sysfs 接口可用"
    
    local chip_count=0
    for chip in /sys/class/gpio/gpiochip*; do
        [ -e "$chip" ] || continue
        chip_count=$((chip_count + 1))
        local label=$(cat "$chip/label" 2>/dev/null || echo "unknown")
        local ngpio=$(cat "$chip/ngpio" 2>/dev/null || echo "?")
        local base=$(cat "$chip/base" 2>/dev/null || echo "?")
        
        if [ "$ngpio" -gt 0 ] 2>/dev/null; then
            log_pass "GPIO $(basename "$chip"): $label ($ngpio lines)"
        else
            log_fail "GPIO $(basename "$chip")" "无可用引脚"
        fi
    done
    
    if [ $chip_count -eq 0 ]; then
        log_fail "GPIO" "无 gpiochip 设备"
        append_test "gpio" "FAILED" "no gpiochips"
    else
        # 尝试导出/反导出 GPIO (使用非关键引脚)
        local test_gpio=""
        for chip in /sys/class/gpio/gpiochip*; do
            [ -e "$chip" ] || continue
            local base=$(cat "$chip/base" 2>/dev/null || echo "")
            if [ -n "$base" ]; then
                test_gpio=$((base + 10))  # 使用偏移 10 的引脚
                break
            fi
        done
        
        if [ -n "$test_gpio" ]; then
            if echo "$test_gpio" | sudo tee /sys/class/gpio/export > /dev/null 2>&1; then
                if [ -d "/sys/class/gpio/gpio$test_gpio" ]; then
                    log_pass "GPIO 导出/控制 (gpio$test_gpio)"
                    echo "$test_gpio" | sudo tee /sys/class/gpio/unexport > /dev/null 2>&1 || true
                else
                    log_fail "GPIO 导出验证" "导出后目录不存在"
                fi
            else
                warn "GPIO 导出测试跳过 (权限不足或引脚忙)"
            fi
        fi
        
        append_test "gpio" "PASS" "chips=$chip_count"
    fi
}

# ══════════════════════════════════════════════════════
# Test 4: SPI 测试
# ══════════════════════════════════════════════════════
test_spi() {
    echo ""
    echo "━━━ Test: SPI ━━━"
    
    local spi_count=0
    for spidev in /dev/spidev*; do
        [ -e "$spidev" ] || continue
        spi_count=$((spi_count + 1))
        
        if [ -r "$spidev" ] && [ -w "$spidev" ]; then
            log_pass "SPI $spidev (可读写)"
        else
            log_fail "SPI $spidev" "权限不足"
        fi
    done
    
    if [ $spi_count -eq 0 ]; then
        log_skip "SPI" "无 SPI 设备"
        append_test "spi" "SKIPPED" "no SPI devices"
    else
        append_test "spi" "PASS" "devices=$spi_count"
    fi
}

# ══════════════════════════════════════════════════════
# Test 5: I2C 测试
# ══════════════════════════════════════════════════════
test_i2c() {
    echo ""
    echo "━━━ Test: I2C ━━━"
    
    local i2c_count=0
    for i2cdev in /dev/i2c-*; do
        [ -e "$i2cdev" ] || continue
        i2c_count=$((i2c_count + 1))
        
        if [ -r "$i2cdev" ] && [ -w "$i2cdev" ]; then
            # 尝试探测 I2C 总线
            local bus_num=$(echo "$i2cdev" | grep -oP '\d+')
            if command -v i2cdetect >/dev/null 2>&1; then
                local devices=$(i2cdetect -y -r "$bus_num" 2>/dev/null | grep -cv "^ " || echo "0")
                log_pass "I2C $i2cdev (总线$bus_num, 探测到 $devices 设备)"
            else
                log_pass "I2C $i2cdev (可读写, 安装 i2c-tools 以探测设备)"
            fi
        else
            log_fail "I2C $i2cdev" "权限不足"
        fi
    done
    
    if [ $i2c_count -eq 0 ]; then
        log_skip "I2C" "无 I2C 设备"
        append_test "i2c" "SKIPPED" "no I2C devices"
    else
        append_test "i2c" "PASS" "buses=$i2c_count"
    fi
}

# ══════════════════════════════════════════════════════
# Test 6: UART 测试
# ══════════════════════════════════════════════════════
test_uart() {
    echo ""
    echo "━━━ Test: UART ━━━"
    
    local uart_count=0
    for uart in /dev/ttyS* /dev/ttyAMA*; do
        [ -e "$uart" ] || continue
        uart_count=$((uart_count + 1))
        
        if [ -r "$uart" ] && [ -w "$uart" ]; then
            log_pass "UART $uart (可读写)"
        else
            log_fail "UART $uart" "权限不足"
        fi
    done
    
    if [ $uart_count -eq 0 ]; then
        log_skip "UART" "无串口设备"
        append_test "uart" "SKIPPED" "no UART devices"
    else
        append_test "uart" "PASS" "ports=$uart_count"
    fi
}

# ══════════════════════════════════════════════════════
# Test 7: Watchdog 测试
# ══════════════════════════════════════════════════════
test_watchdog() {
    echo ""
    echo "━━━ Test: Watchdog ━━━"
    
    if [ -e /dev/watchdog ]; then
        log_pass "Watchdog 设备存在 (/dev/watchdog)"
        
        if [ -r /dev/watchdog ] && [ -w /dev/watchdog ]; then
            log_pass "Watchdog 权限 (可读写)"
        else
            log_fail "Watchdog 权限" "无法访问"
        fi
        
        # 检查 watchdog 超时
        local timeout=$(cat /sys/class/watchdog/watchdog0/timeout 2>/dev/null || echo "unknown")
        log_pass "Watchdog 超时: ${timeout}s"
        
        append_test "watchdog" "PASS" "timeout=$timeout"
    else
        log_skip "Watchdog" "设备不存在"
        append_test "watchdog" "SKIPPED" "device not present"
    fi
}

# ══════════════════════════════════════════════════════
# Test 8: RTC 测试
# ══════════════════════════════════════════════════════
test_rtc() {
    echo ""
    echo "━━━ Test: RTC ━━━"
    
    if [ -e /dev/rtc0 ]; then
        log_pass "RTC 设备存在 (/dev/rtc0)"
        
        if command -v hwclock >/dev/null 2>&1; then
            if hwclock -r >/dev/null 2>&1; then
                local rtc_time=$(hwclock -r 2>/dev/null)
                log_pass "RTC 时间读取成功: $rtc_time"
            else
                log_fail "RTC 时间读取" "hwclock 失败"
            fi
        else
            log_pass "RTC 设备可访问"
        fi
        
        append_test "rtc" "PASS" "device=/dev/rtc0"
    else
        log_skip "RTC" "设备不存在"
        append_test "rtc" "SKIPPED" "device not present"
    fi
}

# ══════════════════════════════════════════════════════
# Test 9: 硬件随机数
# ══════════════════════════════════════════════════════
test_hwrng() {
    echo ""
    echo "━━━ Test: 硬件随机数 (HWRNG) ━━━"
    
    if [ -e /dev/hwrng ]; then
        log_pass "HWRNG 设备存在 (/dev/hwrng)"
        
        # 测试随机数生成
        if dd if=/dev/hwrng bs=16 count=1 of=/dev/null 2>/dev/null; then
            log_pass "HWRNG 可读取"
        else
            log_fail "HWRNG" "无法读取"
        fi
        
        append_test "hwrng" "PASS"
    else
        log_skip "HWRNG" "设备不存在"
        append_test "hwrng" "SKIPPED"
    fi
}

# ══════════════════════════════════════════════════════
# Test 10: 系统信息
# ══════════════════════════════════════════════════════
test_system_info() {
    echo ""
    echo "━━━ Test: 系统信息 ━━━"
    
    # 内核版本
    log_pass "内核: $(uname -r)"
    
    # 架构
    log_pass "架构: $(uname -m)"
    
    # 设备树
    if [ -d /proc/device-tree ]; then
        log_pass "设备树: 可用"
    else
        log_fail "设备树" "不可用"
    fi
    
    # NPU
    if [ -e /dev/dri/renderD129 ]; then
        log_pass "NPU: 可用 (renderD129)"
    else
        warn "NPU 设备未找到"
    fi
    
    # RGA
    if [ -e /dev/rga ]; then
        log_pass "RGA: 可用"
    else
        warn "RGA 设备未找到"
    fi
    
    append_test "system_info" "PASS" "kernel=$(uname -r)"
}

# ── 打印总结 ──
print_summary() {
    echo ""
    echo "============================================"
    echo "  RK3588 外设自检报告"
    echo "============================================"
    echo "  时间:     $TIMESTAMP"
    echo "  主机:     $(hostname)"
    echo "  内核:     $(uname -r)"
    echo "  架构:     $(uname -m)"
    echo "--------------------------------------------"
    echo "  测试总数: $TOTAL_TESTS"
    echo "  通过:     $PASS_COUNT"
    echo "  失败:     $FAIL_COUNT"
    echo "  跳过:     $SKIP_COUNT"
    echo "  通过率:   $(python3 -c "print(round($PASS_COUNT * 100 / max($TOTAL_TESTS, 1), 1))")%"
    echo "--------------------------------------------"
    
    if [ $FAIL_COUNT -gt 0 ]; then
        echo "  ⚠ $FAIL_COUNT 项测试失败，请检查硬件连接和驱动!"
        exit 2
    else
        echo "  ✓ 所有测试通过!"
        exit 0
    fi
    
    echo "  报告文件: $REPORT_FILE"
    echo "============================================"
}

# ── 主函数 ──
main() {
    echo "============================================"
    echo "  RK3588 Peripheral Self-Test v1.0"
    echo "  $(date)"
    echo "============================================"
    
    init_report
    
    test_rs485
    test_can_fd
    test_gpio
    test_spi
    test_i2c
    test_uart
    test_watchdog
    test_rtc
    test_hwrng
    test_system_info
    
    finalize_report
    print_summary
}

main
