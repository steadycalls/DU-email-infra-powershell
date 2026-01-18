# Check-EmailInfrastructure.ps1 Guide

The `Check-EmailInfrastructure.ps1` script provides quick, at-a-glance validation of your email infrastructure setup. It's designed for rapid status checks and monitoring.

## Difference from Verify-EmailInfrastructure.ps1

While both scripts check domain configuration, they serve different purposes:

| Feature | Check-EmailInfrastructure.ps1 | Verify-EmailInfrastructure.ps1 |
|---------|-------------------------------|--------------------------------|
| **Purpose** | Quick pass/fail validation | Detailed diagnostic report |
| **Output** | Minimal, focused on status | Comprehensive with explanations |
| **Speed** | Fast (optimized for bulk checks) | Slower (detailed checks) |
| **Use Case** | Monitoring, CI/CD, quick audits | Troubleshooting, detailed analysis |
| **Exit Code** | Returns 1 if any failures | Always returns 0 |
| **Default Display** | Summary only | Full details |

## Usage

### Basic Check

The simplest usage - shows only pass/fail for each domain:

```powershell
.\Load-Environment.ps1
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt
```

**Output:**
```
================================================================================
Email Infrastructure Status Check
================================================================================

Checking 5 domains...

✓ example.com
✓ example.net
✗ example.org
✓ example.info
✓ example.biz

================================================================================
Summary
================================================================================
Total Domains: 5
  ✓ Passed: 4
  ✗ Failed: 1
  Pass Rate: 80.0%
```

### Show Details

Display additional information (alias count) for passing domains:

```powershell
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ShowDetails
```

**Output:**
```
✓ example.com (4 aliases)
✓ example.net (4 aliases)
✗ example.org
    - Domain not found in Forward Email
    - Zone not found in Cloudflare
✓ example.info (4 aliases)
✓ example.biz (4 aliases)
```

### Show Only Failed Domains

Filter to see only domains with issues:

```powershell
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -OnlyFailed
```

**Output:**
```
✗ example.org
    - Domain not found in Forward Email
    - Zone not found in Cloudflare
✗ example.co
    - Not verified in Forward Email
    - TXT verification record missing
```

### Export to JSON

Save results to JSON for programmatic processing:

```powershell
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ExportJson check-results.json
```

### Export to CSV

Save results to CSV for Excel analysis:

```powershell
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ExportCsv check-results.csv
```

## What It Checks

For each domain, the script validates:

### Forward Email Checks
1. **Domain Exists**: Domain is registered in your Forward Email account
2. **Domain Verified**: Forward Email has verified ownership via DNS
3. **Alias Count**: Number of email aliases configured

### Cloudflare Checks
1. **TXT Record**: Forward Email verification TXT record exists
2. **MX Records**: Both mx1.forwardemail.net and mx2.forwardemail.net MX records exist

### Pass/Fail Criteria

A domain **PASSES** if:
- ✓ Domain exists in Forward Email
- ✓ Domain is verified in Forward Email
- ✓ TXT verification record exists in Cloudflare
- ✓ Both MX records exist in Cloudflare

A domain **FAILS** if any of the above checks fail.

## Exit Codes

The script uses exit codes for automation:

- **Exit 0**: All domains passed
- **Exit 1**: One or more domains failed

This makes it easy to use in CI/CD pipelines or monitoring scripts.

## Use Cases

### 1. Post-Setup Validation

After running the setup script, quickly verify everything worked:

```powershell
.\Setup-EmailInfrastructure.ps1 -DomainsFile domains.txt
Start-Sleep -Seconds 300  # Wait 5 minutes for DNS propagation
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt
```

### 2. Daily Monitoring

Schedule a daily check to catch configuration drift:

```powershell
# check-daily.ps1
.\Load-Environment.ps1
$result = .\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ExportCsv "checks\$(Get-Date -Format 'yyyyMMdd').csv"

if ($LASTEXITCODE -ne 0) {
    # Send alert email, post to Slack, etc.
    Write-Host "ALERT: Some domains failed validation!"
}
```

### 3. CI/CD Integration

Use in automated pipelines:

```powershell
# In your CI/CD pipeline
.\Load-Environment.ps1
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt

if ($LASTEXITCODE -ne 0) {
    Write-Error "Email infrastructure validation failed"
    exit 1
}
```

### 4. Pre-Deployment Validation

Before deploying changes, verify current state:

```powershell
Write-Host "Checking current state..."
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt

if ($LASTEXITCODE -eq 0) {
    Write-Host "All systems operational, proceeding with deployment..."
    # Run deployment
} else {
    Write-Host "Issues detected, aborting deployment"
    exit 1
}
```

### 5. Bulk Domain Audit

Quickly audit hundreds of domains:

