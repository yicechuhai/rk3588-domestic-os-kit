#!/usr/bin/env python3
"""
RK3588 NeoCertify Certification Report Generator
Reads neocertify_report.json and generates certification reports.
Supports: Text, JSON, HTML, and PDF-in-structure formats.
"""
import json, os, sys, argparse
from datetime import datetime
from pathlib import Path

TEMPLATE_DIR = Path(__file__).parent / "templates"
REPORT_DIR = Path("/tmp/neocertify_reports")

class CertReportGenerator:
    """Generate NeoCertify certification reports from test results"""
    
    def __init__(self, report_json=None):
        self.report_json = report_json or "/tmp/neocertify_report.json"
        self.data = {}
        self._load_data()
    
    def _load_data(self):
        """Load certification test results"""
        if os.path.exists(self.report_json):
            with open(self.report_json, "r", encoding="utf-8") as f:
                self.data = json.load(f)
        else:
            self.data = {
                "error": f"Report not found: {self.report_json}",
                "hint": "Run neocertify_runner.py first to generate test data"
            }
    
    def generate_text(self, output_path=None):
        """Generate plain text certification report"""
        if "error" in self.data:
            return self.data["error"]
        
        lines = []
        lines.append("=" * 70)
        lines.append("  RK3588 NeoCertify 认证报告")
        lines.append("  NeoCertify Certification Report v2.0")
        lines.append("=" * 70)
        lines.append(f"  生成时间:     {self.data.get('timestamp', 'N/A')}")
        lines.append(f"  认证编号:     {self.data.get('certification_id', 'N/A')}")
        lines.append("")
        lines.append(f"  平台信息:")
        plat = self.data.get("platform", {})
        lines.append(f"    操作系统:   {plat.get('os', 'N/A')}")
        lines.append(f"    内核版本:   {plat.get('kernel', 'N/A')}")
        lines.append(f"    CPU架构:    {plat.get('arch', 'N/A')}")
        lines.append(f"    CPU核心数:  {plat.get('cpu_cores', 'N/A')}")
        lines.append(f"    主机名:     {plat.get('hostname', 'N/A')}")
        lines.append("")
        lines.append("-" * 70)
        lines.append("  测试套件结果:")
        lines.append("-" * 70)
        
        suite_num = 1
        for suite in self.data.get("test_suites", []):
            name = suite.get("name", "Unknown")
            score = suite.get("score", 0)
            status = suite.get("status", "N/A")
            bar = self._score_bar(score)
            lines.append(f"  {suite_num:2d}. {name}")
            lines.append(f"      得分: {score}/100 {bar} 状态: {status}")
            
            # Show key details per suite
            if "checks" in suite:
                for check_name, check_val in suite["checks"].items():
                    if isinstance(check_val, dict):
                        continue
                    icon = "✓" if check_val else "✗"
                    lines.append(f"         {icon} {check_name}: {check_val}")
            elif "total" in suite and "passed" in suite:
                total = suite.get("total", 0)
                passed = suite.get("passed", 0)
                failed = suite.get("failed", 0)
                lines.append(f"         通过: {passed}/{total}  失败: {failed}")
            suite_num += 1
        
        lines.append("")
        lines.append("=" * 70)
        lines.append(f"  综合评分: {self.data.get('overall_score', 0)}/100")
        lines.append(f"  认证状态: {self.data.get('overall_status', 'PENDING')}")
        lines.append(f"  认证等级: {self.data.get('certification_level', 'N/A')}")
        lines.append("=" * 70)
        
        # Add certification seal (ASCII art)
        if self.data.get("overall_status") == "CERTIFIED":
            lines.append("")
            lines.append("    ╔══════════════════════════════════════════════╗")
            lines.append("    ║                                              ║")
            lines.append("    ║         ✦ N E O C E R T I F Y ✦            ║")
            lines.append("    ║         RK3588 国产OS适配认证通过          ║")
            lines.append("    ║                                              ║")
            lines.append(f"    ║     等级: {self.data.get('certification_level', 'N/A'):>25s}         ║")
            lines.append(f"    ║     编号: {self.data.get('certification_id', 'N/A')}    ║")
            lines.append("    ║                                              ║")
            lines.append("    ╚══════════════════════════════════════════════╝")
        
        content = "\n".join(lines)
        
        if output_path:
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"Text report saved: {output_path}")
        
        return content
    
    def generate_html(self, output_path=None):
        """Generate HTML certification report"""
        if "error" in self.data:
            return f"<html><body><h1>Error</h1><p>{self.data['error']}</p></body></html>"
        
        plat = self.data.get("platform", {})
        
        # Build test suite rows
        suite_rows = ""
        for suite in self.data.get("test_suites", []):
            name = suite.get("name", "Unknown")
            score = suite.get("score", 0)
            status = suite.get("status", "N/A")
            color = "#4CAF50" if score >= 80 else "#FF9800" if score >= 60 else "#F44336"
            status_color = "#4CAF50" if status == "PASS" else "#F44336"
            
            detail_html = ""
            if "checks" in suite:
                for ck, cv in suite["checks"].items():
                    if isinstance(cv, dict):
                        continue
                    icon = "✅" if cv else "❌"
                    detail_html += f'<li>{icon} {ck}: {cv}</li>\n'
            
            suite_rows += f"""
            <tr>
                <td>{name}</td>
                <td>
                    <div class="score-bar">
                        <div class="score-fill" style="width:{score}%;background:{color}"></div>
                    </div>
                </td>
                <td><strong>{score}/100</strong></td>
                <td><span class="badge" style="background:{status_color}">{status}</span></td>
            </tr>
            <tr>
                <td colspan="4" class="detail">
                    <ul>{detail_html}</ul>
                </td>
            </tr>"""
        
        html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>RK3588 NeoCertify 认证报告</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: "Microsoft YaHei", "PingFang SC", sans-serif; background: #f5f5f5; color: #333; }}
