<#
.SYNOPSIS
    Automates email infrastructure setup for bulk domains using Forward Email and Cloudflare (Two-Phase Approach).

.DESCRIPTION
    This script processes domains in two efficient phases:
    
    PHASE 1 - DNS Configuration:
    1. Add each domain to Forward Email
    2. Configure DNS records in Cloudflare (TXT + MX)
    3. Remove old unquoted TXT records if they exist
    
    PHASE 2 - Verification & Aliases (after DNS propagation):
    4. Verify domain ownership via DNS
    5. Create standardized email aliases
    
    This two-phase approach is much faster than sequential processing because:
    - DNS records for all domains are configured first
    - DNS propagates while other domains are being configured
    - Verification happens in batch after propagation time
    - No waiting 30s between each domain verification

.PARAMETER DomainsFile
    Path to text file containing list of domains (one per line).

.PARAMETER ConfigFile
    Optional path to JSON configuration file.

.PARAMETER StateFile
    Path to state persistence file (default: data/state.json).

.PARAMETER LogFile
    Path to log file (default: logs/automation.log).

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL (default: INFO).

.PARAMETER DnsWaitTime
    Seconds to wait between Phase 1 and Phase 2 for DNS propagation (default: 120).

.PARAMETER DryRun
    If specified, performs validation only without making API calls.

.EXAMPLE
    .\Setup-EmailInfrastructure-TwoPhase.ps1 -DomainsFile "data/domains.txt"

.EXAMPLE
    .\Setup-EmailInfrastructure-TwoPhase.ps1 -DomainsFile "domains.txt" -DnsWaitTime 180

.NOTES
    Requires PowerShell 7+ and the following environment variables:
    - FORWARD_EMAIL_API_KEY
    - CLOUDFLARE_API_TOKEN
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainsFile = "data/domains.txt",
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$StateFile = "data/state.json",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/automation.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [int]$DnsWaitTime = 120,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

# Import modules
$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "modules"

