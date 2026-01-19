<#
.SYNOPSIS
    Pass 1: Enable Enhanced Protection and Configure DNS for all domains.

.DESCRIPTION
    This script performs the first pass of email infrastructure setup:
    
    PASS 1 - Enhanced Protection & DNS Configuration:
    1. Read domains from domains.txt
    2. Add each domain to Forward Email (if not already added)
    3. Enable Enhanced Protection for each domain
    4. Extract unique verification strings
    5. Configure DNS records in Cloudflare with DNS-only mode
    
    After this pass completes, wait 5-10 minutes for DNS propagation,
    then run Pass2-AliasCreation.ps1 to create email aliases.

.PARAMETER DomainsFile
    Path to text file containing list of domains (one per line).
    Default: data/domains.txt

.PARAMETER LogFile
    Path to log file.
    Default: logs/pass1-enhanced-protection.log

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL.
    Default: INFO

.PARAMETER DryRun
    If specified, performs validation only without making API calls.

.EXAMPLE
    .\Pass1-EnhancedProtection-DNS.ps1

.EXAMPLE
    .\Pass1-EnhancedProtection-DNS.ps1 -DomainsFile "my-domains.txt" -DryRun

.NOTES
    Author: Email Infrastructure Automation
    Version: 1.0
    Requires: ForwardEmailClient, CloudflareClient, Logger modules
    Environment Variables: FORWARD_EMAIL_API_KEY, CLOUDFLARE_API_TOKEN
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainsFile = "data/domains.txt",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/pass1-enhanced-protection.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

#==============================================================================
# INITIALIZATION
#==============================================================================

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
$modulesPath = Join-Path $scriptRoot "modules"
Import-Module (Join-Path $modulesPath "ForwardEmailClient.psm1") -Force
Import-Module (Join-Path $modulesPath "CloudflareClient.psm1") -Force
Import-Module (Join-Path $modulesPath "Logger.psm1") -Force

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Pass 1: Enhanced Protection & DNS Configuration" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Initialize logger
try {
    $logger = New-Logger -LogFile $LogFile -MinLevel $LogLevel
    Write-Host "[PASS] Logger initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize logger: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check API keys
Write-Host "[CHECK] Verifying API keys..." -ForegroundColor Yellow
if (-not $env:FORWARD_EMAIL_API_KEY) {
    Write-Host "[FAIL] FORWARD_EMAIL_API_KEY environment variable not set" -ForegroundColor Red
    $logger.Error("FORWARD_EMAIL_API_KEY not set", $null, $null)
    exit 1
}
Write-Host "[PASS] Forward Email API key found" -ForegroundColor Green

if (-not $env:CLOUDFLARE_API_TOKEN) {
    Write-Host "[FAIL] CLOUDFLARE_API_TOKEN environment variable not set" -ForegroundColor Red
    $logger.Error("CLOUDFLARE_API_TOKEN not set", $null, $null)
    exit 1
}
Write-Host "[PASS] Cloudflare API token found" -ForegroundColor Green

# Initialize API clients
try {
    $retryConfig = @{
        MaxRetries = 5
        InitialRetryDelay = 5
        MaxRetryDelay = 300
        RateLimitDelay = 60
    }
    $forwardEmailClient = New-ForwardEmailClient -ApiKey $env:FORWARD_EMAIL_API_KEY -RetryConfig $retryConfig
    Write-Host "[PASS] Forward Email client initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize Forward Email client: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    $cloudflareClient = New-CloudflareClient -ApiToken $env:CLOUDFLARE_API_TOKEN -RetryConfig $retryConfig
    Write-Host "[PASS] Cloudflare client initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize Cloudflare client: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

#==============================================================================
# LOAD DOMAINS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Loading Domains" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$domainsFilePath = if ([System.IO.Path]::IsPathRooted($DomainsFile)) {
    $DomainsFile
} else {
    Join-Path $scriptRoot $DomainsFile
}

if (-not (Test-Path $domainsFilePath)) {
    Write-Host "[FAIL] Domains file not found: $domainsFilePath" -ForegroundColor Red
    $logger.Error("Domains file not found", $null, @{Path = $domainsFilePath})
    exit 1
}

$domains = Get-Content $domainsFilePath | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
$totalDomains = $domains.Count

Write-Host "✓ Loaded $totalDomains domains from: $domainsFilePath" -ForegroundColor Green
$logger.Info("Loaded domains", $null, @{Count = $totalDomains; File = $domainsFilePath})
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] Would process $totalDomains domains" -ForegroundColor Yellow
    Write-Host ""
    foreach ($domain in $domains) {
        Write-Host "  - $domain" -ForegroundColor Gray
    }
    exit 0
}

