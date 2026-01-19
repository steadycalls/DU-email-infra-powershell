# Two-Pass Workflow Guide

## Overview

The email infrastructure setup has been redesigned into a **clean two-pass workflow** that separates concerns and provides better reliability through retry logic.

## Why Two Passes?

### Problems with Single-Pass Approach
- DNS propagation delays cause alias creation failures
- Difficult to retry failed domains without reprocessing everything
- Mixed concerns (DNS + aliases) make debugging harder
- No clear separation between infrastructure setup and content creation

### Benefits of Two-Pass Approach
- ✅ **Clear separation**: Infrastructure (Pass 1) vs Content (Pass 2)
- ✅ **Better reliability**: Retry logic for alias creation
- ✅ **Faster debugging**: Easy to identify if issue is DNS or API
- ✅ **Flexible timing**: Wait for DNS propagation between passes
- ✅ **Resumable**: Can re-run Pass 2 without touching DNS

## Workflow Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         PASS 1                               │
│         Enhanced Protection & DNS Configuration              │
├─────────────────────────────────────────────────────────────┤
│  1. Add domain to Forward Email                             │
│  2. Enable Enhanced Protection                              │
│  3. Extract unique verification string                      │
│  4. Configure DNS records in Cloudflare (DNS-only mode)     │
│     - TXT verification (with unique string)                 │
│     - TXT catch-all forwarding                              │
│     - MX records (mx1 + mx2, priority 10)                   │
└─────────────────────────────────────────────────────────────┘
                            ↓
                   Wait 5-10 minutes
                   (DNS propagation)
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                         PASS 2                               │
│            Alias Creation with Retry Logic                   │
├─────────────────────────────────────────────────────────────┤
│  1. For each domain:                                        │
│     a. Attempt to create info@ alias                        │
│     b. Generate 49 unique aliases                           │
│     c. Create all aliases                                   │
│  2. If creation fails:                                      │
│     a. Retry up to 3 times                                  │
│     b. Use exponential backoff (10s, 20s, 40s)             │
│     c. Move to next domain after max retries               │
│  3. Export all aliases to aliases.txt                       │
└─────────────────────────────────────────────────────────────┘
```

## Pass 1: Enhanced Protection & DNS Configuration

### Purpose
Set up the infrastructure foundation for email forwarding with Enhanced Protection.

### What It Does

**For each domain:**
1. Adds domain to Forward Email (or retrieves if exists)
2. Enables Enhanced Protection immediately
3. Extracts the unique cryptographic verification string
4. Configures DNS records in Cloudflare:
   - TXT verification record (with unique string)
   - TXT catch-all forwarding record
   - MX records (both priority 10, DNS-only mode)

### Script: `Pass1-EnhancedProtection-DNS.ps1`

### Usage

```powershell
# Basic usage (uses data/domains.txt)
.\Pass1-EnhancedProtection-DNS.ps1

# With custom domains file
.\Pass1-EnhancedProtection-DNS.ps1 -DomainsFile "my-domains.txt"

# Dry run (test without making changes)
.\Pass1-EnhancedProtection-DNS.ps1 -DryRun
```

### Output

```
[1/62] Processing: alliancedecksak.com
================================================================================
  [1/3] Adding domain to Forward Email...
        ✓ Domain added (ID: abc123)
  [2/3] Enabling Enhanced Protection...
        ✓ Enhanced Protection enabled
        → Verification string: XnmA4Q3ju6
  [3/3] Configuring DNS records in Cloudflare...
        ✓ Found Cloudflare zone (ID: xyz789)
        ✓ Added TXT verification record (DNS only, quoted)
        ✓ Added catch-all forwarding (DNS only, gmb@decisionsunlimited.io)
        ✓ Added MX records (DNS only, mx1 + mx2 priority 10)
  ✓ Pass 1 complete for alliancedecksak.com
```

### Success Criteria

- Domain added to Forward Email
- Enhanced Protection enabled (or fallback to domain ID)
- DNS records configured in Cloudflare
- All records set to DNS-only mode (not proxied)

### What Happens Next

**Wait 5-10 minutes** for DNS propagation before running Pass 2.

You can verify DNS propagation with:
```powershell
nslookup -type=TXT alliancedecksak.com
nslookup -type=MX alliancedecksak.com
```

## Pass 2: Alias Creation with Retry Logic

### Purpose
Create email aliases for all domains with robust retry logic.

### What It Does

**For each domain:**
1. Attempts to create info@ alias
2. Generates 49 unique aliases (firstName or firstName.lastName)
3. Creates all aliases via Forward Email API
4. If creation fails:
   - Retries up to 3 times
   - Uses exponential backoff (10s → 20s → 40s)
   - Moves to next domain after max retries
5. Exports all created aliases to aliases.txt

### Script: `Pass2-AliasCreation.ps1`

### Usage

```powershell
# Basic usage (uses data/domains.txt)
.\Pass2-AliasCreation.ps1

