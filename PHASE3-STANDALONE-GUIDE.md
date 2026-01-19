# Phase 3 Standalone Script - User Guide

## Overview

The **Phase3-AliasGeneration.ps1** script is a standalone tool for creating email aliases on verified domains. It can be run independently after you've manually verified domains in the Forward Email dashboard.

This gives you complete control over the process:
1. Run Phase 1 & 2 (or just Phase 1) to configure DNS
2. Manually verify domains in Forward Email dashboard
3. Run Phase 3 independently to create aliases

## Why Use the Standalone Script?

### Benefits

✅ **Manual Verification Control:** Verify domains at your own pace in the Forward Email dashboard  
✅ **Flexible Timing:** Run alias generation when you're ready, not tied to DNS propagation  
✅ **Selective Processing:** Process specific domains or all verified domains  
✅ **Customizable:** Adjust alias count and naming patterns  
✅ **Resumable:** Re-run safely - skips domains that already have aliases  
✅ **Independent:** No dependency on Phase 1 or Phase 2 completion

### Use Cases

1. **After Manual Verification:** You've verified domains in Forward Email dashboard and want to create aliases
2. **Selective Processing:** You want to create aliases for specific domains only
3. **Custom Alias Count:** You need more or fewer than 50 aliases per domain
4. **Different Name Mix:** You want a different ratio of firstName vs firstName.lastName
5. **Retry Failed Domains:** Some domains failed alias creation and you want to retry

## Prerequisites

### 1. Environment Setup

```powershell
# Ensure Forward Email API key is set
$env:FORWARD_EMAIL_API_KEY = "your-api-key-here"

# Verify it's set
if ($env:FORWARD_EMAIL_API_KEY) {
    Write-Host "✓ API key is set" -ForegroundColor Green
} else {
    Write-Host "✗ API key is missing" -ForegroundColor Red
}
```

### 2. Domains Must Be Verified

**Option A: Verify in Forward Email Dashboard**
1. Go to https://forwardemail.net/my-account/domains
2. Click on each domain
3. Ensure green checkmarks for MX and TXT records
4. Wait for verification to complete

**Option B: Update state.json Manually**
```powershell
# Load state
$state = Get-Content "data\state.json" | ConvertFrom-Json

# Update specific domain to Verified
$state.Domains.'example.com'.State = "Verified"

# Save state
$state | ConvertTo-Json -Depth 10 | Set-Content "data\state.json"
```

### 3. File Structure

```
email-infra-ps/
├── Phase3-AliasGeneration.ps1  ← Standalone script
├── modules/
│   ├── Config.psm1
│   ├── StateManager.psm1
│   ├── ForwardEmailClient.psm1
│   └── Logger.psm1
├── data/
│   ├── state.json              ← Must exist with verified domains
│   └── aliases.txt             ← Output file
├── logs/
│   └── alias-generation.log    ← Log file
└── config.json                 ← API credentials
```

## Usage Examples

### Example 1: Process All Verified Domains

```powershell
# Automatically finds all domains in "Verified" state from state.json
.\Phase3-AliasGeneration.ps1
```

**What it does:**
- Reads state.json
- Finds all domains with State = "Verified"
- Creates 50 aliases per domain (info@ + 49 generated)
- Uses 60/40 firstName/fullName mix
- Exports to data/aliases.txt

**Expected Output:**
```
================================================================================
Phase 3: Alias Generation for Verified Domains
================================================================================

Found 45 verified domains ready for alias generation

[1/45] Creating aliases for: example.com
================================================================================
  Creating email aliases...
    [1/50] Creating info@ alias...
      ✓ Created info@example.com
    [2/50] Generating 49 unique aliases...
      ✓ Created 10/49 aliases
      ✓ Created 20/49 aliases
      ✓ Created 30/49 aliases
      ✓ Created 40/49 aliases
      ✓ Created 49 additional aliases
      ✓ Total: 50 aliases for example.com
  ✓ Alias generation complete for example.com
```

### Example 2: Process Specific Domains

```powershell
# Create a file with specific domains
@"
alliancedecksak.com
alliancedecksca.com
alliancedecksco.com
"@ | Out-File "verified-domains.txt"

# Process only these domains
.\Phase3-AliasGeneration.ps1 -DomainsFile "verified-domains.txt"
```

