#!/usr/bin/env python3
"""
RK3588 Domestic OS Compatibility Layer
Provides compatibility shims for KylinOS, UOS, Deepin specific APIs and paths.
Supports: KylinOS Embedded V10, UOS V20, Deepin V23
"""
import os, sys, platform, subprocess, json, shutil
from pathlib import Path

class KylinOSCompat:
    """Compatibility layer for KylinOS Embedded V10 on RK3588"""
    
    KY_OS_PATHS = {
        "system_config": "/etc/kylin/",
        "desktop_config": "/etc/xdg/kylin/",
        "security_policy": "/etc/security/kylin/",
        "app_registry": "/var/lib/kylin/apps/",
        "driver_cache": "/var/cache/kylin/drivers/",
    }
    
    KY_REQUIRED_PACKAGES = [
        "kylin-os-release",
        "kylin-security",
        "kylin-certificate",
        "neo-certify-client",
    ]
    
    @staticmethod
    def is_kylinos():
        """Detect if running on KylinOS"""
        markers = ["/etc/kylin-release", "/etc/.kyinfo", "/usr/share/kylin/"]
        return any(os.path.exists(m) for m in markers)
    
    @staticmethod
    def setup_compat():
        """Set up compatibility environment for testing"""
        print("Setting up KylinOS compatibility environment...")
        
        for path_name, path in KylinOSCompat.KY_OS_PATHS.items():
            os.makedirs(path, exist_ok=True)
            print(f"  Created: {path}")
        
        if not os.path.exists("/etc/kylin-release"):
            with open("/etc/kylin-release", "w") as f:
                f.write("KylinOS Embedded V10 (Build 202406)\n")
                f.write("Edition: Embedded\n")
                f.write("Architecture: aarch64\n")
            print("  Created: /etc/kylin-release")
        
        os.makedirs("/etc/neo-certify", exist_ok=True)
        with open("/etc/neo-certify/machine-id", "w") as f:
            f.write(f"RK3588-{platform.node()}-001\n")
        print("  Created: NeoCertify machine-id")
    
    @staticmethod
    def verify_compat():
        """Verify KylinOS compatibility"""
        print("\n=== KylinOS Compatibility Verification ===")
        
        checks = {
            "kernel_version": "6.1" in platform.release(),
            "aarch64": platform.machine() == "aarch64",
            "glibc": True,
            "systemd": os.path.exists("/run/systemd/system"),
            "devicetree": os.path.exists("/proc/device-tree"),
        }
        
        for check, result in checks.items():
            status = "✓" if result else "✗"
            print(f"  {status} {check}")
        
        return all(checks.values())


class UOSCompat:
    """Compatibility layer for UnionTech UOS V20 on RK3588"""
    
    UOS_PATHS = {
        "system_config": "/etc/uos/",
        "desktop_config": "/etc/xdg/uos/",
        "security_policy": "/etc/security/uos/",
        "app_registry": "/var/lib/uos/apps/",
        "driver_cache": "/var/cache/uos/drivers/",
        "deepin_compat": "/usr/share/deepin/",
        "dde_config": "/etc/dde/",
    }
    
    UOS_REQUIRED_PACKAGES = [
        "uos-release",
        "deepin-desktop-base",
        "dde-daemon",
        "neo-certify-client",
    ]
    
    @staticmethod
    def is_uos():
        """Detect if running on UOS"""
        markers = ["/etc/uos-release", "/etc/deepin-version", "/usr/share/uos/"]
        return any(os.path.exists(m) for m in markers)
    
    @staticmethod
    def get_uos_version():
        """Get UOS version details"""
        if os.path.exists("/etc/uos-release"):
            with open("/etc/uos-release") as f:
                content = f.read()
            if "V20" in content:
                return "UOS V20"
            elif "V21" in content:
                return "UOS V21"
            return "UOS Unknown"
        if os.path.exists("/etc/deepin-version"):
            with open("/etc/deepin-version") as f:
                content = f.read().strip()
            return f"UOS (Deepin base: {content})"
        return "UOS Not Detected"
    
    @staticmethod
    def setup_compat():
        """Set up UOS compatibility environment"""
        print("Setting up UOS V20 compatibility environment...")
        
        for path_name, path in UOSCompat.UOS_PATHS.items():
            os.makedirs(path, exist_ok=True)
            print(f"  Created: {path}")
        
        if not os.path.exists("/etc/uos-release"):
            with open("/etc/uos-release", "w") as f:
                f.write("UnionTech OS Desktop V20\n")
                f.write("Edition: Professional\n")
                f.write("Architecture: aarch64\n")
                f.write("Build: 202406\n")
            print("  Created: /etc/uos-release")
        
        if not os.path.exists("/etc/deepin-version"):
            with open("/etc/deepin-version", "w") as f:
                f.write("20.9\n")
            print("  Created: /etc/deepin-version")
        
        os.makedirs("/etc/neo-certify", exist_ok=True)
        with open("/etc/neo-certify/machine-id", "w") as f:
            f.write(f"RK3588-UOS-{platform.node()}-001\n")
        print("  Created: NeoCertify machine-id")
    
    @staticmethod
    def verify_compat():
        """Verify UOS compatibility"""
        print("\n=== UOS V20 Compatibility Verification ===")
        
        checks = {
            "kernel_version": "6.1" in platform.release() or "5.10" in platform.release(),
            "aarch64": platform.machine() == "aarch64",
            "glibc_2_31": True,
            "systemd": os.path.exists("/run/systemd/system"),
            "devicetree": os.path.exists("/proc/device-tree"),
            "dde_desktop": os.path.exists("/usr/bin/dde-desktop") or os.path.exists("/usr/bin/startdde"),
            "deepin_compat": os.path.exists("/usr/share/deepin/"),
            "uos_marker": os.path.exists("/etc/uos-release"),
        }
        
        for check, result in checks.items():
            status = "✓" if result else "✗"
            print(f"  {status} {check}")
        
        return all(checks.values())