#==============================================================================
# PASS 1: ENHANCED PROTECTION & DNS CONFIGURATION
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Pass 1: Enhanced Protection & DNS Configuration" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failedCount = 0
$skippedCount = 0
$results = @()

for ($i = 0; $i -lt $totalDomains; $i++) {
    $domain = $domains[$i]
    $domainIndex = $i + 1
    
    Write-Host "[$domainIndex/$totalDomains] Processing: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("Processing domain $domainIndex/$totalDomains", $domain, $null)
    
    $result = @{
        Domain = $domain
        Success = $false
        ForwardEmailDomainId = $null
        VerificationRecord = $null
        EnhancedProtectionEnabled = $false
        DnsConfigured = $false
        Error = $null
    }
    
    try {
        # Step 1: Get or create domain in Forward Email with Enhanced Protection
        Write-Host "  [1/3] Getting domain from Forward Email..." -ForegroundColor Yellow
        try {
            $forwardEmailDomain = $forwardEmailClient.GetDomain($domain)
            $result.ForwardEmailDomainId = $forwardEmailDomain.id
            $logger.Info("Domain found in Forward Email", $domain, @{DomainId = $forwardEmailDomain.id})
            Write-Host "        ✓ Domain found (ID: $($forwardEmailDomain.id))" -ForegroundColor Green
        }
        catch {
            # Domain doesn't exist, create it with Enhanced Protection
            Write-Host "        → Domain not found, creating with Enhanced Protection..." -ForegroundColor Cyan
            try {
                $forwardEmailDomain = $forwardEmailClient.CreateDomain($domain, "enhanced_protection")
                $result.ForwardEmailDomainId = $forwardEmailDomain.id
                $result.EnhancedProtectionEnabled = $true
                $result.VerificationRecord = $forwardEmailDomain.verification_record
                $logger.Info("Domain created with Enhanced Protection", $domain, @{DomainId = $forwardEmailDomain.id; VerificationRecord = $forwardEmailDomain.verification_record})
                Write-Host "        ✓ Domain created with Enhanced Protection (ID: $($forwardEmailDomain.id))" -ForegroundColor Green
                Write-Host "        → Verification string: $($forwardEmailDomain.verification_record)" -ForegroundColor Cyan
            }
            catch {
                $errorMessage = $_.Exception.Message
                $logger.Error("Failed to create domain: $errorMessage", $domain, $null)
                Write-Host "        ✗ ERROR: Failed to create domain: $errorMessage" -ForegroundColor Red
                throw "Failed to create domain: $domain"
            }
        }
        
        # Step 2: Enable Enhanced Protection (if not already enabled during creation)
        if (-not $result.EnhancedProtectionEnabled) {
            Write-Host "  [2/3] Enabling Enhanced Protection..." -ForegroundColor Yellow
            try {
                $enhancedDomain = $forwardEmailClient.EnableEnhancedProtection($domain)
                $result.EnhancedProtectionEnabled = $true
                $result.VerificationRecord = $enhancedDomain.verification_record
                $logger.Info("Enhanced Protection enabled", $domain, @{VerificationRecord = $enhancedDomain.verification_record})
                Write-Host "        ✓ Enhanced Protection enabled" -ForegroundColor Green
                Write-Host "        → Verification string: $($enhancedDomain.verification_record)" -ForegroundColor Cyan
            }
            catch {
                $errorMessage = $_.Exception.Message
                $logger.Warning("Failed to enable Enhanced Protection: $errorMessage", $domain, $null)
                Write-Host "        ⚠ Warning: Could not enable Enhanced Protection: $errorMessage" -ForegroundColor Yellow
                Write-Host "        → Will use domain ID for verification" -ForegroundColor Cyan
                # Continue with domain ID as fallback
                $result.VerificationRecord = $result.ForwardEmailDomainId
            }
        }
        else {
            Write-Host "  [2/3] Enhanced Protection already enabled during creation" -ForegroundColor Green
        }
        
        # Step 3: Configure DNS in Cloudflare
        Write-Host "  [3/3] Configuring DNS records in Cloudflare..." -ForegroundColor Yellow
        try {
            # Get Cloudflare zone ID
            $zoneId = $cloudflareClient.GetZoneId($domain)
            $logger.Info("Found Cloudflare zone", $domain, @{ZoneId = $zoneId})
            Write-Host "        ✓ Found Cloudflare zone (ID: $zoneId)" -ForegroundColor Green
            
            # Remove old unquoted TXT records (if they exist)
            try {
                $existingRecords = $cloudflareClient.ListDnsRecords($zoneId, "TXT", $domain)
                foreach ($existingRecord in $existingRecords.result) {
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
            
            # Add TXT verification record (with Enhanced Protection string)
            $verificationString = $result.VerificationRecord
            $txtValue = "`"forward-email-site-verification=$verificationString`""
            $txtRecord = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "TXT", $txtValue, 3600, $null, $false)
            $logger.Info("Added TXT verification record", $domain, @{RecordId = $txtRecord.id; EnhancedProtection = $result.EnhancedProtectionEnabled})
            Write-Host "        ✓ Added TXT verification record (DNS only, quoted)" -ForegroundColor Green
            
            # Add catch-all forwarding TXT record
            $catchAllValue = "`"forward-email=gmb@decisionsunlimited.io`""
            $catchAllRecord = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "TXT", $catchAllValue, 3600, $null, $false)
            $logger.Info("Added catch-all forwarding record", $domain, @{RecordId = $catchAllRecord.id})
            Write-Host "        ✓ Added catch-all forwarding (DNS only, gmb@decisionsunlimited.io)" -ForegroundColor Green
            
            # Add MX records (both priority 10, DNS only)
            $mx1 = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "MX", "mx1.forwardemail.net", 3600, 10, $false)
            $mx2 = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "MX", "mx2.forwardemail.net", 3600, 10, $false)
            $logger.Info("Added MX records", $domain, @{MX1 = $mx1.id; MX2 = $mx2.id})
            Write-Host "        ✓ Added MX records (DNS only, mx1 + mx2 priority 10)" -ForegroundColor Green
            
            $result.DnsConfigured = $true
            $result.Success = $true
            $successCount++
            Write-Host "  ✓ Pass 1 complete for $domain" -ForegroundColor Green
        }
        catch {
            $errorMessage = $_.Exception.Message
            $logger.Error("Failed to configure DNS: $errorMessage", $domain, $null)
            Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
            $result.Error = "DNS configuration failed: $errorMessage"
            $failedCount++
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $logger.Error("Failed to process domain: $errorMessage", $domain, $null)
        Write-Host "  ✗ ERROR: $errorMessage" -ForegroundColor Red
        $result.Error = $errorMessage
        $failedCount++
    }
    
    $results += $result
    Write-Host ""
}

