# Pre-Flight Checklist - Three-Phase Email Infrastructure Setup

## Before Running the Script

### ✅ Environment Verification

- [ ] **PowerShell Version:** Ensure PowerShell 7+ is installed
  ```powershell
  $PSVersionTable.PSVersion
  # Should show 7.0 or higher
  ```

- [ ] **Environment Variables:** Verify API credentials are set
  ```powershell
  # Check Forward Email API Key
  if ($env:FORWARD_EMAIL_API_KEY) { 
      Write-Host "✓ Forward Email API Key is set" -ForegroundColor Green 
  } else { 
      Write-Host "✗ Forward Email API Key is missing" -ForegroundColor Red 
  }
  
  # Check Cloudflare API Token
  if ($env:CLOUDFLARE_API_TOKEN) { 
      Write-Host "✓ Cloudflare API Token is set" -ForegroundColor Green 
  } else { 
      Write-Host "✗ Cloudflare API Token is missing" -ForegroundColor Red 
  }
  ```

- [ ] **Working Directory:** Navigate to the script directory
  ```powershell
  cd C:\path\to\email-infra-ps
  ```

- [ ] **Modules Available:** Verify all required modules exist
  ```powershell
  Get-ChildItem modules\*.psm1
  # Should show: Config.psm1, StateManager.psm1, ForwardEmailClient.psm1, 
  #              CloudflareClient.psm1, Logger.psm1
  ```

### ✅ Data Files Verification

- [ ] **Domains File:** Verify domains.txt exists and has content
  ```powershell
  if (Test-Path "data\domains.txt") {
      $domainCount = (Get-Content "data\domains.txt" | Where-Object { $_ -match '\S' }).Count
      Write-Host "✓ Found $domainCount domains" -ForegroundColor Green
  } else {
      Write-Host "✗ domains.txt not found" -ForegroundColor Red
  }
  ```

- [ ] **Config File:** Verify config.json exists
  ```powershell
  if (Test-Path "config.json") {
      Write-Host "✓ config.json exists" -ForegroundColor Green
  } else {
      Write-Host "✗ config.json not found" -ForegroundColor Red
  }
  ```

