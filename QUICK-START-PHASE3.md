# Quick Start Guide - Standalone Phase 3

## TL;DR - Run Alias Generation

```powershell
# After verifying domains in Forward Email dashboard, run:
.\Phase3-AliasGeneration.ps1
```

That's it! The script will:
- ✅ Find all verified domains from state.json
- ✅ Create info@ + 49 unique aliases per domain (50 total)
- ✅ Export all aliases to data/aliases.txt
- ✅ Skip domains that already have aliases

## When to Use This Script

Use **Phase3-AliasGeneration.ps1** instead of the full three-phase script when:

1. ✅ You want to **manually verify** domains in Forward Email dashboard first
2. ✅ You want to **check DNS records** before creating aliases
3. ✅ You want to **process specific domains** only
4. ✅ You need **custom alias counts** or naming patterns
5. ✅ You're **retrying failed** alias creation

## Two Workflows

### Workflow A: Full Automation (Three-Phase Script)

```powershell
# Run everything automatically
.\Setup-EmailInfrastructure-ThreePhase.ps1
```

**Pros:** Hands-off, fast  
**Cons:** Less control, relies on DNS timing

### Workflow B: Manual Verification (Standalone Phase 3) ⭐ RECOMMENDED

```powershell
# Step 1: Configure DNS and attempt verification
.\Setup-EmailInfrastructure-ThreePhase.ps1

# Step 2: Manually verify in Forward Email dashboard
# Go to: https://forwardemail.net/my-account/domains
# Check each domain has green checkmarks

# Step 3: Run standalone Phase 3
.\Phase3-AliasGeneration.ps1
```

**Pros:** More control, verify before aliases  
**Cons:** Requires manual step

## Common Usage Patterns

### Pattern 1: All Verified Domains (Default)

```powershell
# Processes all domains with State = "Verified" in state.json
.\Phase3-AliasGeneration.ps1
```

### Pattern 2: Specific Domains Only

```powershell
# Create file with domains to process
@"
domain1.com
domain2.com
domain3.com
"@ | Out-File "my-domains.txt"

# Process only these domains
.\Phase3-AliasGeneration.ps1 -DomainsFile "my-domains.txt"
```

### Pattern 3: Custom Alias Count

```powershell
# Create 100 aliases per domain instead of 50
.\Phase3-AliasGeneration.ps1 -AliasCount 100
```

### Pattern 4: Different Name Mix

```powershell
# 50/50 mix of firstName vs firstName.lastName (default is 60/40)
.\Phase3-AliasGeneration.ps1 -FirstNamePercent 50
```

### Pattern 5: Dry Run (Test First)

```powershell
# See what would be processed without making API calls
.\Phase3-AliasGeneration.ps1 -DryRun
```

## What Gets Created

### For Each Domain:

1. **info@domain.com** - Standard business alias
2. **49 unique aliases** - Mix of:
   - 60% firstName only: `john@domain.com`, `mary@domain.com`
   - 40% firstName.lastName: `john.smith@domain.com`, `mary.johnson@domain.com`

### All Aliases Forward To:

📧 **gmb@decisionsunlimited.io**

### Output File:

📁 **data/aliases.txt** - All aliases in format: `name@domain.com`

## Expected Results (Current Portfolio)

Based on your current state:
- 📊 **49 domains** ready for verification (State: DnsConfigured)
- 🎯 **Expected:** ~45 domains will verify successfully
- 📧 **Total aliases:** ~2,250 (45 domains × 50 aliases)
- ⏱️ **Time:** 10-15 minutes

## Verification Checklist

Before running Phase 3, ensure domains are verified:

### Option A: Check in Forward Email Dashboard

1. Go to https://forwardemail.net/my-account/domains
2. Click on each domain
3. Look for green checkmarks:
   - ✅ TXT record verified
   - ✅ MX records verified

### Option B: Check state.json