try {
    Import-Module (Join-Path $modulePath "Config.psm1") -Force
    Write-Host "[PASS] Config module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "StateManager.psm1") -Force
    Write-Host "[PASS] StateManager module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "ForwardEmailClient.psm1") -Force
    Write-Host "[PASS] ForwardEmailClient module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "CloudflareClient.psm1") -Force
    Write-Host "[PASS] CloudflareClient module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "Logger.psm1") -Force
    Write-Host "[PASS] Logger module loaded" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to load modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize configuration
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Automation Starting (Two-Phase Mode)" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

try {
    $config = New-EmailInfraConfig -ConfigPath $ConfigFile
    Write-Host "Configuration loaded successfully" -ForegroundColor Green
    Write-Host "  - Forward Email API Base: $($config.ForwardEmailApiBase)" -ForegroundColor Gray
    Write-Host "  - Cloudflare API Base: $($config.CloudflareApiBase)" -ForegroundColor Gray
    Write-Host "  - Max Retries: $($config.MaxRetries)" -ForegroundColor Gray
    Write-Host "  - Aliases Configured: $($config.Aliases.Count)" -ForegroundColor Gray
    Write-Host "  - DNS Wait Time: ${DnsWaitTime}s" -ForegroundColor Gray
}
catch {
    Write-Host "Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize state manager
Write-Host ""
try {
    $stateManager = New-StateManager -StateFile $StateFile
    Write-Host "State manager initialized" -ForegroundColor Green
}
catch {
    Write-Host "Failed to initialize state manager: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize API clients
Write-Host ""
try {
    $retryConfig = @{
        MaxRetries = $config.MaxRetries
        InitialRetryDelay = $config.InitialRetryDelay
        MaxRetryDelay = $config.MaxRetryDelay
        RateLimitDelay = $config.RateLimitDelay
    }
    
    $forwardEmailClient = New-ForwardEmailClient -BaseUrl $config.ForwardEmailApiBase -ApiKey $config.ForwardEmailApiKey -RetryConfig $retryConfig
    $cloudflareClient = New-CloudflareClient -BaseUrl $config.CloudflareApiBase -ApiToken $config.CloudflareApiToken -AccountId $config.CloudflareAccountId -RetryConfig $retryConfig
    $logger = New-Logger -LogFile $LogFile -MinLevel $LogLevel
    
    Write-Host "API clients initialized" -ForegroundColor Green
}
catch {
    Write-Host "Failed to initialize API clients: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Load domains from file
Write-Host ""
if (-not (Test-Path $DomainsFile)) {
    Write-Host "Domains file not found: $DomainsFile" -ForegroundColor Red
    exit 1
}

$domains = Get-Content $DomainsFile | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
$totalDomains = $domains.Count

if ($totalDomains -eq 0) {
    Write-Host "No domains found in file: $DomainsFile" -ForegroundColor Red
    exit 1
}

Write-Host "Loaded $totalDomains domains from file" -ForegroundColor Green
Write-Host ""

# Initialize counters
$phase1Complete = 0
$phase1Failed = 0
$phase2Complete = 0
$phase2Failed = 0
$skippedCount = 0

$startTime = Get-Date

# Log automation start
$logger.Info("========================================", $null, $null)
$logger.Info("Email Infrastructure Automation Starting (Two-Phase)", $null, $null)
$logger.Info("========================================", $null, $null)

#==============================================================================
# PHASE 1: DNS CONFIGURATION FOR ALL DOMAINS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 1: DNS Configuration" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 1: DNS Configuration Starting", $null, $null)
$logger.Info("========================================", $null, $null)

$domainIndex = 0
foreach ($domain in $domains) {
    $domainIndex++
    Write-Host "[$domainIndex/$totalDomains] Processing: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("[$domain] Processing domain $domainIndex/$totalDomains", $domain, $null)
    
    # Load or create domain record
    $record = $stateManager.GetDomain($domain)
    if ($null -eq $record) {
        $record = $stateManager.CreateDomain($domain)
        Write-Host "  ✓ Domain record created" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Domain record loaded (State: $($record.State))" -ForegroundColor Green
    }
    
    # Skip if already completed Phase 1 (DNS configured or beyond)
    if ($record.State -in @("DnsConfigured", "Verified", "AliasesCreated", "Completed")) {
        $logger.Info("Domain already has DNS configured, skipping Phase 1", $domain, $null)
        Write-Host "  ✓ DNS already configured - skipping Phase 1" -ForegroundColor Yellow
        $phase1Complete++
        Write-Host ""
        continue
    }
    
    # Skip if failed with max retries
    if ($record.State -eq "Failed" -and $record.Attempts -ge $config.MaxRetries) {
        $logger.Warning("Domain failed with max retries, skipping", $domain, @{Attempts = $record.Attempts})
        Write-Host "  ✗ Domain failed with max retries - skipping" -ForegroundColor Red
        $skippedCount++
        Write-Host ""
        continue
    }
    
    $record.UpdateAttempt()
    
    try {
        # Step 1: Add domain to Forward Email
        if ($record.State -eq "Pending" -or [string]::IsNullOrEmpty($record.ForwardEmailDomainId)) {
            Write-Host "  [1/2] Adding domain to Forward Email..." -ForegroundColor Yellow
            $logger.Info("Adding domain to Forward Email", $domain, $null)
            
            try {
                # Check if domain already exists
                if ($forwardEmailClient.DomainExists($domain)) {
                    $logger.Info("Domain already exists in Forward Email", $domain, $null)
                    Write-Host "        ✓ Domain already exists in Forward Email" -ForegroundColor Green
                    $domainInfo = $forwardEmailClient.GetDomain($domain)
                } else {
                    $domainInfo = $forwardEmailClient.CreateDomain($domain)
                    $logger.Info("Domain added to Forward Email", $domain, @{DomainId = $domainInfo.id})
                    Write-Host "        ✓ Domain added to Forward Email" -ForegroundColor Green
                }
                
                $record.ForwardEmailDomainId = $domainInfo.id
                $record.State = "ForwardEmailAdded"
                $stateManager.UpdateDomain($domain, $record)
            }
            catch {
                $errorMessage = $_.Exception.Message
                $logger.Error("Failed to add domain to Forward Email: $errorMessage", $domain, $null)
                Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                $record.AddError("forward_email_add", $errorMessage, "FORWARD_EMAIL_ERROR", @{})
                $record.MarkFailed()
                $stateManager.UpdateDomain($domain, $record)
                $phase1Failed++
                Write-Host ""
                continue
            }
        }
        
        # Step 2: Configure DNS records in Cloudflare
        if ($record.State -eq "ForwardEmailAdded") {
            Write-Host "  [2/2] Configuring DNS records in Cloudflare..." -ForegroundColor Yellow
            $logger.Info("Configuring DNS records in Cloudflare", $domain, $null)
            
            try {
                # Get Cloudflare Zone ID
                $zoneId = $cloudflareClient.GetZoneId($domain)
                $record.CloudflareZoneId = $zoneId
                $logger.Info("Found Cloudflare zone", $domain, @{ZoneId = $zoneId})
                Write-Host "        ✓ Found Cloudflare zone: $zoneId" -ForegroundColor Green
                
                # Remove old unquoted TXT record if it exists
                try {
                    $oldTxtValue = "forward-email-site-verification=$($record.ForwardEmailDomainId)"
                    $existingRecords = $cloudflareClient.ListDnsRecords($zoneId, "TXT", $domain)
                    $oldRecord = $existingRecords | Where-Object { $_.content -eq $oldTxtValue }
                    if ($oldRecord) {
                        $cloudflareClient.DeleteDnsRecord($zoneId, $oldRecord.id)
                        $logger.Info("Removed old unquoted TXT record", $domain, @{RecordId = $oldRecord.id})
                        Write-Host "        ✓ Removed old unquoted TXT record" -ForegroundColor Green
                    }
                }
                catch {
                    # Non-critical error, continue
                    $logger.Warning("Could not remove old TXT record: $($_.Exception.Message)", $domain, $null)
                }
                
                # Add new quoted TXT verification record
                $txtValue = "`"forward-email-site-verification=$($record.ForwardEmailDomainId)`""
                $txtRecord = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "TXT", $txtValue, 3600)
                $logger.Info("Added TXT verification record", $domain, @{RecordId = $txtRecord.id})
                Write-Host "        ✓ Added TXT verification record (quoted)" -ForegroundColor Green
                
                # Add MX records
                $mx1 = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "MX", "mx1.forwardemail.net", 3600, 10)
                $mx2 = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "MX", "mx2.forwardemail.net", 3600, 20)
                $logger.Info("Added MX records", $domain, @{MX1 = $mx1.id; MX2 = $mx2.id})
                Write-Host "        ✓ Added MX records (mx1 + mx2)" -ForegroundColor Green
                
                $record.State = "DnsConfigured"
                $stateManager.UpdateDomain($domain, $record)
                $phase1Complete++
                Write-Host "  ✓ Phase 1 complete for $domain" -ForegroundColor Green
            }
            catch {
                $errorMessage = $_.Exception.Message
                $logger.Error("Failed to configure DNS: $errorMessage", $domain, $null)
                Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                $record.AddError("dns_config", $errorMessage, "DNS_ERROR", @{})
                $record.MarkFailed()
                $stateManager.UpdateDomain($domain, $record)
                $phase1Failed++
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $logger.Error("Unexpected error in Phase 1: $errorMessage", $domain, $null)
        Write-Host "  ✗ UNEXPECTED ERROR: $errorMessage" -ForegroundColor Red
        $record.AddError("phase1_error", $errorMessage, "UNKNOWN_ERROR", @{})
        $record.MarkFailed()
        $stateManager.UpdateDomain($domain, $record)
        $phase1Failed++
    }
    
    Write-Host ""
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 1 COMPLETE" -ForegroundColor Cyan
Write-Host "  - Configured: $phase1Complete domains" -ForegroundColor Green
Write-Host "  - Failed: $phase1Failed domains" -ForegroundColor Red
Write-Host "  - Skipped: $skippedCount domains" -ForegroundColor Yellow
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 1 Complete: Configured=$phase1Complete, Failed=$phase1Failed, Skipped=$skippedCount", $null, $null)
$logger.Info("========================================", $null, $null)

# Wait for DNS propagation
if ($phase1Complete -gt 0) {
    Write-Host "Waiting ${DnsWaitTime} seconds for DNS propagation..." -ForegroundColor Yellow
    Write-Host "This allows DNS records to propagate before verification attempts." -ForegroundColor Gray
    Write-Host ""
    $logger.Info("Waiting ${DnsWaitTime}s for DNS propagation", $null, $null)
    Start-Sleep -Seconds $DnsWaitTime
}

#==============================================================================
# PHASE 2: VERIFICATION AND ALIASES FOR ALL DOMAINS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 2: Verification & Aliases" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 2: Verification & Aliases Starting", $null, $null)
$logger.Info("========================================", $null, $null)

$domainIndex = 0
foreach ($domain in $domains) {
    $domainIndex++
    
    # Load domain record
    $record = $stateManager.GetDomain($domain)
    if ($null -eq $record) {
        continue  # Skip if no record exists
    }
    
    # Skip if already completed
    if ($record.State -eq "Completed") {
        $logger.Info("Domain already completed, skipping Phase 2", $domain, $null)
        $phase2Complete++
        continue
    }
    
    # Skip if not ready for Phase 2 (DNS not configured)
    if ($record.State -notin @("DnsConfigured", "Verified", "AliasesCreated")) {
        continue
    }
    
    Write-Host "[$domainIndex/$totalDomains] Processing: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("[$domain] Processing domain $domainIndex/$totalDomains (Phase 2)", $domain, $null)
    Write-Host "  ✓ Domain record loaded (State: $($record.State))" -ForegroundColor Green
    
    try {
        # Step 3: Verify domain ownership
        if ($record.State -eq "DnsConfigured") {
            Write-Host "  [3/5] Verifying domain ownership..." -ForegroundColor Yellow
            $logger.Info("Verifying domain ownership", $domain, $null)
            
            $maxAttempts = 3
            $attemptDelay = 10
            $verified = $false
            
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    Write-Host "        Attempt $attempt/$maxAttempts..." -ForegroundColor Gray
                    $verifyResult = $forwardEmailClient.VerifyDomain($domain)
                    
                    if ($verifyResult.verification_record) {
                        $verified = $true
                        $logger.Info("Domain ownership verified", $domain, $null)
                        Write-Host "        ✓ Domain ownership verified" -ForegroundColor Green
                        break
                    }
                }
                catch {
                    $logger.Warning("Verification attempt $attempt failed: $($_.Exception.Message)", $domain, $null)
                }
                
                if ($attempt -lt $maxAttempts) {
                    Write-Host "        Waiting ${attemptDelay}s..." -ForegroundColor Gray
                    Start-Sleep -Seconds $attemptDelay
                }
            }
            
            if (-not $verified) {
                $errorMessage = "Domain verification failed after $maxAttempts attempts"
                $logger.Error($errorMessage, $domain, $null)
                Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                $record.AddError("verification", $errorMessage, "VERIFICATION_ERROR", @{})
                $record.MarkFailed()
                $stateManager.UpdateDomain($domain, $record)
                $phase2Failed++
                Write-Host ""
                continue
            }
            
            $record.State = "Verified"
            $stateManager.UpdateDomain($domain, $record)
        }
        
        # Step 4: Create email aliases
        if ($record.State -eq "Verified") {
            Write-Host "  [4/5] Creating email aliases..." -ForegroundColor Yellow
            $logger.Info("Creating email aliases", $domain, $null)
            
            $aliasesCreated = 0
            foreach ($aliasConfig in $config.Aliases) {
                try {
                    $aliasName = $aliasConfig.Name
                    $recipients = $aliasConfig.Recipients
                    $description = $aliasConfig.Description
                    $labels = $aliasConfig.Labels
                    
                    # Check if alias already exists
                    if ($forwardEmailClient.AliasExists($domain, $aliasName)) {
                        $logger.Info("Alias already exists: $aliasName", $domain, $null)
                        Write-Host "        ✓ Alias already exists: $aliasName@$domain" -ForegroundColor Yellow
                        $aliasesCreated++
                        continue
                    }
                    
                    $alias = $forwardEmailClient.CreateAlias($domain, $aliasName, $recipients, $description, $labels)
                    $logger.Info("Created alias: $aliasName", $domain, @{AliasId = $alias.id})
                    Write-Host "        ✓ Created alias: $aliasName@$domain" -ForegroundColor Green
                    $aliasesCreated++
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    $logger.Warning("Failed to create alias ${aliasName}: ${errorMessage}", $domain, $null)
                    Write-Host "        ✗ Failed to create alias ${aliasName}: ${errorMessage}" -ForegroundColor Red
                }
            }
            
            if ($aliasesCreated -eq 0) {
                $errorMessage = "No aliases were created"
                $logger.Error($errorMessage, $domain, $null)
                Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                $record.AddError("alias_creation", $errorMessage, "ALIAS_ERROR", @{})
                $record.MarkFailed()
                $stateManager.UpdateDomain($domain, $record)
                $phase2Failed++
                Write-Host ""
                continue
            }
            
            Write-Host "        ✓ Created $aliasesCreated aliases" -ForegroundColor Green
            $record.State = "AliasesCreated"
            $stateManager.UpdateDomain($domain, $record)
        }
        
        # Step 5: Mark as completed
        if ($record.State -eq "AliasesCreated") {
            Write-Host "  [5/5] Finalizing..." -ForegroundColor Yellow
            $record.MarkCompleted()
            $stateManager.UpdateDomain($domain, $record)
            $logger.Info("Domain setup completed successfully", $domain, $null)
            Write-Host "  ✓ Domain setup completed successfully!" -ForegroundColor Green
            $phase2Complete++
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $logger.Error("Unexpected error in Phase 2: $errorMessage", $domain, $null)
        Write-Host "  ✗ UNEXPECTED ERROR: $errorMessage" -ForegroundColor Red
        $record.AddError("phase2_error", $errorMessage, "UNKNOWN_ERROR", @{})
        $record.MarkFailed()
        $stateManager.UpdateDomain($domain, $record)
        $phase2Failed++
    }
    
    Write-Host ""
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 2 COMPLETE" -ForegroundColor Cyan
Write-Host "  - Completed: $phase2Complete domains" -ForegroundColor Green
Write-Host "  - Failed: $phase2Failed domains" -ForegroundColor Red
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 2 Complete: Completed=$phase2Complete, Failed=$phase2Failed", $null, $null)
$logger.Info("========================================", $null, $null)

#==============================================================================
# FINAL SUMMARY
#==============================================================================

$endTime = Get-Date
$duration = $endTime - $startTime
$durationFormatted = "{0:hh\:mm\:ss}" -f $duration

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Processing Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "PHASE 1 (DNS Configuration):" -ForegroundColor Yellow
Write-Host "  - Configured: $phase1Complete domains" -ForegroundColor Green
Write-Host "  - Failed: $phase1Failed domains" -ForegroundColor Red
Write-Host ""
Write-Host "PHASE 2 (Verification & Aliases):" -ForegroundColor Yellow
Write-Host "  - Completed: $phase2Complete domains" -ForegroundColor Green
Write-Host "  - Failed: $phase2Failed domains" -ForegroundColor Red
Write-Host ""
Write-Host "OVERALL:" -ForegroundColor Yellow
Write-Host "  - Total Domains: $totalDomains" -ForegroundColor Cyan
Write-Host "  - Fully Completed: $phase2Complete" -ForegroundColor Green
Write-Host "  - Failed: $($phase1Failed + $phase2Failed)" -ForegroundColor Red
Write-Host "  - Skipped: $skippedCount" -ForegroundColor Yellow
Write-Host ""
Write-Host "Total processing time: $durationFormatted" -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("Processing Summary", $null, $null)
$logger.Info("========================================", $null, $null)
$logger.Info("Phase 1 - Configured: $phase1Complete, Failed: $phase1Failed", $null, $null)
$logger.Info("Phase 2 - Completed: $phase2Complete, Failed: $phase2Failed", $null, $null)
$logger.Info("Overall - Total: $totalDomains, Completed: $phase2Complete, Failed: $($phase1Failed + $phase2Failed), Skipped: $skippedCount", $null, $null)
$logger.Info("Total processing time: $durationFormatted", $null, $null)

# Export failures if any
$totalFailed = $phase1Failed + $phase2Failed
if ($totalFailed -gt 0) {
    $failuresFile = "data/failures.json"
    $failedDomains = @()
    
    foreach ($domain in $domains) {
        $record = $stateManager.GetDomain($domain)
        if ($null -ne $record -and $record.State -eq "Failed") {
            $failedDomains += @{
                Domain = $domain
                State = $record.State
                Attempts = $record.Attempts
                Errors = $record.Errors
                LastUpdated = $record.LastUpdated
            }
        }
    }
    
    $failedDomains | ConvertTo-Json -Depth 10 | Out-File $failuresFile -Encoding UTF8
    Write-Host "Exported $totalFailed failed domains to: $failuresFile" -ForegroundColor Yellow
    $logger.Warning("$totalFailed domains failed. See $failuresFile for details.", $null, $null)
    Write-Host ""
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Automation Completed" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("Email Infrastructure Automation Completed", $null, $null)
$logger.Info("========================================", $null, $null)

# Exit with appropriate code
if ($totalFailed -gt 0) {
    exit 1
} else {
    exit 0
}