```powershell
# Check all domains and export results
.\Check-EmailInfrastructure.ps1 -DomainsFile all-domains.txt -ExportCsv audit-results.csv

# Then analyze in Excel or with PowerShell
$results = Import-Csv audit-results.csv
$failed = $results | Where-Object { $_.Status -eq "FAIL" }
Write-Host "Failed domains: $($failed.Count)"
```

### 6. Compare Before/After

Check status before and after changes:

```powershell
# Before changes
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ExportJson before.json

# Make changes...

# After changes
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ExportJson after.json

# Compare
$before = Get-Content before.json | ConvertFrom-Json
$after = Get-Content after.json | ConvertFrom-Json

$improved = $after | Where-Object { 
    $_.Status -eq "PASS" -and 
    ($before | Where-Object { $_.Domain -eq $_.Domain -and $_.Status -eq "FAIL" })
}

Write-Host "Domains fixed: $($improved.Count)"
```

## Common Issues

### Issue: "FORWARD_EMAIL_API_KEY not set"

**Solution:** Run `.\Load-Environment.ps1` before running the check script.

### Issue: All domains show "FAIL"

**Possible causes:**
1. API credentials are incorrect
2. DNS records haven't propagated yet (wait 5-10 minutes)
3. Domains weren't actually set up yet

**Solution:** Run with `-ShowDetails` to see specific issues.

### Issue: Some domains pass, others fail

**Solution:** Run with `-OnlyFailed` to focus on problematic domains:

```powershell
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -OnlyFailed
```

Then investigate each failed domain individually or re-run the setup script for just those domains.

## Integration with Other Scripts

### Workflow 1: Setup → Check → Verify

```powershell
# 1. Run setup
.\Setup-EmailInfrastructure.ps1 -DomainsFile domains.txt

# 2. Quick check
Start-Sleep -Seconds 300
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt

# 3. Detailed verification for failures
if ($LASTEXITCODE -ne 0) {
    .\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat Console
}
```

### Workflow 2: Check → Fix → Check

```powershell
# 1. Check current state
.\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -OnlyFailed -ExportCsv failed.csv

# 2. Extract failed domains
$failed = Import-Csv failed.csv | Select-Object -ExpandProperty Domain
$failed | Out-File failed-domains.txt

# 3. Re-run setup for failed domains
.\Setup-EmailInfrastructure.ps1 -DomainsFile failed-domains.txt

# 4. Check again
Start-Sleep -Seconds 300
.\Check-EmailInfrastructure.ps1 -DomainsFile failed-domains.txt
```

## Automation Examples

### Windows Task Scheduler

Create a scheduled task to run daily checks:

```powershell
# create-scheduled-check.ps1
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File C:\path\to\check-daily.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U

Register-ScheduledTask -TaskName "Email Infrastructure Check" -Action $action -Trigger $trigger -Principal $principal
```

### PowerShell Monitoring Loop

Continuous monitoring with alerts:

```powershell
# monitor.ps1
while ($true) {
    .\Load-Environment.ps1
    $result = .\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -OnlyFailed
    
    if ($LASTEXITCODE -ne 0) {
        # Send alert
        Send-MailMessage -To "admin@example.com" -Subject "Email Infrastructure Alert" -Body "Some domains failed validation"
    }
    
    Start-Sleep -Seconds 3600  # Check every hour
}
```

## Parameters Reference

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-DomainsFile` | String | Yes | - | Path to domains file |
| `-ShowDetails` | Switch | No | False | Show alias counts and issue details |
| `-OnlyFailed` | Switch | No | False | Display only failed domains |
| `-ExportJson` | String | No | - | Export results to JSON file |
| `-ExportCsv` | String | No | - | Export results to CSV file |

## Output Format

### Console Output

- **✓** (green checkmark): Domain passed all checks
- **✗** (red X): Domain failed one or more checks
- Issue details shown in yellow when `-ShowDetails` or `-OnlyFailed` is used

### JSON Export

```json
[
  {
    "Domain": "example.com",
    "Status": "PASS",
    "ForwardEmailExists": true,
    "ForwardEmailVerified": true,
    "CloudflareTxtRecord": true,
    "CloudflareMxRecords": true,
    "AliasCount": 4,
    "Issues": [],
    "CheckedAt": "2026-01-18 22:30:15"
  }
]
```

### CSV Export

| Domain | Status | ForwardEmailExists | ForwardEmailVerified | CloudflareTxtRecord | CloudflareMxRecords | AliasCount | CheckedAt | Issues |
|--------|--------|-------------------|---------------------|--------------------|--------------------|-----------|-----------|--------|
| example.com | PASS | True | True | True | True | 4 | 2026-01-18 22:30:15 | |

## See Also

- [README.md](README.md) - Project overview
- [VERIFICATION-GUIDE.md](VERIFICATION-GUIDE.md) - Detailed verification script
- [USAGE.md](USAGE.md) - Setup script usage
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