```powershell
# Show domains by state
$state = Get-Content "data\state.json" | ConvertFrom-Json
$state.Domains.PSObject.Properties | 
    Group-Object { $_.Value.State } | 
    Select-Object Name, Count

# Expected output:
# Name           Count
# ----           -----
# DnsConfigured     49  ← Need to verify these
# Verified           0  ← Ready for Phase 3
# Failed            13  ← Need investigation
```

### Option C: Manually Update state.json

If domains are verified in Forward Email but state.json shows "DnsConfigured":

```powershell
# Load state
$state = Get-Content "data\state.json" | ConvertFrom-Json

# Update specific domain
$state.Domains.'example.com'.State = "Verified"

# Or update all DnsConfigured domains
$state.Domains.PSObject.Properties | ForEach-Object {
    if ($_.Value.State -eq "DnsConfigured") {
        $_.Value.State = "Verified"
    }
}

# Save
$state | ConvertTo-Json -Depth 10 | Set-Content "data\state.json"
```

## Troubleshooting

### ❌ "No domains to process"

**Fix:**
```powershell
# Check current state
$state = Get-Content "data\state.json" | ConvertFrom-Json
$state.Domains.PSObject.Properties | ForEach-Object {
    Write-Host "$($_.Name): $($_.Value.State)"
}

# Update domains to "Verified" if they're verified in Forward Email
```

### ❌ "Domain not verified"

**Fix:**
1. Check Forward Email dashboard
2. Ensure DNS records are correct in Cloudflare
3. Wait 5-10 minutes for DNS propagation
4. Click "Verify Records" in Forward Email

### ⚠️ "info@ already exists"

**This is normal** - Script skips existing aliases and continues

### ⚠️ Rate limiting

**This is normal** - Script automatically retries with backoff

## After Running

### 1. Check Results

```powershell
# View summary in console output
# Look for:
#   - Domains Processed: 45
#   - Successful: 45
#   - Total Aliases: 2250
```

### 2. Review aliases.txt

```powershell
# Count aliases
(Get-Content "data\aliases.txt").Count

# View sample aliases
Get-Content "data\aliases.txt" | Select-Object -First 20

# Find aliases for specific domain
Get-Content "data\aliases.txt" | Select-String "example.com"
```

### 3. Test Email Forwarding

```powershell
# Pick random alias to test
$testAlias = Get-Content "data\aliases.txt" | Get-Random
Write-Host "Send test email to: $testAlias" -ForegroundColor Cyan

# Send email to that address
# Check gmb@decisionsunlimited.io for forwarded email
```

### 4. Verify in Dashboard

1. Go to https://forwardemail.net/my-account/domains
2. Click on a domain
3. Go to "Aliases" tab
4. Verify aliases are listed
5. Check they forward to gmb@decisionsunlimited.io

## Files Reference

| File | Purpose |
|------|---------|
| **Phase3-AliasGeneration.ps1** | Standalone alias generation script |
| **PHASE3-STANDALONE-GUIDE.md** | Detailed documentation (this file) |
| **data/state.json** | Domain state tracking |
| **data/aliases.txt** | Output: all generated aliases |
| **logs/alias-generation.log** | Detailed operation logs |

## Need More Help?

📖 **Detailed Guide:** See PHASE3-STANDALONE-GUIDE.md  
📖 **Full Documentation:** See PHASE3-IMPROVEMENTS.md  
📖 **Pre-Flight Checklist:** See PRE-FLIGHT-CHECKLIST.md  
📖 **Implementation Summary:** See IMPLEMENTATION-SUMMARY.md

## Summary

**Standalone Phase 3 gives you control:**

✅ Verify domains manually before creating aliases  
✅ Process specific domains or all verified domains  
✅ Customize alias count and naming patterns  
✅ Safe to re-run - skips existing aliases  
✅ Independent of Phase 1 & 2 timing  

**Recommended workflow:**
1. Run Phase 1 & 2 (or just check current state)
2. Verify domains in Forward Email dashboard
3. Run `.\Phase3-AliasGeneration.ps1`
4. Test email forwarding
5. Done! ✅