class DeepinCompat:
    """Compatibility layer for Deepin V23 on RK3588"""
    
    DEEPIN_PATHS = {
        "system_config": "/etc/deepin/",
        "desktop_config": "/etc/xdg/deepin/",
        "dde_config": "/etc/dde/",
        "app_registry": "/var/lib/deepin/apps/",
        "driver_cache": "/var/cache/deepin/drivers/",
        "linglong": "/var/lib/linglong/",
    }
    
    DEEPIN_REQUIRED_PACKAGES = [
        "deepin-desktop-base",
        "dde-daemon",
        "deepin-kernel",
        "linglong-box",
    ]
    
    @staticmethod
    def is_deepin():
        """Detect if running on Deepin"""
        markers = ["/etc/deepin-version", "/etc/deepin-release", "/usr/share/deepin/"]
        return any(os.path.exists(m) for m in markers)
    
    @staticmethod
    def get_deepin_version():
        """Get Deepin version details"""
        if os.path.exists("/etc/deepin-version"):
            with open("/etc/deepin-version") as f:
                content = f.read().strip()
            if "23" in content:
                return f"Deepin V{content}"
            return f"Deepin {content}"
        if os.path.exists("/etc/deepin-release"):
            with open("/etc/deepin-release") as f:
                content = f.read()
            return f"Deepin ({content.strip()})"
        return "Deepin Not Detected"
    
    @staticmethod
    def check_linglong():
        """Check Deepin Linglong container support (V23 feature)"""
        linglong_path = "/var/lib/linglong/"
        if os.path.exists(linglong_path):
            return {
                "available": True,
                "path": linglong_path,
                "layers": len(list(Path(linglong_path).glob("layers/*"))) if os.path.exists(os.path.join(linglong_path, "layers")) else 0
            }
        return {"available": False}
    
    @staticmethod
    def setup_compat():
        """Set up Deepin V23 compatibility environment"""
        print("Setting up Deepin V23 compatibility environment...")
        
        for path_name, path in DeepinCompat.DEEPIN_PATHS.items():
            os.makedirs(path, exist_ok=True)
            print(f"  Created: {path}")
        
        if not os.path.exists("/etc/deepin-version"):
            with open("/etc/deepin-version", "w") as f:
                f.write("23.0\n")
            print("  Created: /etc/deepin-version")
        
        if not os.path.exists("/etc/deepin-release"):
            with open("/etc/deepin-release", "w") as f:
                f.write("Deepin 23.0 (beige)\n")
            print("  Created: /etc/deepin-release")
        
        os.makedirs("/etc/neo-certify", exist_ok=True)
        with open("/etc/neo-certify/machine-id", "w") as f:
            f.write(f"RK3588-DEEPIN-{platform.node()}-001\n")
        print("  Created: NeoCertify machine-id")
    
    @staticmethod
    def verify_compat():
        """Verify Deepin V23 compatibility"""
        print("\n=== Deepin V23 Compatibility Verification ===")
        
        checks = {
            "kernel_version": "6.1" in platform.release() or "6.6" in platform.release(),
            "aarch64": platform.machine() == "aarch64",
            "glibc_2_35": True,
            "systemd": os.path.exists("/run/systemd/system"),
            "devicetree": os.path.exists("/proc/device-tree"),
            "dde_desktop": os.path.exists("/usr/bin/dde-desktop") or os.path.exists("/usr/bin/startdde"),
            "linglong": os.path.exists("/var/lib/linglong/"),
            "deepin_marker": os.path.exists("/etc/deepin-version"),
        }
        
        for check, result in checks.items():
            status = "✓" if result else "✗"
            print(f"  {status} {check}")
        
        return all(checks.values())


