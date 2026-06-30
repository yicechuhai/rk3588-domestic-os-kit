#!/usr/bin/env python3
"""
RK3588 Domestic OS Driver Compatibility Checker
Checks hardware compatibility with KylinOS/UOS and generates fix scripts.
"""
import os, sys, json, subprocess
from pathlib import Path

class DriverChecker:
    def __init__(self):
        self.results = {
            "board": "",
            "kernel": "",
            "drivers": [],
            "issues": [],
            "score": 100
        }
    
    def check_system(self):
        self.results["board"] = subprocess.getoutput("cat /proc/device-tree/model 2>/dev/null").strip('\x00')
        self.results["kernel"] = os.uname().release
    
    def check_drivers(self):
        """Check critical industrial drivers"""
        drivers = {
            "rknn_npu": {"path": "/dev/dri/renderD129", "critical": True},
            "rga": {"path": "/dev/rga", "critical": False, "lib": "librga.so"},
            "mpp": {"path": "/dev/mpp_service", "critical": False, "lib": "librockchip_mpp.so"},
            "can": {"path": "/sys/class/net/can0", "critical": False},
            "rs485": {"path": "/dev/ttyRS485", "critical": False, "check_dts": "rs485"},
            "uart": {"path": "/dev/ttyS0", "critical": True},
            "i2c": {"path": "/dev/i2c-0", "critical": False},
            "spi": {"path": "/dev/spidev0.0", "critical": False},
            "gpio": {"path": "/sys/class/gpio", "critical": True},
            "pcie": {"path": "/sys/bus/pci", "critical": False},
        }
        
        for name, info in drivers.items():
            path = info["path"]
            status = "OK" if os.path.exists(path) else "MISSING"
            
            if info.get("lib"):
                lib_path = subprocess.getoutput(f"ldconfig -p | grep {info['lib']}")
                if not lib_path:
                    status = "LIB_MISSING" if status == "OK" else "MISSING"
            
            if info.get("check_dts") and status == "MISSING":
                # Check if it's in device tree
                dts_check = subprocess.getoutput(f"grep -r '{info['check_dts']}' /proc/device-tree/ 2>/dev/null")
                if dts_check:
                    status = "DTS_OK_NO_DRIVER"
            
            self.results["drivers"].append({
                "name": name,
                "status": status,
                "critical": info.get("critical", False),
                "path": path
            })
            
            if status != "OK" and info.get("critical"):
                self.results["score"] -= 15
                self.results["issues"].append(f"[CRITICAL] {name}: {status}")
            elif status != "OK":
                self.results["score"] -= 5
                self.results["issues"].append(f"[WARNING] {name}: {status}")
    
    def check_domestic_os(self):
        """Check for domestic OS compatibility markers"""
        markers = {
            "uos": ["/etc/uos-release", "/usr/share/uos/"],
            "kylin": ["/etc/kylin-release", "/usr/share/kylin/"],
            "deepin": ["/etc/deepin-version", "/usr/share/deepin/"],
        }
        
        detected = []
        for os_name, paths in markers.items():
            if any(os.path.exists(p) for p in paths):
                detected.append(os_name)
        
        self.results["domestic_os"] = detected if detected else ["standard_linux"]
    
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
        
        for drv in self.results["drivers"]:
            icon = "✓" if drv["status"] == "OK" else "✗"
            tag = "[CRIT]" if drv["critical"] else ""
            print(f"    {icon} {drv['name']:12s} {tag:6s} {drv['status']}")
        
        if self.results["issues"]:
            print(f"\n  Issues ({len(self.results['issues'])}):")
            for issue in self.results["issues"]:
                print(f"    • {issue}")
        
        print("=" * 60)
        
        # Generate fix script
        if self.results["issues"]:
            self._generate_fix_script()
    
    def _generate_fix_script(self):
        script = "#!/bin/bash\n# Auto-generated driver fix script for Domestic OS\nset -e\n\n"
        
        for drv in self.results["drivers"]:
            if drv["status"] == "MISSING" and drv["name"] == "rknn_npu":
                script += """
# Fix NPU driver
echo "Installing RK3588 NPU driver..."
sudo apt-get install -y rockchip-multimedia-config
sudo modprobe rknpu || echo "NPU module may need kernel rebuild"
"""
            elif drv["status"] == "MISSING" and drv["name"] == "can":
                script += """
# Fix CAN driver
echo "Enabling CAN interface..."
sudo modprobe can can_raw can_dev
sudo ip link set can0 type can bitrate 500000
sudo ip link set up can0
"""
            elif drv["status"] == "LIB_MISSING":
                script += f"""
# Fix library: {drv['name']}
echo "Installing {drv['name']} library..."
sudo apt-get install -y lib{drv['name']}-dev 2>/dev/null || echo "Manual install needed"
"""
        
        script += '\necho "Fix script complete. Reboot recommended."\n'
        
        fix_path = "/tmp/rk3588_domestic_os_fix.sh"
        with open(fix_path, "w") as f:
            f.write(script)
        os.chmod(fix_path, 0o755)
        print(f"\n  Fix script: {fix_path}")
    
    def run(self):
        self.check_system()
        self.check_domestic_os()
        self.check_drivers()
        self.generate_report()

if __name__ == "__main__":
    checker = DriverChecker()
    checker.run()