- [ ] **State File:** Check current state (if exists)
  ```powershell
  if (Test-Path "data\state.json") {
      $state = Get-Content "data\state.json" | ConvertFrom-Json
      $domains = $state.Domains.PSObject.Properties
      $stateGroups = $domains | Group-Object { $_.Value.State }
      
      Write-Host "`nCurrent State Summary:" -ForegroundColor Cyan
      foreach ($group in $stateGroups) {
          Write-Host "  $($group.Name): $($group.Count) domains" -ForegroundColor Yellow
      }
  } else {
      Write-Host "✓ No existing state - fresh start" -ForegroundColor Green
  }
  ```

### ✅ Directory Structure

- [ ] **Required Directories:** Ensure all directories exist
  ```powershell
  $requiredDirs = @("data", "logs", "modules", "config")
  foreach ($dir in $requiredDirs) {
      if (Test-Path $dir) {
          Write-Host "✓ $dir directory exists" -ForegroundColor Green
      } else {
          Write-Host "✗ $dir directory missing - creating..." -ForegroundColor Yellow
          New-Item -ItemType Directory -Path $dir -Force | Out-Null
      }
  }
  ```

### ✅ API Connectivity Test

- [ ] **Forward Email API:** Test API connectivity
  ```powershell
  try {
      $headers = @{
          "Authorization" = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$env:FORWARD_EMAIL_API_KEY:")))"
          "Accept" = "application/json"
      }
      $response = Invoke-RestMethod -Uri "https://api.forwardemail.net/v1/domains" -Headers $headers -Method GET
      Write-Host "✓ Forward Email API is accessible" -ForegroundColor Green
  } catch {
      Write-Host "✗ Forward Email API error: $($_.Exception.Message)" -ForegroundColor Red
  }
  ```

- [ ] **Cloudflare API:** Test API connectivity
  ```powershell
  try {
      $headers = @{
          "Authorization" = "Bearer $env:CLOUDFLARE_API_TOKEN"
          "Content-Type" = "application/json"
      }
      $response = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones?per_page=1" -Headers $headers -Method GET
      Write-Host "✓ Cloudflare API is accessible" -ForegroundColor Green
  } catch {
      Write-Host "✗ Cloudflare API error: $($_.Exception.Message)" -ForegroundColor Red
  }
  ```

## Running the Script

### Option 1: Fresh Start (All Phases)

```powershell
.\Setup-EmailInfrastructure-ThreePhase.ps1 -DomainsFile "data\domains.txt"
```

**Expected Behavior:**
- Phase 1: Configure DNS for all domains not yet configured
- Wait 180 seconds for DNS propagation
- Phase 2: Verify all domains with configured DNS
- Phase 3: Create aliases for all verified domains

**Estimated Time:** 30-40 minutes for 62 domains

### Option 2: Resume from Current State

```powershell
.\Setup-EmailInfrastructure-ThreePhase.ps1
```

**Expected Behavior:**
- Automatically detects current state from state.json
- Skips completed phases for each domain
- Continues from where it left off

**Estimated Time:** Depends on how many domains need processing

### Option 3: Longer DNS Wait Time

```powershell
.\Setup-EmailInfrastructure-ThreePhase.ps1 -DnsWaitTime 300
```

**Use When:**
- Previous verification attempts failed
- DNS propagation is slow in your region
- You want to be extra cautious

**Estimated Time:** +2-3 minutes for longer wait

### Option 4: Dry Run (Validation Only)

```powershell
.\Setup-EmailInfrastructure-ThreePhase.ps1 -DryRun
```

**Use When:**
- Testing configuration
- Verifying environment setup
- Checking domain file format

**Estimated Time:** < 1 minute

## During Execution

### ✅ Monitoring Progress

- [ ] **Watch Console Output:** Monitor real-time progress
  - Green ✓ = Success
  - Red ✗ = Error
  - Yellow ⚠ = Warning
  - Cyan = Phase headers

- [ ] **Check Log File:** Monitor detailed logs in another window
  ```powershell
  Get-Content logs\automation.log -Wait -Tail 20
  ```

- [ ] **Monitor State File:** Check state changes
  ```powershell
  # In another PowerShell window
  while ($true) {
      Clear-Host
      $state = Get-Content "data\state.json" | ConvertFrom-Json
      $domains = $state.Domains.PSObject.Properties
      $stateGroups = $domains | Group-Object { $_.Value.State }
      
      Write-Host "Current State ($(Get-Date -Format 'HH:mm:ss')):" -ForegroundColor Cyan
      foreach ($group in $stateGroups) {
          Write-Host "  $($group.Name): $($group.Count) domains" -ForegroundColor Yellow
      }
      Start-Sleep -Seconds 10
  }
  ```

### ✅ Expected Console Output

**Phase 1 (DNS Configuration):**
```
================================================================================
PHASE 1: DNS Configuration (Batch)
================================================================================

[1/62] Processing: example.com
================================================================================
  [1/3] Adding domain to Forward Email...
        ✓ Domain added (ID: 696bc40f17672c7db2f935a7)
  [2/3] Configuring DNS records in Cloudflare...
        ✓ Found Cloudflare zone (ID: 75144c7d389098de26042178dfd6165d)
        ✓ Added TXT verification record (quoted)
        ✓ Added catch-all forwarding (gmb@decisionsunlimited.io)
        ✓ Added MX records (mx1 + mx2)
  ✓ Phase 1 complete for example.com
```

**Phase 2 (Verification):**
```
================================================================================
PHASE 2: Domain Verification
================================================================================

[1/49] Verifying: example.com
================================================================================
  [3/5] Verifying domain ownership...
        Attempt 1/5...
        ✓ Domain ownership verified (MX + TXT records detected)
  ✓ Phase 2 complete for example.com
```

**Phase 3 (Alias Generation):**
```
================================================================================
PHASE 3: Alias Generation
================================================================================

