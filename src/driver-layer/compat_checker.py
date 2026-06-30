#!/usr/bin/env python3
"""
RK3588 Domestic OS Driver Compatibility Checker
Checks hardware compatibility with KylinOS/UOS and generates fix scripts.
"""
import os, sys, json, subprocess, time, platform
from collections import OrderedDict
from datetime import datetime
from pathlib import Path

class DriverChecker:
    def __init__(self):
        self.timestamp = datetime.now().isoformat()
        self.results = {
            "board": "",
            "kernel": "",
            "arch": platform.machine(),
            "drivers": [],
            "issues": [],
            "score": 100,
            "compatibility_matrix": {},
            "peripheral_details": {}
        }
    
    def check_system(self):
        self.results["board"] = subprocess.getoutput("cat /proc/device-tree/model 2>/dev/null").strip('\x00')
        self.results["kernel"] = os.uname().release
        self.results["hostname"] = platform.node()
        self.results["timestamp"] = self.timestamp
    
    def check_drivers(self):
        """Check critical industrial drivers with extended peripheral detection"""
        drivers = {
            "rknn_npu": {"path": "/dev/dri/renderD129", "critical": True, "category": "AI"},
            "rga": {"path": "/dev/rga", "critical": False, "lib": "librga.so", "category": "Multimedia"},
            "mpp": {"path": "/dev/mpp_service", "critical": False, "lib": "librockchip_mpp.so", "category": "Multimedia"},
            "can_fd": {"path": "/sys/class/net/can0", "critical": False, "category": "Industrial"},
            "can1": {"path": "/sys/class/net/can1", "critical": False, "category": "Industrial"},
            "rs485": {"path": "/dev/ttyRS485", "critical": False, "check_dts": "rs485", "category": "Industrial"},
            "uart0": {"path": "/dev/ttyS0", "critical": True, "category": "Serial"},
            "uart1": {"path": "/dev/ttyS1", "critical": False, "category": "Serial"},
            "uart2": {"path": "/dev/ttyS2", "critical": False, "category": "Serial"},
            "i2c0": {"path": "/dev/i2c-0", "critical": False, "category": "Bus"},
            "i2c1": {"path": "/dev/i2c-1", "critical": False, "category": "Bus"},
            "i2c2": {"path": "/dev/i2c-2", "critical": False, "category": "Bus"},
            "spi0": {"path": "/dev/spidev0.0", "critical": False, "category": "Bus"},
            "spi1": {"path": "/dev/spidev0.1", "critical": False, "category": "Bus"},
            "gpio": {"path": "/sys/class/gpio", "critical": True, "category": "GPIO"},
            "gpiochip0": {"path": "/sys/class/gpio/gpiochip0", "critical": False, "category": "GPIO"},
            "gpiochip1": {"path": "/sys/class/gpio/gpiochip1", "critical": False, "category": "GPIO"},
            "pcie": {"path": "/sys/bus/pci", "critical": False, "category": "Bus"},
            "ethernet": {"path": "/sys/class/net/eth0", "critical": False, "category": "Network"},
            "ethernet1": {"path": "/sys/class/net/eth1", "critical": False, "category": "Network"},
            "usb3": {"path": "/sys/bus/usb/devices/usb3", "critical": False, "category": "Bus"},
            "hdmi": {"path": "/sys/class/drm/card0-HDMI-A-1", "critical": False, "category": "Display"},
            "dp": {"path": "/sys/class/drm/card0-DP-1", "critical": False, "category": "Display"},
            "hwrng": {"path": "/dev/hwrng", "critical": False, "category": "Security"},
            "crypto": {"path": "/dev/crypto", "critical": False, "category": "Security"},
            "watchdog": {"path": "/dev/watchdog", "critical": False, "category": "System"},
            "rtc": {"path": "/dev/rtc0", "critical": False, "category": "System"},
            "dma": {"path": "/sys/class/dma", "critical": False, "category": "System"},
            "mailbox": {"path": "/sys/class/mailbox", "critical": False, "category": "IPC"},
        }
        
        categories = {}
        
        for name, info in drivers.items():
            path = info["path"]
            cat = info.get("category", "Other")
            
            status = "OK"
            if os.path.exists(path):
                if name.startswith("gpiochip"):
                    try:
                        ngpio = int(subprocess.getoutput(f"cat {path}/ngpio 2>/dev/null").strip() or "0")
                        if ngpio == 0:
                            status = "NO_LINES"
                    except:
                        status = "ERROR"
                elif name.startswith("ethernet"):
                    try:
                        operstate = subprocess.getoutput(f"cat {path}/operstate 2>/dev/null").strip()
                        if operstate == "down":
                            status = "LINK_DOWN"
                    except:
                        pass
                elif name.startswith("can"):
                    try:
                        flags = subprocess.getoutput(f"cat {path}/flags 2>/dev/null").strip()
                        if flags == "0x1003":
                            status = "DOWN"
                    except:
                        pass
            else:
                status = "MISSING"
                if info.get("check_dts"):
                    dts_check = subprocess.getoutput(f"grep -r '{info['check_dts']}' /proc/device-tree/ 2>/dev/null")
                    if dts_check:
                        status = "DTS_OK_NO_DRIVER"
            
            if info.get("lib"):
                lib_path = subprocess.getoutput(f"ldconfig -p | grep {info['lib']}")
                if not lib_path:
                    status = "LIB_MISSING" if status == "OK" else "MISSING"
            
            entry = {
                "name": name,
                "status": status,
                "critical": info.get("critical", False),
                "path": path,
                "category": cat
            }
            self.results["drivers"].append(entry)
            
            if cat not in categories:
                categories[cat] = {"total": 0, "ok": 0}
            categories[cat]["total"] += 1
            if status == "OK":
                categories[cat]["ok"] += 1
            
            if status != "OK" and info.get("critical"):
                self.results["score"] -= 15
                self.results["issues"].append(f"[CRITICAL] {name}: {status}")
            elif status != "OK":
                self.results["score"] -= 5
                self.results["issues"].append(f"[WARNING] {name}: {status}")
        
        self.results["peripheral_details"] = {
            cat: {
                "total": v["total"],
                "ok": v["ok"],
                "ratio": round(100 * v["ok"] / v["total"], 1) if v["total"] else 0
            }
            for cat, v in categories.items()
        }
    
    def check_domestic_os(self):
        """Check for domestic OS compatibility markers"""
        markers = {
            "uos": ["/etc/uos-release", "/usr/share/uos/"],
            "kylin": ["/etc/kylin-release", "/usr/share/kylin/"],
            "deepin": ["/etc/deepin-version", "/usr/share/deepin/"],
            "openkylin": ["/etc/openkylin-release", "/usr/share/openkylin/"],
            "euler": ["/etc/euleros-release", "/usr/share/euleros/"],
        }
        
        detected = []
        for os_name, paths in markers.items():
            if any(os.path.exists(p) for p in paths):
                detected.append(os_name)
        
        self.results["domestic_os"] = detected if detected else ["standard_linux"]
    
    def _build_compatibility_matrix(self):
        """Build a compatibility matrix across detected OS types and peripheral categories"""
        os_list = self.results.get("domestic_os", ["standard_linux"])
        categories = set(d["category"] for d in self.results["drivers"])
        
        matrix = {}
        for cat in sorted(categories):
            cat_drivers = [d for d in self.results["drivers"] if d["category"] == cat]
            total = len(cat_drivers)
            ok = sum(1 for d in cat_drivers if d["status"] == "OK")
            missing = sum(1 for d in cat_drivers if d["status"] != "OK")
            
            matrix[cat] = {
                "total_devices": total,
                "available": ok,
                "missing": missing,
                "compatibility_pct": round(100 * ok / total, 1) if total else 0,
                "status": "COMPATIBLE" if ok == total else "PARTIAL" if ok > 0 else "INCOMPATIBLE",
                "devices": [
                    {"name": d["name"], "status": d["status"], "critical": d["critical"]}
                    for d in cat_drivers
                ]
            }
        
        self.results["compatibility_matrix"] = {
            "target_os": os_list,
            "kernel": self.results["kernel"],
            "arch": self.results["arch"],
            "categories": matrix,
            "overall_compatibility": round(self.results["score"], 1)
        }
    
    def generate_report(self):
        print("=" * 60)
        print("  RK3588 Domestic OS Driver Compatibility Report")
        print("=" * 60)
        print(f"  Board:    {self.results['board']}")
        print(f"  Kernel:   {self.results['kernel']}")
        print(f"  OS Type:  {', '.join(self.results['domestic_os'])}")
        print(f"  Score:    {self.results['score']}/100")
        print()
        print("  Driver Status:")
        
        by_category = {}
        for drv in self.results["drivers"]:
            cat = drv.get("category", "Other")
            if cat not in by_category:
                by_category[cat] = []
            by_category[cat].append(drv)
        
        for cat, cat_drivers in sorted(by_category.items()):
            print(f"\n  [{cat}]")
            for drv in cat_drivers:
                icon = "✓" if drv["status"] == "OK" else "~" if "DTS_OK" in drv.get("status", "") else "✗"
                tag = "[CRIT]" if drv["critical"] else ""
                print(f"    {icon} {drv['name']:14s} {tag:7s} {drv['status']}")
        
        if self.results["issues"]:
            print(f"\n  Issues ({len(self.results['issues'])}):")
            for issue in self.results["issues"]:
                print(f"    • {issue}")
        
        if self.results.get("peripheral_details"):
            print(f"\n  Peripheral Category Summary:")
            for cat, info in sorted(self.results["peripheral_details"].items()):
                bar = "█" * int(info["ratio"] / 10) + "░" * (10 - int(info["ratio"] / 10))
                print(f"    {cat:14s} [{bar}] {info['ok']}/{info['total']} ({info['ratio']}%)")
        
        print("=" * 60)
        
        if self.results["issues"]:
            self._generate_fix_script()
        
        self._build_compatibility_matrix()
        matrix_path = "/tmp/rk3588_compat_matrix.json"
        with open(matrix_path, "w", encoding="utf-8") as f:
            json.dump(self.results["compatibility_matrix"], f, indent=2, ensure_ascii=False)
        print(f"\n  Compatibility Matrix: {matrix_path}")
        
        return self.results["compatibility_matrix"]
    
    def _generate_fix_script(self):
        script = ("#!/bin/bash\n"
                  "# Auto-generated driver fix script for Domestic OS on RK3588\n"
                  f"# Generated: {self.timestamp}\n"
                  "set -euo pipefail\n\n"
                  "LOG_FILE=\"/var/log/rk3588_driver_fix.log\"\n"
                  "exec > >(tee -a \"$LOG_FILE\") 2>&1\n\n")
        
        for drv in self.results["drivers"]:
            if drv["status"] == "MISSING" and drv["name"] == "rknn_npu":
                script += """
echo "Installing RK3588 NPU driver..."
sudo apt-get install -y rockchip-multimedia-config 2>/dev/null || true
sudo modprobe rknpu 2>/dev/null || echo "NPU module may need kernel rebuild"
"""
            elif drv["status"] == "MISSING" and drv["name"] == "can_fd":
                script += """
echo "Enabling CAN FD interface..."
sudo modprobe can can_raw can_dev rockchip_canfd 2>/dev/null || true
sudo ip link set can0 type can bitrate 500000 2>/dev/null
sudo ip link set up can0 2>/dev/null || true
"""
            elif drv["status"] == "MISSING" and drv["name"] == "can1":
                script += """
echo "Enabling CAN1 interface..."
sudo ip link set can1 type can bitrate 500000 2>/dev/null || true
sudo ip link set up can1 2>/dev/null || echo "CAN1 not available"
"""
            elif drv["status"] == "MISSING" and drv["name"].startswith("uart"):
                script += """
echo "Checking UART availability..."
for uart in /dev/ttyS*; do
    [ -e "$uart" ] && echo "  Found: $uart"
done
"""
            elif drv["status"] == "MISSING" and drv["name"].startswith("i2c"):
                script += """
echo "Enabling I2C subsystem..."
sudo modprobe i2c-dev i2c-rk3x 2>/dev/null || true
"""
            elif drv["status"] == "MISSING" and drv["name"].startswith("spi"):
                script += """
echo "Enabling SPI subsystem..."
sudo modprobe spidev rockchip-spi 2>/dev/null || true
"""
            elif drv["status"] == "MISSING" and drv["name"].startswith("gpiochip"):
                script += """
echo "Enabling GPIO subsystem..."
sudo modprobe gpio-sysfs 2>/dev/null || true
"""
            elif drv["status"] == "LIB_MISSING":
                script += (f"\necho \"Installing {drv['name']} library...\"\n"
                           f"sudo apt-get install -y lib{drv['name']}-dev 2>/dev/null || echo \"Manual install needed\"\n")
        
        script += '\necho "Fix script complete. Reboot recommended for kernel module changes."\n'
        script += 'echo "Log saved to: $LOG_FILE"\n'
        
        fix_path = "/tmp/rk3588_domestic_os_fix.sh"
        with open(fix_path, "w", encoding="utf-8") as f:
            f.write(script)
        os.chmod(fix_path, 0o755)
        print(f"\n  Fix script: {fix_path}")
    
    def run(self):
        self.check_system()
        self.check_domestic_os()
        self.check_drivers()
        return self.generate_report()

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="RK3588 Driver Compatibility Checker")
    ap.add_argument("--json", action="store_true", help="Output JSON only (for CI/CD)")
    ap.add_argument("--matrix", action="store_true", help="Output only compatibility matrix JSON")
    args = ap.parse_args()
    
    checker = DriverChecker()
    checker.check_system()
    checker.check_domestic_os()
    checker.check_drivers()
    checker._build_compatibility_matrix()
    
    if args.matrix:
        print(json.dumps(checker.results["compatibility_matrix"], indent=2, ensure_ascii=False))
        sys.exit(0)
    elif args.json:
        print(json.dumps(checker.results, indent=2, ensure_ascii=False))
        sys.exit(0)
    else:
        checker.generate_report()