**Use when:**
- You've verified only a subset of domains
- You want to test with a few domains first
- You're processing domains in batches

### Example 3: Custom Alias Count

```powershell
# Create 100 aliases per domain instead of 50
.\Phase3-AliasGeneration.ps1 -AliasCount 100
```

**Use when:**
- You need more aliases per domain
- You're setting up for high-volume email operations

### Example 4: Custom Name Mix

```powershell
# Use 50/50 mix of firstName vs firstName.lastName
.\Phase3-AliasGeneration.ps1 -FirstNamePercent 50

# Use 80/20 mix (80% firstName only)
.\Phase3-AliasGeneration.ps1 -FirstNamePercent 80
```

**Use when:**
- You want more full names (firstName.lastName)
- You want more simple names (firstName only)

### Example 5: Dry Run

```powershell
# See what would be processed without making API calls
.\Phase3-AliasGeneration.ps1 -DryRun
```

**Output:**
```
[DRY RUN] Would process the following domains:
  - example1.com
  - example2.com
  - example3.com

[DRY RUN] Would create 50 aliases per domain
[DRY RUN] Total aliases: 150
```

### Example 6: Custom Log File

```powershell
# Use a different log file
.\Phase3-AliasGeneration.ps1 -LogFile "logs\my-alias-run.log"
```

### Example 7: Verbose Logging

```powershell
# Enable debug logging
.\Phase3-AliasGeneration.ps1 -LogLevel DEBUG
```

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DomainsFile` | string | "" | Optional file with specific domains to process |
| `StateFile` | string | "data/state.json" | Path to state file |
| `LogFile` | string | "logs/alias-generation.log" | Path to log file |
| `LogLevel` | string | "INFO" | Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL) |
| `AliasCount` | int | 50 | Number of aliases per domain (includes info@) |
| `FirstNamePercent` | int | 60 | Percentage using firstName only (0-100) |
| `DryRun` | switch | false | Show what would be done without API calls |

## Workflow Integration

### Workflow 1: Full Automation (Three-Phase Script)

```powershell
# Run all three phases automatically
.\Setup-EmailInfrastructure-ThreePhase.ps1
```

**Use when:**
- You trust the automation completely
- You want hands-off operation
- DNS propagation is reliable in your region

### Workflow 2: Manual Verification (Recommended)

```powershell
# Step 1: Run Phase 1 & 2 only (DNS + Verification)
.\Setup-EmailInfrastructure-ThreePhase.ps1
# This will configure DNS and attempt verification

# Step 2: Manually verify in Forward Email dashboard
# Go to https://forwardemail.net/my-account/domains
# Check each domain for green checkmarks
# Wait for any pending verifications

# Step 3: Run Phase 3 standalone
.\Phase3-AliasGeneration.ps1
```

**Use when:**
- You want to verify domains manually before creating aliases
- You want to check DNS records in the dashboard
- You want more control over the process

### Workflow 3: Selective Processing

```powershell
# Step 1: Run Phase 1 & 2 for all domains
.\Setup-EmailInfrastructure-ThreePhase.ps1

# Step 2: Check which domains verified successfully
$state = Get-Content "data\state.json" | ConvertFrom-Json
$verified = $state.Domains.PSObject.Properties | Where-Object { $_.Value.State -eq "Verified" }
$verified | ForEach-Object { $_.Name }

# Step 3: Create file with priority domains
$priorityDomains = @("domain1.com", "domain2.com", "domain3.com")
$priorityDomains | Out-File "priority-domains.txt"

# Step 4: Process priority domains first
.\Phase3-AliasGeneration.ps1 -DomainsFile "priority-domains.txt"

# Step 5: Process remaining domains later
.\Phase3-AliasGeneration.ps1
```

**Use when:**
- You have priority domains that need aliases immediately
- You want to test with a small batch first
- You're processing domains in stages

## Understanding the Output

### Console Output

```
================================================================================
Phase 3: Alias Generation for Verified Domains
================================================================================

