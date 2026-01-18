# Domain Verification Guide

This guide explains how to use the `Verify-EmailInfrastructure.ps1` script to check the status of your email infrastructure setup across Forward Email and Cloudflare.

## What It Checks

The verification script performs comprehensive checks for each domain:

### Forward Email Checks
- **Domain Exists**: Confirms the domain is registered in your Forward Email account
- **Domain Verified**: Checks if Forward Email has verified domain ownership via DNS
- **Alias Count**: Counts how many email aliases are configured for the domain

### Cloudflare Checks
- **Zone Found**: Confirms the domain exists as a zone in your Cloudflare account
- **TXT Record**: Verifies the Forward Email verification TXT record exists
- **MX Records**: Confirms both mx1.forwardemail.net and mx2.forwardemail.net MX records exist

### Overall Status
Each domain receives one of three statuses:
- **✓ Fully Configured**: All checks passed, domain is ready to receive email
- **⚠ Partially Configured**: Domain exists but some checks failed (e.g., not verified or missing DNS records)
- **✗ Not Configured**: Domain not found or major configuration missing

## Usage

### Basic Console Output

The simplest way to run the verification:

```powershell
# Load environment variables first
.\Load-Environment.ps1

# Run verification
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt
```

This displays a detailed, color-coded report in the console showing the status of each domain.

### Export to JSON

Export detailed results to a JSON file for programmatic processing:

```powershell
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat JSON -ExportPath report.json
```

If you don't specify `-ExportPath`, it will auto-generate a timestamped filename like `verification-report-20260118-143022.json`.

### Export to CSV

Export results to CSV for analysis in Excel or other spreadsheet tools:

```powershell
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat CSV -ExportPath report.csv
```

The CSV includes all check results and issues in a flat format suitable for sorting and filtering.

## Example Output

### Console Output

```
================================================================================
Email Infrastructure Verification
================================================================================

Loaded 3 domains from domains.txt

Verifying: example.com
  ✓ Domain exists in Forward Email
  ✓ Domain is verified in Forward Email
  ✓ 4 aliases configured
  ✓ Zone found in Cloudflare
  ✓ TXT verification record exists
  ✓ MX records exist (mx1 + mx2)
  Status: Fully Configured

Verifying: example.net
  ✓ Domain exists in Forward Email
  ✗ Domain is NOT verified in Forward Email
  ✓ 0 aliases configured
  ✓ Zone found in Cloudflare
  ✓ TXT verification record exists
  ✓ MX records exist (mx1 + mx2)
  Status: Partially Configured

Verifying: example.org
  ✗ Domain does NOT exist in Forward Email
  ✗ Zone NOT found in Cloudflare
  Status: Not Configured

================================================================================
Verification Summary
================================================================================
Total Domains: 3
  ✓ Fully Configured: 1
  ⚠ Partially Configured: 1
  ✗ Not Configured: 1

Domains with Issues:
  example.net:
    - Domain not verified in Forward Email
  example.org:
    - Domain not found in Forward Email
    - Zone not found in Cloudflare
```

## Common Issues and Solutions

### Issue: "Domain not verified in Forward Email"

**Cause**: DNS records may not have propagated yet, or the verification TXT record is incorrect.

**Solution**:
1. Check if DNS records exist in Cloudflare
2. Wait 5-10 minutes for DNS propagation
3. Run the verification script again
4. If still failing, manually verify in Forward Email dashboard

### Issue: "TXT verification record missing in Cloudflare"

**Cause**: The automation script may have failed to create the DNS record, or it was manually deleted.

**Solution**:
1. Log in to Forward Email and get the verification record value
2. Manually add the TXT record in Cloudflare, or
3. Re-run the setup script for that domain

### Issue: "MX records incomplete or missing"

**Cause**: MX records were not created or were partially deleted.

**Solution**:
1. Manually add the MX records in Cloudflare:
   - Priority 10: mx1.forwardemail.net
   - Priority 20: mx2.forwardemail.net
2. Or re-run the setup script for that domain

### Issue: "Zone not found in Cloudflare"

**Cause**: The domain is not registered in your Cloudflare account.

**Solution**:
1. Add the domain to Cloudflare first
2. Update your domain's nameservers to point to Cloudflare
3. Wait for nameserver propagation (can take 24-48 hours)
4. Re-run the setup script

## Integration with Setup Script

The verification script is designed to work alongside the main setup script:

**Workflow 1: Verify Before Setup**
```powershell
# Check current state
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt

# Run setup for domains that need it
.\Setup-EmailInfrastructure.ps1 -DomainsFile domains.txt

# Verify again to confirm success
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt
```

**Workflow 2: Periodic Audits**
```powershell
# Weekly audit to catch any configuration drift
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat CSV -ExportPath "audit-$(Get-Date -Format 'yyyyMMdd').csv"
```

**Workflow 3: Troubleshooting**
```powershell
# Create a file with just the problematic domains
.\Verify-EmailInfrastructure.ps1 -DomainsFile failed-domains.txt

# Review the specific issues
# Fix manually or re-run setup script
```

## Automation Tips

### Schedule Regular Verification

Create a scheduled task to run verification weekly:

```powershell
# Create a wrapper script: verify-weekly.ps1
.\Load-Environment.ps1
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat CSV -ExportPath "C:\Reports\email-audit-$(Get-Date -Format 'yyyyMMdd').csv"
```

Then schedule it in Windows Task Scheduler.

### Alert on Issues

Parse the JSON output to send alerts:

```powershell
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat JSON -ExportPath temp-report.json

$report = Get-Content temp-report.json | ConvertFrom-Json
$issues = $report | Where-Object { $_.Issues.Count -gt 0 }

if ($issues.Count -gt 0) {
    # Send email alert, post to Slack, etc.
    Write-Host "ALERT: $($issues.Count) domains have issues!"
}
```

### Compare Reports Over Time

```powershell
# Save daily reports
.\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat JSON -ExportPath "reports\$(Get-Date -Format 'yyyyMMdd').json"

# Compare today vs yesterday to detect changes
$today = Get-Content "reports\20260118.json" | ConvertFrom-Json
$yesterday = Get-Content "reports\20260117.json" | ConvertFrom-Json

# Identify newly broken domains
$newIssues = $today | Where-Object { 
    $_.Issues.Count -gt 0 -and 
    ($yesterday | Where-Object { $_.Domain -eq $_.Domain -and $_.Issues.Count -eq 0 })
}
```

## Parameters Reference

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-DomainsFile` | Yes | - | Path to text file with domains (one per line) |
| `-OutputFormat` | No | Console | Output format: Console, JSON, or CSV |
| `-ExportPath` | No | Auto-generated | Path for exported report file |

## Exit Codes

The script does not use exit codes for domain-level failures (since it processes multiple domains). It only exits with an error code if:
- Environment variables are not set
- Domains file is not found
- Modules fail to load

This allows the script to continue checking all domains even if some fail.

## See Also

- [README.md](README.md) - Project overview
- [USAGE.md](USAGE.md) - Setup script usage
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [WINDOWS-SETUP.md](WINDOWS-SETUP.md) - Windows-specific setup