# With custom alias count
.\Pass2-AliasCreation.ps1 -AliasCount 100

# With custom retry settings
.\Pass2-AliasCreation.ps1 -MaxRetries 5 -InitialRetryDelay 15

# With different name mix
.\Pass2-AliasCreation.ps1 -FirstNamePercent 50

# Dry run (test without making changes)
.\Pass2-AliasCreation.ps1 -DryRun
```

### Output

```
[1/62] Creating aliases for: alliancedecksak.com
================================================================================
  [Attempt 1/3] Creating 50 aliases...
  [1/50] Creating info@ alias...
        ✓ Created info@alliancedecksak.com
  [2/50] Generating 49 unique aliases...
        ✓ Created 10/49 aliases
        ✓ Created 20/49 aliases
        ✓ Created 30/49 aliases
        ✓ Created 40/49 aliases
        ✓ Created 49 additional aliases
        ✓ Total: 50 aliases for alliancedecksak.com
  ✓ Alias generation complete for alliancedecksak.com
```

### Retry Logic

If alias creation fails:

```
[1/62] Creating aliases for: alliancedecksal.com
================================================================================
  [Attempt 1/3] Creating 50 aliases...
  ✗ ERROR (attempt 1): Domain not verified

  [Retry 2/3] Waiting 10 seconds before retry...
  [Attempt 2/3] Creating 50 aliases...
  ✗ ERROR (attempt 2): Domain not verified

  [Retry 3/3] Waiting 20 seconds before retry...
  [Attempt 3/3] Creating 50 aliases...
  ✓ Alias generation complete for alliancedecksal.com
```

### Success Criteria

- info@ alias created
- 49 additional aliases created
- All aliases exported to data/aliases.txt

### What Gets Created

For each domain (e.g., `alliancedecksak.com`):

```
info@alliancedecksak.com → gmb@decisionsunlimited.io
james@alliancedecksak.com → gmb@decisionsunlimited.io
mary.smith@alliancedecksak.com → gmb@decisionsunlimited.io
john@alliancedecksak.com → gmb@decisionsunlimited.io
patricia.johnson@alliancedecksak.com → gmb@decisionsunlimited.io
... (46 more unique aliases)
```

## Complete Workflow Example

### Step 1: Prepare Domains File

```powershell
# Create or verify domains.txt
cat data/domains.txt
```

Output:
```
alliancedecksak.com
alliancedecksal.com
alliancedecksca.com
... (59 more domains)
```

### Step 2: Run Pass 1

```powershell
# Run Pass 1 to configure infrastructure
.\Pass1-EnhancedProtection-DNS.ps1
```

Expected time: **5-10 minutes** for 62 domains

### Step 3: Wait for DNS Propagation

```powershell
# Wait 5-10 minutes, then verify DNS
nslookup -type=TXT alliancedecksak.com
nslookup -type=MX alliancedecksak.com
```

### Step 4: Verify in Forward Email Dashboard

1. Go to https://forwardemail.net/my-account/domains
2. Check each domain has:
   - ✅ Green checkmark for MX records
   - ✅ Green checkmark for TXT verification
   - 🔒 Enhanced Protection enabled

### Step 5: Run Pass 2

```powershell
# Run Pass 2 to create aliases
.\Pass2-AliasCreation.ps1
```

Expected time: **10-15 minutes** for 62 domains (50 aliases each)

### Step 6: Verify Results

```powershell
# Check aliases file
cat data/aliases.txt | measure-object -Line
```

Expected: **3,100 lines** (62 domains × 50 aliases)

## Parameters Reference

### Pass 1 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DomainsFile` | string | data/domains.txt | Path to domains file |
| `LogFile` | string | logs/pass1-enhanced-protection.log | Path to log file |
| `LogLevel` | string | INFO | Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL) |
| `DryRun` | switch | false | Test without making changes |

### Pass 2 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `DomainsFile` | string | data/domains.txt | Path to domains file |
| `LogFile` | string | logs/pass2-alias-creation.log | Path to log file |
| `LogLevel` | string | INFO | Logging level |
| `AliasCount` | int | 50 | Number of aliases per domain |
| `FirstNamePercent` | int | 60 | Percentage of firstName-only aliases (vs firstName.lastName) |
| `MaxRetries` | int | 3 | Maximum retry attempts per domain |
| `InitialRetryDelay` | int | 10 | Initial retry delay in seconds (doubles each retry) |
| `DryRun` | switch | false | Test without making changes |

