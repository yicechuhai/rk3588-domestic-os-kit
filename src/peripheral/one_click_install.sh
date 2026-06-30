#!/bin/bash
# =============================================================================
# RK3588 Industrial Peripheral One-Click Installer v2.0
# 一键安装 RS485(隔离)、CAN FD、GPIO(权限)、I2C、SPI、Modbus 等工业外设
# =============================================================================
set -euo pipefail

INSTALL_DIR="/opt/rk3588-peripherals"
LOG_FILE="$INSTALL_DIR/install.log"
UDEV_RULES_DIR="/etc/udev/rules.d"
GPIO_GROUP="gpio"
CAN_GROUP="can"
SERIAL_GROUP="dialout"
MODBUS_USER="${SUDO_USER:-root}"

mkdir -p "$INSTALL_DIR" "$UDEV_RULES_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "  RK3588 Peripheral One-Click Installer v2.0"
echo "  $(date)"
echo "  User: $MODBUS_USER"
echo "=========================================="
echo ""

# ── 错误处理 ──
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

warn() {
    echo "WARNING: $1"
}

# ── RS485 (隔离型) ──
install_rs485() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[RS485] 隔离型 RS485 配置..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 加载工业 IO 模块
    sudo modprobe industrialio 2>/dev/null || warn "industrialio module not available"
    sudo modprobe industrialio_triggered_buffer 2>/dev/null || true
    
    # 检查设备树配置
    if grep -r "rs485" /proc/device-tree/ 2>/dev/null | head -1; then
        echo "[RS485] ✓ Device tree 已配置 rs485 节点"
    else
        echo "[RS485] ⚠ Device tree 未配置 rs485，需要手动添加 DTS:"
        cat << 'DTS'
&uart4 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&uart4m1_xfer>;
    rs485-rts-delay = <0 0>;
    linux,rs485-enabled-at-boot-time;
};
DTS
    fi
    
    # 隔离 RS485 串口权限设置
    RS485_PORTS=("/dev/ttyRS485" "/dev/ttyS0" "/dev/ttyS1" "/dev/ttyS2")
    for port in "${RS485_PORTS[@]}"; do
        if [ -e "$port" ]; then
            echo "[RS485] 配置端口: $port"
            sudo chown "root:$SERIAL_GROUP" "$port" 2>/dev/null || true
            sudo chmod 0660 "$port" 2>/dev/null || true
            # 设置低延迟模式
            sudo setserial "$port" low_latency 2>/dev/null || true
            echo "[RS485]   ✓ 权限: 0660, 组: $SERIAL_GROUP, low_latency"
        fi
    done
    
    # 隔离 RS485 udev 规则
    cat > "$UDEV_RULES_DIR/99-rk3588-rs485.rules" << 'UDEV'
# RK3588 Isolated RS485 UDEV Rules
SUBSYSTEM=="tty", KERNEL=="ttyRS485*", GROUP="dialout", MODE="0660", SYMLINK+="rs485-isolated"
SUBSYSTEM=="tty", KERNEL=="ttyS*", GROUP="dialout", MODE="0660"
UDEV
    echo "[RS485] ✓ udev 规则已安装: $UDEV_RULES_DIR/99-rk3588-rs485.rules"
    
    # RS485 隔离参数配置
    if [ -e "/dev/ttyRS485" ]; then
        echo "[RS485] 隔离配置参数:"
        echo "  - 波特率: 9600/19200/38400/115200"
        echo "  - 数据位: 8"
        echo "  - 停止位: 1"
        echo "  - 校验: None/Even/Odd"
        echo "  - 流控: RTS (自动)"
        echo "  - 隔离电压: 2500V (需硬件支持)"
    fi
}

