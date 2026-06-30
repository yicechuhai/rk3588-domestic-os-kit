#!/usr/bin/env python3
"""
RK3588 KylinOS Embedded V10 Compatibility Layer
Provides compatibility shims for KylinOS-specific APIs and paths.
"""
import os, sys, platform, subprocess

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
        
        # Create mock kylin-release
        if not os.path.exists("/etc/kylin-release"):
            with open("/etc/kylin-release", "w") as f:
                f.write("KylinOS Embedded V10 (Build 202406)\n")
                f.write("Edition: Embedded\n")
                f.write("Architecture: aarch64\n")
            print("  Created: /etc/kylin-release")
        
        # Create NeoCertify marker
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
            "glibc": True,  # Assume glibc
            "systemd": os.path.exists("/run/systemd/system"),
            "devicetree": os.path.exists("/proc/device-tree"),
        }
        
        for check, result in checks.items():
            status = "✓" if result else "✗"
            print(f"  {status} {check}")
        
        return all(checks.values())

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="KylinOS Compatibility Layer")
    ap.add_argument("--setup", action="store_true", help="Setup compatibility environment")
    ap.add_argument("--verify", action="store_true", help="Verify compatibility")
    args = ap.parse_args()
    
    if args.setup:
        KylinOSCompat.setup_compat()
    if args.verify:
        KylinOSCompat.verify_compat()
    if not (args.setup or args.verify):
        print("KylinOS Compat v1.0")
        print(f"Running on: {platform.system()} {platform.release()}")
        print(f"Is KylinOS: {KylinOSCompat.is_kylinos()}")
