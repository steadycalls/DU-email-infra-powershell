<#
.SYNOPSIS
    Automates email infrastructure setup for bulk domains using Forward Email and Cloudflare (Three-Phase Approach).

.DESCRIPTION
    This script processes domains in three efficient phases:
    
    PHASE 1 - DNS Configuration:
    1. Add each domain to Forward Email
    2. Configure DNS records in Cloudflare (TXT + MX)
    3. Remove old unquoted TXT records if they exist
    
    PHASE 2 - Verification (after DNS propagation):
    4. Verify domain ownership via DNS using GetDomain API
    5. Check for has_mx_record and has_txt_record status
    
    PHASE 3 - Alias Generation:
    6. Create info@ alias for each verified domain
    7. Generate 49 additional unique aliases (60% firstName, 40% firstName.lastName)
    8. Export all aliases to aliases.txt
    
    This three-phase approach is much faster than sequential processing because:
    - DNS records for all domains are configured first
    - DNS propagates while other domains are being configured
    - Verification happens in batch after propagation time
    - Aliases are generated only for verified domains

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
    Seconds to wait between Phase 1 and Phase 2 for DNS propagation (default: 180).

.PARAMETER DryRun
    If specified, performs validation only without making API calls.

.EXAMPLE
    .\Setup-EmailInfrastructure-ThreePhase.ps1 -DomainsFile "data/domains.txt"