# ── CAN FD ──
install_can_fd() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[CAN FD] CAN FD 驱动配置..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 加载 CAN 内核模块
    echo "[CAN FD] 加载内核模块..."
    sudo modprobe can 2>/dev/null || warn "can module not available"
    sudo modprobe can_raw 2>/dev/null || true
    sudo modprobe can_dev 2>/dev/null || true
    sudo modprobe can-gw 2>/dev/null || true
    sudo modprobe can-isotp 2>/dev/null || true
    sudo modprobe rockchip_canfd 2>/dev/null || warn "rockchip_canfd module not available"
    
    # 创建 CAN 用户组
    if ! getent group "$CAN_GROUP" > /dev/null 2>&1; then
        sudo groupadd "$CAN_GROUP" 2>/dev/null || true
    fi
    sudo usermod -aG "$CAN_GROUP" "$MODBUS_USER" 2>/dev/null || true
    
    # CAN0 配置
    if [ -d "/sys/class/net/can0" ]; then
        echo "[CAN FD] CAN0 接口已存在，配置中..."
    else
        echo "[CAN FD] 创建 CAN0 接口..."
        sudo ip link add dev can0 type can 2>/dev/null || warn "Cannot create can0 (check DTS)"
    fi
    
    # 配置 CAN FD 参数
    if ip link show can0 >/dev/null 2>&1; then
        echo "[CAN FD] 配置 CAN0 FD 参数:"
        # 仲裁域 500kbps，数据域 2Mbps (FD)
        sudo ip link set can0 type can \
            bitrate 500000 \
            dbitrate 2000000 \
            fd on \
            sample-point 0.875 \
            dsample-point 0.8 \
            restart-ms 100 \
            2>/dev/null || warn "CAN FD advanced params not fully supported"
        
        sudo ip link set up can0 2>/dev/null || warn "Cannot bring up can0"
        
        # 验证配置
        if ip link show can0 2>/dev/null | grep -q "UP"; then
            echo "[CAN FD] ✓ CAN0 UP (仲裁:500k, 数据:2M, FD:ON)"
            # 显示接口信息
            ip -details link show can0 2>/dev/null | grep -E "can|bitrate|state|fd"
        else
            warn "CAN0 is DOWN"
        fi
    else
        warn "CAN0 interface not found. Check device tree for rockchip,canfd"
    fi
    
    # CAN1 配置（如果存在）
    if [ -d "/sys/class/net/can1" ]; then
        echo "[CAN FD] 配置 CAN1..."
        sudo ip link set can1 type can bitrate 500000 dbitrate 2000000 fd on 2>/dev/null || true
        sudo ip link set up can1 2>/dev/null || warn "Cannot bring up can1"
        echo "[CAN FD] ✓ CAN1 UP"
    else
        echo "[CAN FD] CAN1 未在设备树中启用 (可选)"
    fi
    
    # CAN udev 规则
    cat > "$UDEV_RULES_DIR/99-rk3588-can.rules" << 'UDEV'
# RK3588 CAN FD UDEV Rules
SUBSYSTEM=="net", KERNEL=="can*", GROUP="can", MODE="0660"
UDEV
    echo "[CAN FD] ✓ udev 规则已安装"
    
    # CAN 网关配置（可选：CAN-以太网桥接）
    if command -v cangw &>/dev/null; then
        echo "[CAN FD] CAN-GW (网关路由)可用"
    fi
    
    # SocketCAN 测试提示
    echo "[CAN FD] 测试命令:"
    echo "  candump can0          # 接收 CAN 数据"
    echo "  cansend can0 123#DEADBEEF  # 发送 CAN 数据"
    echo "  canfdtest can0        # CAN FD 回环测试"
}

