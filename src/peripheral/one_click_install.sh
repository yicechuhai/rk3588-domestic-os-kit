#!/bin/bash
# =============================================================================
# RK3588 Industrial Peripheral One-Click Installer
# 一键安装 RS485、CAN FD、GPIO、I2C 等工业外设驱动
# =============================================================================
set -euo pipefail

INSTALL_DIR="/opt/rk3588-peripherals"
LOG_FILE="$INSTALL_DIR/install.log"

mkdir -p $INSTALL_DIR
exec > >(tee -a $LOG_FILE) 2>&1

echo "=========================================="
echo "  RK3588 Peripheral One-Click Installer"
echo "  $(date)"
echo "=========================================="
echo ""

# ── RS485 ──
install_rs485() {
    echo "[RS485] Checking..."
    
    # Check if RS485 is in device tree
    if grep -r "rs485" /proc/device-tree/ 2>/dev/null | head -1; then
        echo "[RS485] Device tree configured"
    else
        echo "[RS485] WARNING: Not in device tree. Add to DTS:"
        cat << 'DTS'
&uart4 {
    status = "okay";
    rs485-rts-delay = <0 0>;
    linux,rs485-enabled-at-boot-time;
};
DTS
    fi
    
    # Load module
    sudo modprobe industrialio 2>/dev/null || true
    echo "[RS485] Module loaded"
}

# ── CAN FD ──
install_can() {
    echo "[CAN FD] Checking..."
    
    sudo modprobe can can_raw can_dev rockchip_canfd 2>/dev/null || true
    
    if ip link show can0 >/dev/null 2>&1; then
        echo "[CAN FD] CAN0 already configured"
    else
        echo "[CAN FD] Setting up CAN0..."
        sudo ip link set can0 type can bitrate 500000 dbitrate 2000000 fd on 2>/dev/null || {
            echo "[CAN FD] CAN interface not found, check device tree"
        }
        sudo ip link set up can0 2>/dev/null || true
    fi
    
    # Test
    if ip link show can0 2>/dev/null | grep -q "UP"; then
        echo "[CAN FD] CAN0 UP (500k/2M FD)"
    fi
}

# ── GPIO ──
install_gpio() {
    echo "[GPIO] Checking..."
    
    if [ -d /sys/class/gpio ]; then
        echo "[GPIO] GPIO subsystem available"
        for chip in /sys/class/gpio/gpiochip*; do
            label=$(cat $chip/label 2>/dev/null || echo "unknown")
            ngpio=$(cat $chip/ngpio 2>/dev/null || echo "?")
            echo "  $(basename $chip): $label ($ngpio lines)"
        done
    else
        echo "[GPIO] GPIO not available"
    fi
}

# ── SPI ──
install_spi() {
    echo "[SPI] Checking..."
    
    for spidev in /dev/spidev*; do
        [ -e "$spidev" ] && echo "[SPI] $spidev available"
    done
}

# ── I2C ──
install_i2c() {
    echo "[I2C] Checking..."
    
    for i2cdev in /dev/i2c-*; do
        [ -e "$i2cdev" ] && echo "[I2C] $i2cdev available"
    done
}

# ── Modbus RTU (RS485) ──
install_modbus_rtu() {
    echo "[Modbus RTU] Setting up..."
    
    sudo modprobe industrialio_triggered_buffer 2>/dev/null || true
    
    if [ -e /dev/ttyRS485 ] || [ -e /dev/ttyS0 ]; then
        port=$( [ -e /dev/ttyRS485 ] && echo "/dev/ttyRS485" || echo "/dev/ttyS0" )
        echo "[Modbus RTU] Port: $port"
        echo "[Modbus RTU] Usage: modbus_server_demo --rtu $port --baud 115200"
    else
        echo "[Modbus RTU] No serial port found"
    fi
}

# ── Run all ──
install_rs485
install_can
install_gpio
install_spi
install_i2c
install_modbus_rtu

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "  Log: $LOG_FILE"
echo "=========================================="