.container {{ max-width: 960px; margin: 20px auto; padding: 30px; background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
h1 {{ text-align: center; color: #1a237e; margin-bottom: 5px; }}
.subtitle {{ text-align: center; color: #666; margin-bottom: 30px; }}
.cert-seal {{ text-align: center; padding: 20px; margin: 20px 0; border: 3px solid {'#4CAF50' if self.data.get('overall_status') == 'CERTIFIED' else '#FF9800'}; border-radius: 12px; background: #f9f9f9; }}
.cert-seal h2 {{ color: {'#4CAF50' if self.data.get('overall_status') == 'CERTIFIED' else '#FF9800'}; font-size: 28px; }}
.platform-info {{ display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin: 20px 0; padding: 20px; background: #f0f4ff; border-radius: 8px; }}
.platform-info .label {{ font-weight: bold; color: #555; }}
table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
th {{ background: #1a237e; color: #fff; padding: 12px; text-align: left; }}
td {{ padding: 10px 12px; border-bottom: 1px solid #eee; }}
.score-bar {{ width: 120px; height: 8px; background: #e0e0e0; border-radius: 4px; overflow: hidden; display: inline-block; }}
.score-fill {{ height: 100%; border-radius: 4px; }}
.badge {{ display: inline-block; padding: 3px 10px; border-radius: 12px; color: #fff; font-size: 12px; }}
.detail ul {{ margin: 5px 0 5px 20px; font-size: 13px; color: #666; list-style: none; }}
.summary {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 15px; margin: 20px 0; }}
.summary-card {{ padding: 20px; border-radius: 8px; text-align: center; }}
.summary-card h3 {{ font-size: 32px; margin-bottom: 5px; }}
.summary-card p {{ color: #666; }}
footer {{ text-align: center; margin-top: 30px; color: #999; font-size: 12px; }}
</style>
</head>
<body>
<div class="container">
    <h1>RK3588 NeoCertify 认证报告</h1>
    <p class="subtitle">NeoCertify 2.0 Certification Report</p>
    
    <div class="cert-seal">
        <h2>{'✦ 认 证 通 过 ✦' if self.data.get('overall_status') == 'CERTIFIED' else '⚠ 待审核 ⚠'}</h2>
        <p>认证编号: {self.data.get('certification_id', 'N/A')}</p>
        <p>认证等级: {self.data.get('certification_level', 'N/A')}</p>
        <p>生成时间: {self.data.get('timestamp', 'N/A')}</p>
    </div>
    
    <div class="summary">
        <div class="summary-card" style="background:#e8f5e9">
            <h3 style="color:#4CAF50">{self.data.get('overall_score', 0)}</h3>
            <p>综合评分</p>
        </div>
        <div class="summary-card" style="background:#e3f2fd">
            <h3 style="color:#2196F3">{len(self.data.get('test_suites', []))}</h3>
            <p>测试套件</p>
        </div>
        <div class="summary-card" style="background:#fff3e0">
            <h3 style="color:#FF9800">{self.data.get('overall_status', 'PENDING')}</h3>
            <p>认证状态</p>
        </div>
    </div>
    
    <div class="platform-info">
        <div><span class="label">操作系统:</span> {plat.get('os', 'N/A')}</div>
        <div><span class="label">内核版本:</span> {plat.get('kernel', 'N/A')}</div>
        <div><span class="label">CPU架构:</span> {plat.get('arch', 'N/A')}</div>
        <div><span class="label">CPU核心数:</span> {plat.get('cpu_cores', 'N/A')}</div>
        <div><span class="label">主机名:</span> {plat.get('hostname', 'N/A')}</div>
        <div><span class="label">内核完整版本:</span> {plat.get('kernel_version_full', 'N/A')}</div>
    </div>
    
    <h3>测试套件详细结果</h3>
    <table>
        <thead>
            <tr>
                <th>测试项目</th>
                <th>评分</th>
                <th>得分</th>
                <th>状态</th>
            </tr>
        </thead>
        <tbody>
            {suite_rows}
        </tbody>
    </table>
    
    <footer>
        <p>本报告由 RK3588 Domestic OS Adaptation Kit 自动生成</p>
        <p>NeoCertify 2.0 Compliance Test Suite | &copy; 2026</p>
    </footer>
</div>
</body>
</html>"""
        
        if output_path:
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(html)
            print(f"HTML report saved: {output_path}")
        
        return html
    
    def generate_pdf_description(self, output_path=None):
        """Generate PDF generation instructions (as actual PDF requires wkhtmltopdf or similar)"""
        desc = f"""NeoCertify Certification Report - PDF Generation Guide
========================================================

Report Data Source: {self.report_json}

To generate PDF from the HTML report:

Option 1: wkhtmltopdf (recommended)
  wkhtmltopdf --page-size A4 --margin-top 10mm --margin-bottom 10mm \\
    /tmp/neocertify_reports/report.html \\
    /tmp/neocertify_reports/report.pdf

Option 2: Python + weasyprint
  pip install weasyprint
  python3 -c "from weasyprint import HTML; HTML('/tmp/neocertify_reports/report.html').write_pdf('/tmp/neocertify_reports/report.pdf')"

Option 3: Browser print
  Open /tmp/neocertify_reports/report.html in a browser and print to PDF.
  Recommended print settings: A4, Margins: 10mm, Background graphics: ON

PDF Report Structure:
  1. Cover page with NeoCertify seal
  2. Platform summary
  3. Overall score and certification level
  4. Per-test-suite detailed results
  5. Appendix: raw JSON data

Certification ID: {self.data.get('certification_id', 'N/A')}
Overall Score: {self.data.get('overall_score', 0)}/100
Status: {self.data.get('overall_status', 'PENDING')}
Level: {self.data.get('certification_level', 'N/A')}
"""
        if output_path:
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(desc)
            print(f"PDF guide saved: {output_path}")
        
        return desc
    
    def _score_bar(self, score, width=20):
        """Generate ASCII score bar"""
        filled = int(score * width / 100)
        return f"[{'#' * filled}{'.' * (width - filled)}]"


def main():
    ap = argparse.ArgumentParser(description="NeoCertify Certification Report Generator")
    ap.add_argument("--input", "-i", default="/tmp/neocertify_report.json",
                    help="Input JSON report path")
    ap.add_argument("--output-dir", "-o", default="/tmp/neocertify_reports",
                    help="Output directory for reports")
    ap.add_argument("--format", "-f", choices=["text", "html", "pdf", "all"],
                    default="all", help="Report format")
    args = ap.parse_args()
    
    os.makedirs(args.output_dir, exist_ok=True)
    
    gen = CertReportGenerator(args.input)
    
    if "error" in gen.data:
        print(f"ERROR: {gen.data['error']}")
        print(gen.data.get("hint", ""))
        sys.exit(1)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    if args.format in ("text", "all"):
        path = os.path.join(args.output_dir, f"neocertify_report_{timestamp}.txt")
        gen.generate_text(path)
    
    if args.format in ("html", "all"):
        path = os.path.join(args.output_dir, f"neocertify_report_{timestamp}.html")
        gen.generate_html(path)
    
    if args.format in ("pdf", "all"):
        path = os.path.join(args.output_dir, f"neocertify_pdf_guide_{timestamp}.txt")
        gen.generate_pdf_description(path)
    
    print(f"\nReports generated in: {args.output_dir}")

if __name__ == "__main__":
    main()