[1/49] Creating aliases for: example.com
================================================================================
  [4/5] Creating email aliases...
        Creating info@ alias...
        ✓ Created info@example.com
        Generating 49 unique aliases...
        ✓ Created 10/49 aliases
        ✓ Created 20/49 aliases
        ✓ Created 30/49 aliases
        ✓ Created 40/49 aliases
        ✓ Created 49 aliases total
  ✓ Phase 3 complete for example.com
```

## After Execution

### ✅ Verify Results

- [ ] **Check Final Summary:** Review console output
  ```
  ================================================================================
  AUTOMATION COMPLETE
  ================================================================================
  
  Phase 1 (DNS Configuration):
    - Configured: 49
    - Failed: 13
  
  Phase 2 (Verification):
    - Verified: 49
    - Failed: 0
  
  Phase 3 (Aliases):
    - Created: 49
    - Failed: 0
    - Total Aliases: 2450
  
  Files:
    - State: data\state.json
    - Aliases: data\aliases.txt
    - Logs: logs\automation.log
  ```

- [ ] **Verify Alias File:** Check aliases were exported
  ```powershell
  if (Test-Path "data\aliases.txt") {
      $aliasCount = (Get-Content "data\aliases.txt").Count
      Write-Host "✓ Exported $aliasCount aliases" -ForegroundColor Green
      
      # Show sample aliases
      Write-Host "`nSample Aliases:" -ForegroundColor Cyan
      Get-Content "data\aliases.txt" | Select-Object -First 10
  } else {
      Write-Host "✗ aliases.txt not found" -ForegroundColor Red
  }
  ```

- [ ] **Check for Failures:** Review any failed domains
  ```powershell
  $state = Get-Content "data\state.json" | ConvertFrom-Json
  $failed = $state.Domains.PSObject.Properties | Where-Object { $_.Value.State -eq "Failed" }
  
  if ($failed.Count -gt 0) {
      Write-Host "`n⚠ Failed Domains: $($failed.Count)" -ForegroundColor Yellow
      foreach ($domain in $failed) {
          Write-Host "  - $($domain.Name)" -ForegroundColor Red
          if ($domain.Value.Errors.Count -gt 0) {
              $latestError = $domain.Value.Errors[-1]
              Write-Host "    Error: $($latestError.Message)" -ForegroundColor Gray
          }
      }
  } else {
      Write-Host "✓ No failed domains" -ForegroundColor Green
  }
  ```

- [ ] **Review Logs:** Check for warnings or errors
  ```powershell
  # Show last 50 log entries
  Get-Content "logs\automation.log" -Tail 50
  
  # Count errors and warnings
  $logContent = Get-Content "logs\automation.log"
  $errors = $logContent | Where-Object { $_ -match "ERROR" }
  $warnings = $logContent | Where-Object { $_ -match "WARNING" }
  
  Write-Host "`nLog Summary:" -ForegroundColor Cyan
  Write-Host "  Errors: $($errors.Count)" -ForegroundColor Red
  Write-Host "  Warnings: $($warnings.Count)" -ForegroundColor Yellow
  ```

### ✅ Test Email Forwarding

- [ ] **Test Catch-All Forwarding:**
  ```powershell
  # Send test email to: random-test-$(Get-Random)@[any-domain]
  # Should forward to gmb@decisionsunlimited.io
  ```

- [ ] **Test info@ Alias:**
  ```powershell
  # Send test email to: info@[any-domain]
  # Should forward to gmb@decisionsunlimited.io
  ```

- [ ] **Test Generated Alias:**
  ```powershell
  # Pick a random alias from aliases.txt
  $testAlias = Get-Content "data\aliases.txt" | Get-Random
  Write-Host "Test this alias: $testAlias" -ForegroundColor Cyan
  # Send email to this address
  # Should forward to gmb@decisionsunlimited.io
  ```

### ✅ Verify in Forward Email Dashboard

- [ ] **Login to Forward Email:** https://forwardemail.net/my-account/domains
- [ ] **Check Domain List:** Verify all domains are listed
- [ ] **Check Verification Status:** Ensure domains show as verified (green checkmark)
- [ ] **Check Aliases:** Click into a domain and verify aliases exist
- [ ] **Check Catch-All:** Verify catch-all forwarding is configured

### ✅ Verify in Cloudflare Dashboard

- [ ] **Login to Cloudflare:** https://dash.cloudflare.com
- [ ] **Pick a Sample Domain:** Click into DNS management
- [ ] **Verify TXT Records:** Should see two TXT records:
  - `forward-email-site-verification=[domain-id]` (quoted)
  - `forward-email=gmb@decisionsunlimited.io` (quoted)
- [ ] **Verify MX Records:** Should see two MX records:
  - `mx1.forwardemail.net` (priority 10)
  - `mx2.forwardemail.net` (priority 20)

## Troubleshooting

### ❌ Issue: Script Won't Start

**Error:** "Cannot be loaded because running scripts is disabled"

**Solution:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### ❌ Issue: Module Import Errors

**Error:** "The specified module 'X' was not loaded"

**Solution:**
```powershell
# Force reload all modules
Get-Module | Remove-Module -Force
Import-Module .\modules\Config.psm1 -Force
Import-Module .\modules\StateManager.psm1 -Force
Import-Module .\modules\ForwardEmailClient.psm1 -Force
Import-Module .\modules\CloudflareClient.psm1 -Force
Import-Module .\modules\Logger.psm1 -Force
```

### ❌ Issue: API Authentication Errors

**Error:** "401 Unauthorized" or "403 Forbidden"

**Solution:**
```powershell
# Re-set environment variables
$env:FORWARD_EMAIL_API_KEY = "your-api-key-here"
$env:CLOUDFLARE_API_TOKEN = "your-api-token-here"