.EXAMPLE
    .\Setup-EmailInfrastructure-ThreePhase.ps1 -DomainsFile "domains.txt" -DnsWaitTime 240

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
    [int]$DnsWaitTime = 180,
    
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

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Setup - Three-Phase Batch Processing" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Initialize configuration
try {
    $config = New-EmailInfraConfig -ConfigFile $ConfigFile
    Write-Host "[PASS] Configuration loaded" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize state manager
try {
    $stateManager = New-StateManager -StateFile $StateFile
    Write-Host "[PASS] State manager initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize state manager: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize logger
try {
    $logger = New-Logger -LogFile $LogFile -LogLevel $LogLevel
    Write-Host "[PASS] Logger initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize logger: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize API clients
try {
    $forwardEmailClient = New-ForwardEmailClient -Config $config
    Write-Host "[PASS] Forward Email client initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize Forward Email client: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    $cloudflareClient = New-CloudflareClient -Config $config
    Write-Host "[PASS] Cloudflare client initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize Cloudflare client: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Load domains
if (-not (Test-Path $DomainsFile)) {
    Write-Host "[FAIL] Domains file not found: $DomainsFile" -ForegroundColor Red
    exit 1
}

$domains = Get-Content $DomainsFile | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
$totalDomains = $domains.Count

Write-Host "Loaded $totalDomains domains from $DomainsFile" -ForegroundColor Green
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] Validation complete. Exiting." -ForegroundColor Yellow
    exit 0
}

$logger.Info("========================================", $null, $null)
$logger.Info("Email Infrastructure Setup Starting", $null, $null)
$logger.Info("Total Domains: $totalDomains", $null, $null)
$logger.Info("DNS Wait Time: ${DnsWaitTime}s", $null, $null)
$logger.Info("========================================", $null, $null)

#==============================================================================
# PHASE 1: DNS CONFIGURATION FOR ALL DOMAINS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 1: DNS Configuration (Batch)" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 1: DNS Configuration Starting", $null, $null)
$logger.Info("========================================", $null, $null)

$phase1Complete = 0
$phase1Failed = 0
$skippedCount = 0

$domainIndex = 0
foreach ($domain in $domains) {
    $domainIndex++
    
    # Load or create domain record
    $record = $stateManager.GetDomain($domain)
    if ($null -eq $record) {
        $record = $stateManager.CreateDomain($domain)
    }
    
    # Skip if already configured
    if ($record.State -in @("DnsConfigured", "Verified", "AliasesCreated", "Completed")) {
        $logger.Info("Domain already configured, skipping Phase 1", $domain, $null)
        $skippedCount++
        continue
    }
    
    Write-Host "[$domainIndex/$totalDomains] Processing: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("[$domain] Processing domain $domainIndex/$totalDomains (Phase 1)", $domain, $null)
    
    try {
        # Step 1: Add domain to Forward Email
        if ($record.State -eq "Pending") {
            Write-Host "  [1/3] Adding domain to Forward Email..." -ForegroundColor Yellow
            $logger.Info("Adding domain to Forward Email", $domain, $null)
            
            try {
                $forwardEmailDomain = $forwardEmailClient.CreateDomain($domain)
                $record.ForwardEmailDomainId = $forwardEmailDomain.id
                $record.State = "ForwardEmailAdded"
                $stateManager.UpdateDomain($domain, $record)
                $logger.Info("Domain added to Forward Email", $domain, @{DomainId = $forwardEmailDomain.id})
                Write-Host "        ✓ Domain added (ID: $($forwardEmailDomain.id))" -ForegroundColor Green
            }
            catch {
                $errorMessage = $_.Exception.Message
                $logger.Error("Failed to add domain to Forward Email: $errorMessage", $domain, $null)
                Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                $record.AddError("forward_email_add", $errorMessage, "FORWARD_EMAIL_ERROR", @{})
                $record.MarkFailed()
                $stateManager.UpdateDomain($domain, $record)
                $phase1Failed++
                continue
            }
        }
        
        # Step 2: Configure DNS records in Cloudflare
        if ($record.State -eq "ForwardEmailAdded") {
            Write-Host "  [2/3] Configuring DNS records in Cloudflare..." -ForegroundColor Yellow
            $logger.Info("Configuring DNS records", $domain, $null)
            
            try {
                # Get Cloudflare zone ID
                $zoneId = $cloudflareClient.GetZoneId($domain)
                $record.CloudflareZoneId = $zoneId
                $stateManager.UpdateDomain($domain, $record)
                $logger.Info("Found Cloudflare zone", $domain, @{ZoneId = $zoneId})
                Write-Host "        ✓ Found Cloudflare zone (ID: $zoneId)" -ForegroundColor Green
                
                # Remove old unquoted TXT records (if they exist)
                try {
                    $existingRecords = $cloudflareClient.ListDnsRecords($zoneId, "TXT", $domain)
                    foreach ($existingRecord in $existingRecords) {
                        if ($existingRecord.content -match "forward-email-site-verification=" -and $existingRecord.content -notmatch '^".*"$') {
                            $cloudflareClient.DeleteDnsRecord($zoneId, $existingRecord.id)
                            $logger.Info("Removed old unquoted TXT record", $domain, @{RecordId = $existingRecord.id})
                            Write-Host "        ✓ Removed old unquoted TXT record" -ForegroundColor Yellow
                        }
                    }
                }
                catch {
                    # Ignore errors when cleaning up old records
                    $logger.Warning("Could not clean up old records: $($_.Exception.Message)", $domain, $null)
                }
                
                # Add new quoted TXT verification record
                $txtValue = "`"forward-email-site-verification=$($record.ForwardEmailDomainId)`""
                $txtRecord = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "TXT", $txtValue, 3600)
                $logger.Info("Added TXT verification record", $domain, @{RecordId = $txtRecord.id})
                Write-Host "        ✓ Added TXT verification record (quoted)" -ForegroundColor Green
                
                # Add catch-all forwarding TXT record
                $catchAllValue = "`"forward-email=gmb@decisionsunlimited.io`""
                $catchAllRecord = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "TXT", $catchAllValue, 3600)
                $logger.Info("Added catch-all forwarding record", $domain, @{RecordId = $catchAllRecord.id})
                Write-Host "        ✓ Added catch-all forwarding (gmb@decisionsunlimited.io)" -ForegroundColor Green
                
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
# PHASE 2: VERIFICATION FOR ALL DOMAINS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 2: Domain Verification" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 2: Domain Verification Starting", $null, $null)
$logger.Info("========================================", $null, $null)

$phase2Complete = 0
$phase2Failed = 0

$domainIndex = 0
foreach ($domain in $domains) {
    $domainIndex++
    
    # Load domain record
    $record = $stateManager.GetDomain($domain)
    if ($null -eq $record) {
        continue
    }
    
    # Skip if already verified or completed
    if ($record.State -in @("Verified", "AliasesCreated", "Completed")) {
        $logger.Info("Domain already verified, skipping Phase 2", $domain, $null)
        $phase2Complete++
        continue
    }
    
    # Skip if not ready for Phase 2 (DNS not configured)
    if ($record.State -ne "DnsConfigured") {
        continue
    }
    
    Write-Host "[$domainIndex/$totalDomains] Verifying: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("[$domain] Verifying domain $domainIndex/$totalDomains (Phase 2)", $domain, $null)
    
    try {
        Write-Host "  [3/5] Verifying domain ownership..." -ForegroundColor Yellow
        $logger.Info("Verifying domain ownership", $domain, $null)
        
        $maxAttempts = 5
        $attemptDelay = 15
        $verified = $false
        
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Write-Host "        Attempt $attempt/$maxAttempts..." -ForegroundColor Gray
                
                # Use GetDomain instead of VerifyDomain to check status
                $domainInfo = $forwardEmailClient.GetDomain($domain)
                
                # Check if domain has required records verified
                if ($domainInfo.has_mx_record -and $domainInfo.has_txt_record) {
                    $verified = $true
                    $logger.Info("Domain ownership verified", $domain, @{
                        HasMX = $domainInfo.has_mx_record
                        HasTXT = $domainInfo.has_txt_record
                    })
                    Write-Host "        ✓ Domain ownership verified (MX + TXT records detected)" -ForegroundColor Green
                    break
                }
                else {
                    $missingRecords = @()
                    if (-not $domainInfo.has_mx_record) { $missingRecords += "MX" }
                    if (-not $domainInfo.has_txt_record) { $missingRecords += "TXT" }
                    $missing = $missingRecords -join ", "
                    Write-Host "        ⚠ Missing records: $missing" -ForegroundColor Yellow
                    $logger.Warning("Verification pending - missing records: $missing", $domain, $null)
                }
            }
            catch {
                $errorMsg = $_.Exception.Message
                $logger.Warning("Verification attempt $attempt failed: $errorMsg", $domain, $null)
                Write-Host "        ⚠ Attempt failed: $errorMsg" -ForegroundColor Yellow
            }
            
            if ($attempt -lt $maxAttempts) {
                Write-Host "        Waiting ${attemptDelay}s before retry..." -ForegroundColor Gray
                Start-Sleep -Seconds $attemptDelay
            }
        }
        
        if ($verified) {
            $record.State = "Verified"
            $stateManager.UpdateDomain($domain, $record)
            $phase2Complete++
            Write-Host "  ✓ Phase 2 complete for $domain" -ForegroundColor Green
        }
        else {
            $errorMessage = "Domain verification failed after $maxAttempts attempts - DNS records not detected by Forward Email"
            $logger.Error($errorMessage, $domain, $null)
            Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
            Write-Host "        ℹ DNS records may need more time to propagate globally" -ForegroundColor Gray
            $record.AddError("verification", $errorMessage, "VERIFICATION_ERROR", @{})
            $record.MarkFailed()
            $stateManager.UpdateDomain($domain, $record)
            $phase2Failed++
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
Write-Host "  - Verified: $phase2Complete domains" -ForegroundColor Green
Write-Host "  - Failed: $phase2Failed domains" -ForegroundColor Red
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 2 Complete: Verified=$phase2Complete, Failed=$phase2Failed", $null, $null)
$logger.Info("========================================", $null, $null)

#==============================================================================
# PHASE 3: ALIAS GENERATION FOR ALL VERIFIED DOMAINS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 3: Alias Generation" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 3: Alias Generation Starting", $null, $null)
$logger.Info("========================================", $null, $null)

# Load name lists for alias generation
$firstNames = @(
    "james", "john", "robert", "michael", "william", "david", "richard", "joseph", "thomas", "charles",
    "christopher", "daniel", "matthew", "anthony", "donald", "mark", "paul", "steven", "andrew", "kenneth",
    "joshua", "kevin", "brian", "george", "edward", "ronald", "timothy", "jason", "jeffrey", "ryan",
    "jacob", "gary", "nicholas", "eric", "jonathan", "stephen", "larry", "justin", "scott", "brandon",
    "benjamin", "samuel", "frank", "gregory", "raymond", "alexander", "patrick", "jack", "dennis", "jerry",
    "mary", "patricia", "jennifer", "linda", "barbara", "elizabeth", "susan", "jessica", "sarah", "karen",
    "nancy", "lisa", "betty", "margaret", "sandra", "ashley", "kimberly", "emily", "donna", "michelle",
    "dorothy", "carol", "amanda", "melissa", "deborah", "stephanie", "rebecca", "sharon", "laura", "cynthia",
    "kathleen", "amy", "angela", "shirley", "anna", "brenda", "pamela", "emma", "nicole", "helen",
    "samantha", "katherine", "christine", "debra", "rachel", "catherine", "carolyn", "janet", "ruth", "maria"
)

$lastNames = @(
    "smith", "johnson", "williams", "brown", "jones", "garcia", "miller", "davis", "rodriguez", "martinez",
    "hernandez", "lopez", "gonzalez", "wilson", "anderson", "thomas", "taylor", "moore", "jackson", "martin",
    "lee", "perez", "thompson", "white", "harris", "sanchez", "clark", "ramirez", "lewis", "robinson",
    "walker", "young", "allen", "king", "wright", "scott", "torres", "nguyen", "hill", "flores",
    "green", "adams", "nelson", "baker", "hall", "rivera", "campbell", "mitchell", "carter", "roberts",
    "gomez", "phillips", "evans", "turner", "diaz", "parker", "cruz", "edwards", "collins", "reyes",
    "stewart", "morris", "morales", "murphy", "cook", "rogers", "gutierrez", "ortiz", "morgan", "cooper",
    "peterson", "bailey", "reed", "kelly", "howard", "ramos", "kim", "cox", "ward", "richardson",
    "watson", "brooks", "chavez", "wood", "james", "bennett", "gray", "mendoza", "ruiz", "hughes",
    "price", "alvarez", "castillo", "sanders", "patel", "myers", "long", "ross", "foster", "jimenez"
)

# Track used aliases globally
$usedAliases = @{}

# Function to generate unique alias
function Get-UniqueAlias {
    param(
        [string]$Domain,
        [bool]$UseFullName
    )
    
    $maxAttempts = 100
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        if ($UseFullName) {
            $firstName = $firstNames | Get-Random
            $lastName = $lastNames | Get-Random
            $alias = "$firstName.$lastName"
        }
        else {
            $alias = $firstNames | Get-Random
        }
        
        $fullEmail = "$alias@$Domain"
        
        if (-not $usedAliases.ContainsKey($fullEmail)) {
            $usedAliases[$fullEmail] = $true
            return $alias
        }
    }
    
    # Fallback: append random number
    $alias = "$alias$(Get-Random -Minimum 1000 -Maximum 9999)"
    $fullEmail = "$alias@$Domain"
    $usedAliases[$fullEmail] = $true
    return $alias
}

$phase3Complete = 0
$phase3Failed = 0
$allAliases = @()

$domainIndex = 0
foreach ($domain in $domains) {
    $domainIndex++
    
    # Load domain record
    $record = $stateManager.GetDomain($domain)
    if ($null -eq $record) {
        continue
    }
    
    # Skip if already has aliases or completed
    if ($record.State -in @("AliasesCreated", "Completed")) {
        $logger.Info("Domain already has aliases, skipping Phase 3", $domain, $null)
        $phase3Complete++
        
        # Add existing aliases to export list
        if ($record.Aliases.Count -gt 0) {
            foreach ($alias in $record.Aliases) {
                $allAliases += "$alias@$domain"
            }
        }
        continue
    }
    
    # Skip if not verified
    if ($record.State -ne "Verified") {
        continue
    }
    
    Write-Host "[$domainIndex/$totalDomains] Creating aliases for: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("[$domain] Creating aliases $domainIndex/$totalDomains (Phase 3)", $domain, $null)
    
    try {
        Write-Host "  [4/5] Creating email aliases..." -ForegroundColor Yellow
        $logger.Info("Creating email aliases", $domain, $null)
        
        $domainAliases = @()
        $recipient = "gmb@decisionsunlimited.io"
        
        # Create info@ alias first
        try {
            Write-Host "        Creating info@ alias..." -ForegroundColor Gray
            $infoAlias = $forwardEmailClient.CreateAlias($domain, "info", @($recipient), "Info alias", @())
            $domainAliases += "info"
            $allAliases += "info@$domain"
            $logger.Info("Created info@ alias", $domain, @{AliasId = $infoAlias.id})
            Write-Host "        ✓ Created info@$domain" -ForegroundColor Green
        }
        catch {
            $logger.Warning("Failed to create info@ alias: $($_.Exception.Message)", $domain, $null)
            Write-Host "        ⚠ Failed to create info@ (may already exist)" -ForegroundColor Yellow
        }
        
        # Generate 49 additional unique aliases (60% firstName, 40% firstName.lastName)
        Write-Host "        Generating 49 unique aliases..." -ForegroundColor Gray
        $aliasesCreated = 0
        $aliasesTarget = 49
        
        for ($i = 0; $i -lt $aliasesTarget; $i++) {
            try {
                # 60% chance for firstName only, 40% for firstName.lastName
                $useFullName = (Get-Random -Minimum 1 -Maximum 100) -le 40
                $aliasName = Get-UniqueAlias -Domain $domain -UseFullName $useFullName
                
                $newAlias = $forwardEmailClient.CreateAlias($domain, $aliasName, @($recipient), "Generated alias", @())
                $domainAliases += $aliasName
                $allAliases += "$aliasName@$domain"
                $aliasesCreated++
                
                if (($aliasesCreated % 10) -eq 0) {
                    Write-Host "        ✓ Created $aliasesCreated/$aliasesTarget aliases" -ForegroundColor Green
                }
            }
            catch {
                $logger.Warning("Failed to create alias $aliasName: $($_.Exception.Message)", $domain, $null)
            }
        }
        
        Write-Host "        ✓ Created $aliasesCreated aliases total" -ForegroundColor Green
        
        $record.Aliases = $domainAliases
        $record.State = "AliasesCreated"
        $stateManager.UpdateDomain($domain, $record)
        $phase3Complete++
        Write-Host "  ✓ Phase 3 complete for $domain" -ForegroundColor Green
    }
    catch {
        $errorMessage = $_.Exception.Message
        $logger.Error("Unexpected error in Phase 3: $errorMessage", $domain, $null)
        Write-Host "  ✗ UNEXPECTED ERROR: $errorMessage" -ForegroundColor Red
        $record.AddError("phase3_error", $errorMessage, "ALIAS_ERROR", @{})
        $record.MarkFailed()
        $stateManager.UpdateDomain($domain, $record)
        $phase3Failed++
    }
    
    Write-Host ""
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "PHASE 3 COMPLETE" -ForegroundColor Cyan
Write-Host "  - Aliases Created: $phase3Complete domains" -ForegroundColor Green
Write-Host "  - Failed: $phase3Failed domains" -ForegroundColor Red
Write-Host "  - Total Aliases: $($allAliases.Count)" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$logger.Info("========================================", $null, $null)
$logger.Info("PHASE 3 Complete: Created=$phase3Complete, Failed=$phase3Failed, TotalAliases=$($allAliases.Count)", $null, $null)
$logger.Info("========================================", $null, $null)

# Export aliases to file
$aliasesFile = Join-Path $PSScriptRoot "data/aliases.txt"
$allAliases | Sort-Object | Out-File -FilePath $aliasesFile -Encoding UTF8
Write-Host "✓ Exported $($allAliases.Count) aliases to: $aliasesFile" -ForegroundColor Green
$logger.Info("Exported aliases to file", $null, @{Count = $allAliases.Count; File = $aliasesFile})

#==============================================================================
# FINAL SUMMARY
#==============================================================================

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "AUTOMATION COMPLETE" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "Phase 1 (DNS Configuration):" -ForegroundColor Yellow
Write-Host "  - Configured: $phase1Complete" -ForegroundColor Green
Write-Host "  - Failed: $phase1Failed" -ForegroundColor Red
Write-Host ""
Write-Host "Phase 2 (Verification):" -ForegroundColor Yellow
Write-Host "  - Verified: $phase2Complete" -ForegroundColor Green
Write-Host "  - Failed: $phase2Failed" -ForegroundColor Red
Write-Host ""
Write-Host "Phase 3 (Aliases):" -ForegroundColor Yellow
Write-Host "  - Created: $phase3Complete" -ForegroundColor Green
Write-Host "  - Failed: $phase3Failed" -ForegroundColor Red
Write-Host "  - Total Aliases: $($allAliases.Count)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Files:" -ForegroundColor Yellow
Write-Host "  - State: $StateFile" -ForegroundColor Gray
Write-Host "  - Aliases: $aliasesFile" -ForegroundColor Gray
Write-Host "  - Logs: $LogFile" -ForegroundColor Gray
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan

$logger.Info("========================================", $null, $null)
$logger.Info("AUTOMATION COMPLETE", $null, $null)
$logger.Info("Phase1: Configured=$phase1Complete, Failed=$phase1Failed", $null, $null)
$logger.Info("Phase2: Verified=$phase2Complete, Failed=$phase2Failed", $null, $null)
$logger.Info("Phase3: Created=$phase3Complete, Failed=$phase3Failed, TotalAliases=$($allAliases.Count)", $null, $null)
$logger.Info("========================================", $null, $null)
