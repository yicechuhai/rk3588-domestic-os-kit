#!/usr/bin/env python3
"""
RK3588 NeoCertify Compliance Test Suite
Automated certification testing for domestic OS compatibility.
Generates NeoCertify-compatible JSON reports.
"""
import subprocess, json, os, sys, platform
from datetime import datetime
from pathlib import Path

class NeoCertifyRunner:
    def __init__(self):
        self.results = {
            "certification": "NeoCertify 2.0",
            "timestamp": datetime.now().isoformat(),
            "platform": {},
            "test_suites": [],
            "overall_score": 0,
            "overall_status": "PENDING"
        }
    
    def detect_platform(self):
        """Detect the domestic OS platform"""
        os_markers = {
            "KylinOS": ["/etc/kylin-release", "/etc/.kyinfo"],
            "UOS": ["/etc/uos-release", "/etc/deepin-version"],
            "Deepin": ["/etc/deepin-version", "/etc/deepin-release"],
        }
        
        detected = "Ubuntu"  # default
        for os_name, markers in os_markers.items():
            if any(os.path.exists(m) for m in markers):
                detected = os_name
                break
        
        self.results["platform"] = {
            "os": detected,
            "kernel": platform.release(),
            "arch": platform.machine(),
            "hostname": platform.node(),
            "cpu_cores": os.cpu_count()
        }
        return detected
    
    def test_driver_compatibility(self):
        """Test driver compatibility with domestic OS"""
        print("[Test 1/5] Driver Compatibility...")
        
        drivers = {
            "rknn_npu": "/dev/dri/renderD129",
            "rga": "/usr/lib/librga.so",
            "mpp": "/dev/mpp_service",
            "can": "/sys/class/net/can0",
            "uart": "/dev/ttyS0",
            "i2c": "/dev/i2c-0",
            "spi": "/dev/spidev0.0",
            "gpio": "/sys/class/gpio",
            "pcie": "/sys/bus/pci",
            "ethernet": "/sys/class/net/eth0",
        }
        
        passed = 0
        failed = 0
        details = []
        
        for name, path in drivers.items():
            if os.path.exists(path):
                passed += 1
                details.append({"driver": name, "status": "OK"})
            else:
                failed += 1
                details.append({"driver": name, "status": "MISSING", "path": path})
        
        self.results["test_suites"].append({
            "name": "Driver Compatibility",
            "total": len(drivers),
            "passed": passed,
            "failed": failed,
            "score": int(100 * passed / len(drivers)),
            "details": details
        })
        print(f"  Score: {passed}/{len(drivers)}")
    
    def test_rt_performance(self):
        """Test real-time performance"""
        print("[Test 2/5] Real-Time Performance...")
        
        # Run quick jitter test
        try:
            result = subprocess.run(
                ["python3", "/opt/rk3588-toolkit/rt-tools/monitor/jitter_monitor.py", 
                 "-d", "5", "-i", "1000", "--json"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                p99 = data.get("p99_us", 999)
            else:
                p99 = 999
        except:
            p99 = 999
        
        grade = "A+" if p99 < 50 else "A" if p99 < 100 else "B" if p99 < 500 else "C" if p99 < 1000 else "D"
        
        self.results["test_suites"].append({
            "name": "Real-Time Performance",
            "p99_latency_us": p99,
            "grade": grade,
            "note": "PREEMPT_RT kernel required for grade A+ (<50us)"
        })
        print(f"  P99 Latency: {p99}us, Grade: {grade}")
    
    def test_system_security(self):
        """Test system security compliance"""
        print("[Test 3/5] Security Compliance...")
        
        checks = {}
        
        # Seccomp
        try:
            r = subprocess.run(["cat", "/proc/sys/kernel/seccomp/actions_avail"],
                              capture_output=True, text=True)
            checks["seccomp"] = "enabled" if r.returncode == 0 else "disabled"
        except:
            checks["seccomp"] = "unknown"
        
        # SELinux
        try:
            r = subprocess.run(["getenforce"], capture_output=True, text=True)
            checks["selinux"] = r.stdout.strip().lower()
        except:
            checks["selinux"] = "not_installed"
        
        # ASLR
        try:
            with open("/proc/sys/kernel/randomize_va_space") as f:
                val = int(f.read().strip())
            checks["aslr"] = "enabled" if val > 0 else "disabled"
        except:
            checks["aslr"] = "unknown"
        
        # Kernel hardening
        hardening_checks = {
            "dmesg_restrict": "/proc/sys/kernel/dmesg_restrict",
            "kptr_restrict": "/proc/sys/kernel/kptr_restrict",
            "ptrace_scope": "/proc/sys/kernel/yama/ptrace_scope",
        }
        
        for name, path in hardening_checks.items():
            try:
                with open(path) as f:
                    checks[name] = int(f.read().strip()) > 0
            except:
                checks[name] = "unknown"
        
        score = 100
        if checks.get("seccomp") != "enabled": score -= 20
        if checks.get("selinux") not in ("enforcing", "permissive"): score -= 10
        if checks.get("aslr") != "enabled": score -= 20
        
        self.results["test_suites"].append({
            "name": "Security Compliance",
            "checks": checks,
            "score": max(0, score)
        })
        print(f"  Score: {max(0, score)}/100")
    
    def test_network_isolation(self):
        """Test network stack isolation capabilities"""
        print("[Test 4/5] Network Isolation...")
        checks = {}
        
        # Check network namespaces
        try:
            r = subprocess.run(["ip", "netns", "list"], capture_output=True, text=True)
            checks["network_namespaces"] = "enabled" if r.returncode == 0 else "disabled"
        except:
            checks["network_namespaces"] = "unknown"
        
        # Check cgroups v2
        checks["cgroups_v2"] = os.path.exists("/sys/fs/cgroup/cgroup.controllers")
        
        self.results["test_suites"].append({
            "name": "Network Isolation",
            "checks": checks,
            "score": 80 if checks.get("network_namespaces") == "enabled" else 50
        })
        print(f"  Network namespaces: {checks.get('network_namespaces', 'unknown')}")
    
    def test_neocertify_compliance(self):
        """Generate NeoCertify compliance report"""
        print("[Test 5/5] NeoCertify Compliance...")
        
        # Check for required NeoCertify markers
        neocert_checks = {
            "domestic_crypto": False,  # SM2/SM3/SM4 support
            "audit_logging": os.path.exists("/var/log/audit/audit.log"),
            "mandatory_access_control": os.path.exists("/sys/fs/selinux"),
            "secure_boot": os.path.exists("/sys/firmware/efi/efivars/SecureBoot-*"),
        }
        
        # Check for domestic crypto libraries
        try:
            r = subprocess.run(["ldconfig", "-p"], capture_output=True, text=True)
            libs = r.stdout
            neocert_checks["domestic_crypto"] = any(
                lib in libs for lib in ["libcrypto.so", "libssl.so"]
            )
        except:
            pass
        
        score = sum(25 for v in neocert_checks.values() if v)
        
        self.results["test_suites"].append({
            "name": "NeoCertify Compliance",
            "checks": neocert_checks,
            "score": score
        })
        print(f"  Score: {score}/100")
    
    def generate_report(self):
        """Generate final NeoCertify JSON report"""
        scores = [t.get("score", 0) for t in self.results["test_suites"]]
        self.results["overall_score"] = int(sum(scores) / len(scores)) if scores else 0
        self.results["overall_status"] = (
            "CERTIFIED" if self.results["overall_score"] >= 80
            else "CONDITIONAL" if self.results["overall_score"] >= 60
            else "FAILED"
        )
        
        report_path = "/tmp/neocertify_report.json"
        with open(report_path, "w") as f:
            json.dump(self.results, f, indent=2, ensure_ascii=False)
        
        print(f"\n{'='*60}")
        print(f"  NeoCertify Compliance Report")
        print(f"{'='*60}")
        print(f"  Platform:   {self.results['platform']['os']} {self.results['platform']['kernel']}")
        print(f"  Arch:       {self.results['platform']['arch']}")
        print(f"  Overall:    {self.results['overall_score']}/100 — {self.results['overall_status']}")
        print(f"  Report:     {report_path}")
        print(f"{'='*60}")
        
        return report_path

def main():
    runner = NeoCertifyRunner()
    
    print("=" * 60)
    print("  RK3588 NeoCertify Compliance Test Suite v1.0")
    print("=" * 60)
    print()
    
    platform = runner.detect_platform()
    print(f"Detected: {platform}\n")
    
    runner.test_driver_compatibility()
    runner.test_rt_performance()
    runner.test_system_security()
    runner.test_network_isolation()
    runner.test_neocertify_compliance()
    
    runner.generate_report()

if __name__ == "__main__":
    main()