#==============================================================================
# SUMMARY
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Pass 1 Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Total Domains:    $totalDomains" -ForegroundColor White
Write-Host "✓ Successful:     $successCount" -ForegroundColor Green
Write-Host "✗ Failed:         $failedCount" -ForegroundColor Red
Write-Host ""

if ($failedCount -gt 0) {
    Write-Host "Failed Domains:" -ForegroundColor Red
    foreach ($result in $results) {
        if (-not $result.Success) {
            Write-Host "  - $($result.Domain): $($result.Error)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

Write-Host "Enhanced Protection Summary:" -ForegroundColor Cyan
$enhancedCount = ($results | Where-Object { $_.EnhancedProtectionEnabled }).Count
Write-Host "  Enabled:  $enhancedCount domains" -ForegroundColor Green
Write-Host "  Fallback: $($successCount - $enhancedCount) domains (using domain ID)" -ForegroundColor Yellow
Write-Host ""

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Next Steps" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Wait 5-10 minutes for DNS propagation" -ForegroundColor Yellow
Write-Host "2. Verify domains in Forward Email dashboard:" -ForegroundColor Yellow
Write-Host "   https://forwardemail.net/my-account/domains" -ForegroundColor Cyan
Write-Host "3. Run Pass 2 to create aliases:" -ForegroundColor Yellow
Write-Host "   .\Pass2-AliasCreation.ps1" -ForegroundColor Cyan
Write-Host ""

$logger.Info("Pass 1 complete", $null, @{Total = $totalDomains; Success = $successCount; Failed = $failedCount; Enhanced = $enhancedCount})