# Verify they're set
Write-Host "Forward Email: $($env:FORWARD_EMAIL_API_KEY.Substring(0,10))..." -ForegroundColor Green
Write-Host "Cloudflare: $($env:CLOUDFLARE_API_TOKEN.Substring(0,10))..." -ForegroundColor Green
```

### ❌ Issue: Verification Fails for All Domains

**Symptoms:** Phase 2 shows "Missing records: MX, TXT" for all domains

**Solution:**
```powershell
# Wait longer for DNS propagation
Start-Sleep -Seconds 600  # Wait 10 minutes

# Re-run with longer wait time
.\Setup-EmailInfrastructure-ThreePhase.ps1 -DnsWaitTime 300
```

### ❌ Issue: Alias Creation Fails

**Error:** "Domain not verified" or "400 Bad Request"

**Solution:**
```powershell
# Check domain verification status in Forward Email dashboard
# If verified in dashboard but script fails, try:

# 1. Check state.json - ensure domain is in "Verified" state
$state = Get-Content "data\state.json" | ConvertFrom-Json
$state.Domains.'example.com'.State

# 2. Manually update state if needed (advanced)
$state.Domains.'example.com'.State = "Verified"
$state | ConvertTo-Json -Depth 10 | Set-Content "data\state.json"

# 3. Re-run script
.\Setup-EmailInfrastructure-ThreePhase.ps1
```

## Success Criteria

✅ **All checks passed:**
- [ ] Phase 1: 49+ domains configured (13 may remain failed from previous issues)
- [ ] Phase 2: 45+ domains verified (some may need more propagation time)
- [ ] Phase 3: 45+ domains with aliases created
- [ ] aliases.txt contains 2,250+ email addresses
- [ ] No critical errors in logs
- [ ] Test emails forward successfully
- [ ] Forward Email dashboard shows verified domains
- [ ] Cloudflare DNS records are correct

## Next Steps After Success

1. **Document Failed Domains:** Investigate the 13 domains that failed in Phase 1
2. **Test Email Forwarding:** Send test emails to verify forwarding works
3. **Monitor for Issues:** Check gmb@decisionsunlimited.io for test emails
4. **Schedule Regular Checks:** Periodically verify DNS records remain configured
5. **Add New Domains:** Update domains.txt and re-run script to add more domains

## Support

If issues persist after following this checklist:

1. Review `logs/automation.log` for detailed error messages
2. Check `data/failures.json` for failure details
3. Consult `PHASE3-IMPROVEMENTS.md` for architecture details
4. Review Forward Email API documentation: https://forwardemail.net/en/api
5. Review Cloudflare API documentation: https://developers.cloudflare.com/api/