[PASS] Config module loaded
[PASS] StateManager module loaded
[PASS] ForwardEmailClient module loaded
[PASS] Logger module loaded
[PASS] Configuration loaded
[PASS] State manager initialized
[PASS] Logger initialized
[PASS] Forward Email client initialized

Found 45 verified domains ready for alias generation

================================================================================
Creating Aliases for Verified Domains
================================================================================

[1/45] Creating aliases for: example.com
================================================================================
  Creating email aliases...
    [1/50] Creating info@ alias...
      ✓ Created info@example.com
    [2/50] Generating 49 unique aliases...
      ✓ Created 10/49 aliases
      ✓ Created 20/49 aliases
      ✓ Created 30/49 aliases
      ✓ Created 40/49 aliases
      ✓ Created 49 additional aliases
      ✓ Total: 50 aliases for example.com
  ✓ Alias generation complete for example.com

[2/45] Creating aliases for: another.com
...

================================================================================
Exporting Aliases
================================================================================

✓ Exported 2250 aliases to: C:\path\to\data\aliases.txt

================================================================================
ALIAS GENERATION COMPLETE
================================================================================

Results:
  - Domains Processed: 45
  - Successful: 45
  - Failed: 0
  - Total Aliases: 2250
  - Avg per Domain: 50.0

Files:
  - State: data\state.json
  - Aliases: data\aliases.txt
  - Logs: logs\alias-generation.log

Next Steps:
  1. Review aliases.txt to see all generated email addresses
  2. Test email forwarding by sending to a few aliases
  3. Verify in Forward Email dashboard: https://forwardemail.net/my-account/domains
```

### Output Files

**1. data/aliases.txt**
```
info@alliancedecksak.com
james@alliancedecksak.com
john.smith@alliancedecksak.com
mary@alliancedecksak.com
robert.johnson@alliancedecksak.com
...
```

**2. data/state.json (updated)**
```json
{
  "LastUpdated": "2026-01-18T20:30:00.000Z",
  "Domains": {
    "example.com": {
      "State": "AliasesCreated",
      "Aliases": [
        "info",
        "james",
        "john.smith",
        "mary",
        ...
      ],
      "ForwardEmailDomainId": "696bc40f17672c7db2f935a7",
      "CloudflareZoneId": "75144c7d389098de26042178dfd6165d"
    }
  }
}
```

**3. logs/alias-generation.log**
```
2026-01-18 20:30:00 [INFO] Phase 3: Alias Generation Starting
2026-01-18 20:30:00 [INFO] Domains to process: 45
2026-01-18 20:30:01 [INFO] [example.com] Creating aliases 1/45
2026-01-18 20:30:02 [INFO] Created info@ alias
2026-01-18 20:30:15 [INFO] Created 50 aliases for example.com
...
```

## Troubleshooting

### Issue: No Domains Found

**Error:**
```
Found 0 verified domains ready for alias generation
No domains to process!
```

**Solution:**
```powershell
# Check current state
$state = Get-Content "data\state.json" | ConvertFrom-Json
$state.Domains.PSObject.Properties | ForEach-Object {
    Write-Host "$($_.Name): $($_.Value.State)"
}

# If domains are in "DnsConfigured" state, manually update to "Verified"
$state.Domains.'example.com'.State = "Verified"
$state | ConvertTo-Json -Depth 10 | Set-Content "data\state.json"
```

### Issue: Domain Not Verified in Forward Email

**Error:**
```
✗ ERROR: Domain not verified
```

**Solution:**
1. Go to Forward Email dashboard: https://forwardemail.net/my-account/domains
2. Click on the domain
3. Check verification status (should have green checkmarks)
4. If not verified, check DNS records in Cloudflare
5. Wait for DNS propagation (can take 5-30 minutes)
6. Click "Verify Records" in Forward Email dashboard

### Issue: Alias Already Exists

**Warning:**
```
ℹ info@ already exists (skipping)
```

**This is normal:**
- Script detects existing aliases and skips them
- Continues with remaining aliases
- No action needed

### Issue: API Rate Limiting

**Error:**
```
⚠ Rate limited. Waiting 60 seconds...
```

**Solution:**
- Script automatically handles rate limiting
- Wait for it to complete
- If it happens frequently, add delays:
  ```powershell
  # Process in smaller batches
  # Create file with 10 domains at a time
  ```

### Issue: Some Aliases Failed

**Output:**
```
Results:
  - Domains Processed: 45
  - Successful: 42
  - Failed: 3