## Troubleshooting

### Pass 1 Issues

**Issue**: "Failed to enable Enhanced Protection"

**Cause**: Account not on paid plan or API error

**Solution**:
- Verify Forward Email subscription includes Enhanced Protection
- Check API key permissions
- Script will fallback to domain ID (still works, just not enhanced)

**Issue**: "Failed to configure DNS"

**Cause**: Cloudflare zone not found or API error

**Solution**:
- Verify domain exists in Cloudflare account
- Check CLOUDFLARE_API_TOKEN permissions
- Ensure token has DNS edit permissions

### Pass 2 Issues

**Issue**: "Domain not verified" (even after retries)

**Cause**: DNS not propagated or records incorrect

**Solution**:
1. Wait longer (DNS can take up to 24 hours globally)
2. Verify DNS records in Cloudflare dashboard
3. Check Forward Email dashboard for verification status
4. Re-run Pass 2 after verification complete

**Issue**: "Rate limit exceeded"

**Cause**: Too many API requests too quickly

**Solution**:
- Script has built-in retry logic with exponential backoff
- Wait for retries to complete
- If persistent, increase `InitialRetryDelay` parameter

## Best Practices

### 1. Always Run in Order
- ✅ Run Pass 1 first
- ⏱️ Wait 5-10 minutes
- ✅ Run Pass 2 second

### 2. Verify Between Passes
- Check Forward Email dashboard
- Verify DNS propagation
- Confirm green checkmarks before Pass 2

### 3. Use Dry Run First
```powershell
.\Pass1-EnhancedProtection-DNS.ps1 -DryRun
.\Pass2-AliasCreation.ps1 -DryRun
```

### 4. Monitor Logs
```powershell
# Watch Pass 1 logs
Get-Content logs/pass1-enhanced-protection.log -Tail 20 -Wait

# Watch Pass 2 logs
Get-Content logs/pass2-alias-creation.log -Tail 20 -Wait
```

### 5. Re-run Pass 2 Safely
Pass 2 is **safe to re-run** multiple times:
- Skips existing aliases automatically
- Only creates missing aliases
- No risk of duplicates

## Expected Results

### For 62 Domains

**Pass 1:**
- Time: 5-10 minutes
- Output: DNS records configured
- Enhanced Protection: 62 domains enabled

**Pass 2:**
- Time: 10-15 minutes
- Output: 3,100 aliases created (62 × 50)
- Export: data/aliases.txt

### Success Metrics

- ✅ **100% DNS configuration**: All domains have MX and TXT records
- ✅ **100% Enhanced Protection**: All domains use cryptographic verification
- ✅ **95%+ alias creation**: Most domains create all 50 aliases
- ✅ **Retry success**: Failed domains succeed after retry

## Files Created

```
email-infra-ps/
├── data/
│   ├── domains.txt (input)
│   └── aliases.txt (output from Pass 2)
├── logs/
│   ├── pass1-enhanced-protection.log
│   └── pass2-alias-creation.log
├── Pass1-EnhancedProtection-DNS.ps1
└── Pass2-AliasCreation.ps1
```

## Comparison: Old vs New Approach

| Aspect | Old (Three-Phase) | New (Two-Pass) |
|--------|-------------------|----------------|
| **Passes** | 3 (DNS, Verify, Aliases) | 2 (Infrastructure, Content) |
| **Retry Logic** | Limited | Robust (3 attempts, exponential backoff) |
| **DNS Propagation** | Fixed 120s wait | Flexible (wait between passes) |
| **Resumability** | Must restart from beginning | Can re-run Pass 2 independently |
| **Debugging** | Mixed concerns | Clear separation |
| **Enhanced Protection** | Added in Phase 1 | Added in Pass 1 (correct order) |
| **Verification** | Automated | Manual check between passes |
| **Flexibility** | Rigid workflow | Flexible timing |

## Summary

The two-pass workflow provides:

1. **Better Reliability**: Retry logic handles transient failures
2. **Clearer Process**: Infrastructure setup separate from content creation
3. **Easier Debugging**: Know exactly where issues occur
4. **More Flexible**: Control timing between passes
5. **Safer Re-runs**: Pass 2 can be run multiple times safely

**Recommended for all new deployments!**

---

**Last Updated**: January 19, 2026  
**Script Version**: 2.0 (Two-Pass Workflow)