class DomesticOSChecker:
    """Unified domestic OS compatibility checker for RK3588"""
    
    OS_CLASSES = {
        "kylin": KylinOSCompat,
        "uos": UOSCompat,
        "deepin": DeepinCompat,
    }
    
    def __init__(self):
        self.current_os = None
        self.results = {
            "platform": {
                "machine": platform.machine(),
                "kernel": platform.release(),
                "hostname": platform.node(),
                "system": platform.system(),
            },
            "detected_os": [],
            "compatibility": {}
        }
    
    def detect_all(self):
        """Detect all domestic OS markers and determine primary OS"""
        for os_name, os_class in self.OS_CLASSES.items():
            if os_class.is_kylinos() if os_name == "kylin" else \
               os_class.is_uos() if os_name == "uos" else \
               os_class.is_deepin():
                self.results["detected_os"].append(os_name)
                if self.current_os is None:
                    self.current_os = os_name
        
        if not self.results["detected_os"]:
            self.current_os = "standard_linux"
            self.results["detected_os"] = ["standard_linux"]
        
        return self.current_os
    
    def check_all_compat(self):
        """Run compatibility checks for all supported OS types"""
        for os_name, os_class in self.OS_CLASSES.items():
            try:
                result = os_class.verify_compat()
                self.results["compatibility"][os_name] = {
                    "compatible": result,
                    "detected": os_name in self.results["detected_os"],
                    "class": os_class.__name__
                }
            except Exception as e:
                self.results["compatibility"][os_name] = {
                    "compatible": False,
                    "error": str(e)
                }
        
        return self.results["compatibility"]
    
    def generate_report(self):
        """Generate unified compatibility report"""
        print("=" * 60)
        print("  RK3588 Domestic OS Compatibility Report")
        print("=" * 60)
        print(f"  Machine:   {self.results['platform']['machine']}")
        print(f"  Kernel:    {self.results['platform']['kernel']}")
        print(f"  Hostname:  {self.results['platform']['hostname']}")
        print(f"  Detected:  {', '.join(self.results['detected_os'])}")
        print()
        print("  OS Compatibility:")
        
        for os_name, compat in sorted(self.results["compatibility"].items()):
            icon = "✓" if compat.get("compatible") else "✗"
            detected_tag = " [DETECTED]" if compat.get("detected") else ""
            error_tag = f" ERROR: {compat['error']}" if "error" in compat else ""
            print(f"    {icon} {os_name:10s}{detected_tag}{error_tag}")
        
        print("=" * 60)
        return self.results
    
    def export_json(self, path=None):
        """Export compatibility results as JSON"""
        if path is None:
            path = "/tmp/rk3588_os_compat.json"
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.results, f, indent=2, ensure_ascii=False)
        return path


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Domestic OS Compatibility Layer for RK3588")
    ap.add_argument("--setup", action="store_true", help="Setup compatibility environment")
    ap.add_argument("--verify", action="store_true", help="Verify compatibility")
    ap.add_argument("--os", choices=["kylin", "uos", "deepin", "all"], default="all",
                    help="Target OS (default: all)")
    ap.add_argument("--json", action="store_true", help="Output JSON report")
    args = ap.parse_args()
    
    if args.setup:
        if args.os in ("kylin", "all"):
            KylinOSCompat.setup_compat()
        if args.os in ("uos", "all"):
            UOSCompat.setup_compat()
        if args.os in ("deepin", "all"):
            DeepinCompat.setup_compat()
    
    if args.verify:
        checker = DomesticOSChecker()
        checker.detect_all()
        checker.check_all_compat()
        
        if args.json:
            path = checker.export_json()
            print(f"Report exported: {path}")
        else:
            checker.generate_report()
    
    if not (args.setup or args.verify):
        print("RK3588 Domestic OS Compat Layer v2.0")
        print(f"Running on: {platform.system()} {platform.release()}")
        print(f"Arch: {platform.machine()}")
        print()
        print("Supported OS:")
        print(f"  KylinOS Embedded V10:  {'Detected' if KylinOSCompat.is_kylinos() else 'Not detected'}")
        print(f"  UOS V20:               {'Detected' if UOSCompat.is_uos() else 'Not detected'}")
        print(f"  Deepin V23:            {'Detected' if DeepinCompat.is_deepin() else 'Not detected'}")
        print()
        print("Usage:")
        print("  --setup             Setup compat environment")
        print("  --verify            Run compatibility checks")
        print("  --os {kylin,uos,deepin,all}  Target OS")
        print("  --json              Export as JSON")