```

**Solution:**
```powershell
# Check logs for specific errors
Get-Content "logs\alias-generation.log" | Select-String "ERROR"

# Check which domains failed
$state = Get-Content "data\state.json" | ConvertFrom-Json
$failed = $state.Domains.PSObject.Properties | Where-Object { $_.Value.State -eq "Failed" }
$failed | ForEach-Object { 
    Write-Host "$($_.Name): $($_.Value.Errors[-1].Message)" 
}

# Re-run for failed domains only
$failedDomains = $failed | ForEach-Object { $_.Name }
$failedDomains | Out-File "failed-domains.txt"
.\Phase3-AliasGeneration.ps1 -DomainsFile "failed-domains.txt"
```

## Best Practices

### 1. Test with Small Batch First

```powershell
# Create test file with 2-3 domains
@"
test1.com
test2.com
test3.com
"@ | Out-File "test-domains.txt"

# Run on test batch
.\Phase3-AliasGeneration.ps1 -DomainsFile "test-domains.txt"

# Verify results
Get-Content "data\aliases.txt" | Select-String "test1.com"

# If successful, process all domains
.\Phase3-AliasGeneration.ps1
```

### 2. Backup State Before Running

```powershell
# Backup state.json
Copy-Item "data\state.json" "data\state.json.backup"

# Run script
.\Phase3-AliasGeneration.ps1

# If issues, restore backup
Copy-Item "data\state.json.backup" "data\state.json"
```

### 3. Monitor Progress

```powershell
# In one window, run the script
.\Phase3-AliasGeneration.ps1

# In another window, monitor logs
Get-Content "logs\alias-generation.log" -Wait -Tail 20
```

### 4. Verify in Forward Email Dashboard

After script completes:
1. Go to https://forwardemail.net/my-account/domains
2. Click on a sample domain
3. Go to "Aliases" tab
4. Verify you see info@ and generated aliases
5. Check that they forward to gmb@decisionsunlimited.io

### 5. Test Email Forwarding

```powershell
# Pick a random alias
$testAlias = Get-Content "data\aliases.txt" | Get-Random
Write-Host "Send test email to: $testAlias" -ForegroundColor Cyan

# Send email to that address
# Check gmb@decisionsunlimited.io for forwarded email
```

## Advanced Usage

### Custom Recipient

If you want aliases to forward to a different address:

```powershell
# Edit the script
# Find this line (around line 270):
$recipient = "gmb@decisionsunlimited.io"

# Change to:
$recipient = "your-email@example.com"
```

### Custom Name Lists

To use different names:

```powershell
# Edit the script
# Find $firstNames and $lastNames arrays (around lines 180-220)
# Replace with your custom names
```

### Process Only Domains with Specific Pattern

```powershell
# Get all domains matching pattern
$state = Get-Content "data\state.json" | ConvertFrom-Json
$allianceDomains = $state.Domains.PSObject.Properties | 
    Where-Object { $_.Name -like "alliancedecks*" -and $_.Value.State -eq "Verified" } |
    ForEach-Object { $_.Name }

# Save to file
$allianceDomains | Out-File "alliance-domains.txt"

# Process
.\Phase3-AliasGeneration.ps1 -DomainsFile "alliance-domains.txt"
```

## Summary

The standalone Phase 3 script gives you complete control over alias generation:

✅ **Flexible:** Run when you're ready, not tied to DNS timing  
✅ **Selective:** Process specific domains or all verified domains  
✅ **Customizable:** Adjust alias count and naming patterns  
✅ **Safe:** Skips domains that already have aliases  
✅ **Resumable:** Re-run anytime without issues  

**Recommended Workflow:**
1. Run Phase 1 & 2 (DNS configuration and verification)
2. Manually verify domains in Forward Email dashboard
3. Run Phase 3 standalone to create aliases
4. Test email forwarding
5. Done!