# ── GPIO ──
install_gpio() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[GPIO] GPIO 权限与配置..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 创建 GPIO 用户组
    if ! getent group "$GPIO_GROUP" > /dev/null 2>&1; then
        sudo groupadd "$GPIO_GROUP" 2>/dev/null || true
    fi
    sudo usermod -aG "$GPIO_GROUP" "$MODBUS_USER" 2>/dev/null || true
    
    # 加载 GPIO sysfs 接口
    sudo modprobe gpio-sysfs 2>/dev/null || true
    
    if [ -d /sys/class/gpio ]; then
        echo "[GPIO] GPIO 子系统可用"
        
        # 遍历所有 GPIO 芯片
        for chip in /sys/class/gpio/gpiochip*; do
            [ -e "$chip" ] || continue
            chip_name=$(basename "$chip")
            label=$(cat "$chip/label" 2>/dev/null || echo "unknown")
            ngpio=$(cat "$chip/ngpio" 2>/dev/null || echo "?")
            base=$(cat "$chip/base" 2>/dev/null || echo "?")
            echo "  $chip_name: $label ($ngpio lines, base=$base)"
        done
        
        # GPIO 权限配置
        for gpiochip in /sys/class/gpio/gpiochip*; do
            [ -e "$gpiochip" ] || continue
            sudo chown "root:$GPIO_GROUP" "$gpiochip"/* 2>/dev/null || true
            sudo chmod 0660 "$gpiochip"/* 2>/dev/null || true
        done
        
        # gpio udev 规则
        cat > "$UDEV_RULES_DIR/99-rk3588-gpio.rules" << 'UDEV'
# RK3588 GPIO UDEV Rules
SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
ACTION=="add", SUBSYSTEM=="gpio", KERNEL=="gpio*", GROUP="gpio", MODE="0660"
UDEV
        echo "[GPIO] ✓ udev 规则已安装"
        echo "[GPIO] ✓ GPIO 组权限已设置 (组: $GPIO_GROUP)"
    else
        warn "GPIO 子系统不可用"
    fi
}

# ── SPI ──
install_spi() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[SPI] SPI 配置..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    sudo modprobe spidev 2>/dev/null || true
    sudo modprobe rockchip-spi 2>/dev/null || true
    
    local spi_count=0
    for spidev in /dev/spidev*; do
        [ -e "$spidev" ] || continue
        spi_count=$((spi_count + 1))
        sudo chown "root:$GPIO_GROUP" "$spidev" 2>/dev/null || true
        sudo chmod 0660 "$spidev" 2>/dev/null || true
        echo "[SPI] ✓ $spidev (权限: 0660)"
    done
    
    if [ $spi_count -eq 0 ]; then
        warn "未找到 SPI 设备，请检查设备树配置"
    fi
    
    # SPI udev
    cat > "$UDEV_RULES_DIR/99-rk3588-spi.rules" << 'UDEV'
# RK3588 SPI UDEV Rules
SUBSYSTEM=="spidev", GROUP="gpio", MODE="0660"
UDEV
    echo "[SPI] ✓ udev 规则已安装"
}

# ── I2C ──
install_i2c() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[I2C] I2C 配置..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    sudo modprobe i2c-dev 2>/dev/null || true
    sudo modprobe i2c-rk3x 2>/dev/null || true
    
    local i2c_count=0
    for i2cdev in /dev/i2c-*; do
        [ -e "$i2cdev" ] || continue
        i2c_count=$((i2c_count + 1))
        sudo chown "root:$GPIO_GROUP" "$i2cdev" 2>/dev/null || true
        sudo chmod 0660 "$i2cdev" 2>/dev/null || true
        echo "[I2C] ✓ $i2cdev (权限: 0660)"
    done
    
    if [ $i2c_count -eq 0 ]; then
        warn "未找到 I2C 设备，请检查设备树配置"
    fi
    
    cat > "$UDEV_RULES_DIR/99-rk3588-i2c.rules" << 'UDEV'
# RK3588 I2C UDEV Rules
KERNEL=="i2c-[0-9]*", GROUP="gpio", MODE="0660"
UDEV
    echo "[I2C] ✓ udev 规则已安装"
}

# ── Modbus RTU (RS485) ──
install_modbus_rtu() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[Modbus RTU] Modbus over RS485..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    sudo modprobe industrialio_triggered_buffer 2>/dev/null || true
    
    local modbus_port=""
    if [ -e /dev/ttyRS485 ]; then
        modbus_port="/dev/ttyRS485"
    elif [ -e /dev/ttyS0 ]; then
        modbus_port="/dev/ttyS0"
    fi
    
    if [ -n "$modbus_port" ]; then
        echo "[Modbus RTU] 端口: $modbus_port"
        sudo chown "root:$SERIAL_GROUP" "$modbus_port" 2>/dev/null || true
        sudo chmod 0660 "$modbus_port" 2>/dev/null || true
        
        cat << 'MODBUS_INFO'
[Modbus RTU] 典型配置:
  - 协议: Modbus RTU (RS485)
  - 波特率: 9600/19200/38400/115200
  - 从站ID: 1-247
  - 功能码: 01/02/03/04/05/06/15/16
  - 超时: 1000ms (推荐)
  
[Modbus RTU] 测试命令:
  modbus_client --rtu /dev/rs485-isolated --baud 115200 --debug
MODBUS_INFO
    else
        warn "未找到 Modbus 串口设备"
    fi
}

# ── UART ──
install_uart() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[UART] UART 串口配置..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local uart_count=0
    for uart in /dev/ttyS* /dev/ttyAMA*; do
        [ -e "$uart" ] || continue
        uart_count=$((uart_count + 1))
        sudo chown "root:$SERIAL_GROUP" "$uart" 2>/dev/null || true
        sudo chmod 0660 "$uart" 2>/dev/null || true
        # 禁用控制台重定向到串口（如果是控制台端口）
        if [ "$uart" = "/dev/ttyS0" ] || [ "$uart" = "/dev/ttyAMA0" ]; then
            echo "[UART] $uart (可能是控制台端口，保留)"
        else
            echo "[UART] ✓ $uart (权限: 0660)"
        fi
    done
    
    if [ $uart_count -eq 0 ]; then
        warn "未找到 UART 设备"
    fi
}

# ── 重新加载 udev ──
reload_udev() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[UDEV] 重新加载 udev 规则..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    sudo udevadm control --reload-rules 2>/dev/null || warn "Cannot reload udev rules"
    sudo udevadm trigger 2>/dev/null || warn "Cannot trigger udev"
    echo "[UDEV] ✓ udev 规则已重新加载"
}

# ── 安装摘要 ──
print_summary() {
    echo ""
    echo "=========================================="
    echo "  外设安装完成摘要"
    echo "=========================================="
    
    echo ""
    echo "  设备节点状态:"
    for dev in /dev/ttyRS485 /dev/ttyS0 /dev/ttyS1 /dev/spidev0.0 /dev/i2c-0 /dev/gpiochip0; do
        if [ -e "$dev" ]; then
            perms=$(stat -c "%a:%G" "$dev" 2>/dev/null || echo "???")
            echo "    ✓ $dev ($perms)"
        else
            echo "    ✗ $dev (不存在)"
        fi
    done
    
    echo ""
    echo "  网络接口状态:"
    for iface in can0 can1; do
        if ip link show "$iface" >/dev/null 2>&1; then
            state=$(ip -br link show "$iface" 2>/dev/null | awk '{print $2}')
            echo "    ✓ $iface ($state)"
        else
            echo "    ✗ $iface (不存在)"
        fi
    done
    
    echo ""
    echo "  用户组成员:"
    echo "    gpio:     $(getent group gpio 2>/dev/null | cut -d: -f4 || echo '组不存在')"
    echo "    can:      $(getent group can 2>/dev/null | cut -d: -f4 || echo '组不存在')"
    echo "    dialout:  $(getent group dialout 2>/dev/null | cut -d: -f4 || echo '组不存在')"
    
    echo ""
    echo "  udev 规则:"
    ls -la "$UDEV_RULES_DIR"/99-rk3588-*.rules 2>/dev/null || echo "    无规则文件"
    
    echo ""
    echo "  重要提示:"
    echo "    1. 重新登录或执行 'newgrp gpio' 使组权限生效"
    echo "    2. 如需 CAN FD 隔离功能，请确认硬件设计支持"
    echo "    3. 日志文件: $LOG_FILE"
}

# ── 主流程 ──
main() {
    install_rs485
    install_can_fd
    install_gpio
    install_spi
    install_i2c
    install_uart
    install_modbus_rtu
    reload_udev
    print_summary
    
    echo ""
    echo "=========================================="
    echo "  外设一键安装完成!"
    echo "  日志: $LOG_FILE"
    echo "=========================================="
}

main
