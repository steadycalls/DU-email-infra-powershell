<#
.SYNOPSIS
    Phase 4 Pass 1: Audit and Update Alias Passwords

.DESCRIPTION
    This script audits all aliases for domains in domains.txt and updates
    their passwords to a consistent value.
    
    PHASE 4 PASS 1 - Alias Password Audit:
    1. Read domains from domains.txt
    2. For each domain, retrieve all aliases
    3. Update password for each alias to the specified value
    4. Export audit results to CSV
    
    This script is useful for:
    - Setting passwords on existing aliases
    - Fixing aliases that failed password setting during Pass 2
    - Ensuring all aliases have consistent passwords

.PARAMETER DomainsFile
    Path to text file containing list of domains (one per line).
    Default: data/domains.txt

.PARAMETER LogFile
    Path to log file.
    Default: logs/phase4-pass1-audit-aliases.log

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL.
    Default: INFO

.PARAMETER AliasPassword
    Password to set for all aliases.
    Default: 474d6dc122cde69b6cd8b3a1

.PARAMETER MaxRetries
    Maximum number of retry attempts per alias (default: 3).

.PARAMETER InitialRetryDelay
    Initial delay in seconds before first retry (default: 5).

.PARAMETER DryRun
    If specified, performs audit only without updating passwords.

.EXAMPLE
    .\Phase4-Pass1-AuditAliases.ps1

.EXAMPLE
    .\Phase4-Pass1-AuditAliases.ps1 -DryRun

.EXAMPLE
    .\Phase4-Pass1-AuditAliases.ps1 -AliasPassword "custom-password"

.NOTES
    Author: Email Infrastructure Automation
    Version: 1.0
    Requires: ForwardEmailClient, Logger modules
    Environment Variables: FORWARD_EMAIL_API_KEY
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainsFile = "data/domains.txt",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/phase4-pass1-audit-aliases.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [string]$AliasPassword = "474d6dc122cde69b6cd8b3a1",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 3,
    
    [Parameter(Mandatory=$false)]
    [int]$InitialRetryDelay = 5,
    
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
Import-Module (Join-Path $modulesPath "Logger.psm1") -Force

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Phase 4 Pass 1: Audit and Update Alias Passwords" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE] No passwords will be updated" -ForegroundColor Yellow
    Write-Host ""
}

# Initialize logger
try {
    $logger = New-Logger -LogFile $LogFile -MinLevel $LogLevel
    Write-Host "[PASS] Logger initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize logger: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check API key
Write-Host "[CHECK] Verifying API key..." -ForegroundColor Yellow
if (-not $env:FORWARD_EMAIL_API_KEY) {
    Write-Host "[FAIL] FORWARD_EMAIL_API_KEY environment variable not set" -ForegroundColor Red
    $logger.Error("FORWARD_EMAIL_API_KEY not set", $null, $null)
    exit 1
}
Write-Host "[PASS] Forward Email API key found" -ForegroundColor Green

# Initialize Forward Email client
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

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

function Update-AliasPassword {
    param(
        [string]$Domain,
        [object]$Alias,
        [string]$Password,
        [object]$Client,
        [object]$Logger,
        [int]$MaxRetries,
        [int]$InitialDelay
    )
    
    $attempt = 0
    $success = $false
    $lastError = $null
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        
        if ($attempt -gt 1) {
            $delay = $InitialDelay * [Math]::Pow(2, $attempt - 2)
            Start-Sleep -Seconds $delay
        }
        
        try {
            $Client.GenerateAliasPassword($Domain, $Alias.id, $Password, $true) | Out-Null
            $success = $true
            return @{
                Success = $true
                Attempts = $attempt
                Error = $null
            }
        }
        catch {
            $lastError = $_.Exception.Message
            if ($attempt -ge $MaxRetries) {
                $Logger.Warning("Failed to update password for $($Alias.name)@$Domain after $attempt attempts: $lastError", $Domain, $null)
            }
        }
    }
    
    return @{
        Success = $false
        Attempts = $attempt
        Error = $lastError
    }
}

#==============================================================================
# PHASE 4 PASS 1: AUDIT AND UPDATE ALIAS PASSWORDS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Phase 4 Pass 1: Auditing and Updating Alias Passwords" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$auditResults = @()
$totalAliases = 0
$successCount = 0
$failedCount = 0
$skippedCount = 0

for ($i = 0; $i -lt $totalDomains; $i++) {
    $domain = $domains[$i]
    $domainIndex = $i + 1
    
    Write-Host "[$domainIndex/$totalDomains] Processing domain: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("Processing domain $domainIndex/$totalDomains", $domain, $null)
    
    try {
        # Retrieve all aliases for the domain
        Write-Host "  [1/2] Retrieving aliases..." -ForegroundColor Yellow
        $aliasesResponse = $forwardEmailClient.ListAliases($domain)
        
        # Handle pagination response
        $aliases = if ($aliasesResponse -is [array]) {
            $aliasesResponse
        } elseif ($aliasesResponse.PSObject.Properties.Name -contains 'results') {
            $aliasesResponse.results
        } else {
            @($aliasesResponse)
        }
        
        $aliasCount = $aliases.Count
        $totalAliases += $aliasCount
        
        Write-Host "        ✓ Found $aliasCount aliases" -ForegroundColor Green
        $logger.Info("Found aliases", $domain, @{Count = $aliasCount})
        
        if ($aliasCount -eq 0) {
            Write-Host "        → No aliases to update" -ForegroundColor Cyan
            $skippedCount++
            continue
        }
        
        # Update password for each alias
        Write-Host "  [2/2] Updating passwords..." -ForegroundColor Yellow
        
        $domainSuccess = 0
        $domainFailed = 0
        
        foreach ($alias in $aliases) {
            $aliasName = $alias.name
            $aliasId = $alias.id
            
            if ($DryRun) {
                Write-Host "        [DRY RUN] Would update password for: $aliasName@$domain" -ForegroundColor Yellow
                $auditResults += [PSCustomObject]@{
                    Domain = $domain
                    Alias = "$aliasName@$domain"
                    AliasId = $aliasId
                    Status = "DryRun"
                    Attempts = 0
                    Error = ""
                }
                continue
            }
            
            $result = Update-AliasPassword `
                -Domain $domain `
                -Alias $alias `
                -Password $AliasPassword `
                -Client $forwardEmailClient `
                -Logger $logger `
                -MaxRetries $MaxRetries `
                -InitialDelay $InitialRetryDelay
            
            if ($result.Success) {
                $domainSuccess++
                $successCount++
                $auditResults += [PSCustomObject]@{
                    Domain = $domain
                    Alias = "$aliasName@$domain"
                    AliasId = $aliasId
                    Status = "Success"
                    Attempts = $result.Attempts
                    Error = ""
                }
            }
            else {
                $domainFailed++
                $failedCount++
                $auditResults += [PSCustomObject]@{
                    Domain = $domain
                    Alias = "$aliasName@$domain"
                    AliasId = $aliasId
                    Status = "Failed"
                    Attempts = $result.Attempts
                    Error = $result.Error
                }
            }
        }
        
        if (-not $DryRun) {
            Write-Host "        ✓ Updated: $domainSuccess | ✗ Failed: $domainFailed" -ForegroundColor $(if ($domainFailed -eq 0) { "Green" } else { "Yellow" })
        }
        
        $logger.Info("Completed domain", $domain, @{Success = $domainSuccess; Failed = $domainFailed})
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "  ✗ ERROR: Failed to process domain: $errorMessage" -ForegroundColor Red
        $logger.Error("Failed to process domain: $errorMessage", $domain, $null)
        
        $auditResults += [PSCustomObject]@{
            Domain = $domain
            Alias = "N/A"
            AliasId = "N/A"
            Status = "DomainError"
            Attempts = 0
            Error = $errorMessage
        }
    }
    
    Write-Host ""
}

#==============================================================================
# EXPORT RESULTS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Exporting Audit Results" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$resultsFile = Join-Path $scriptRoot "data/phase4-pass1-audit-results.csv"
$dataDir = Split-Path -Parent $resultsFile
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$auditResults | Export-Csv -Path $resultsFile -NoTypeInformation -Encoding UTF8
Write-Host "✓ Exported audit results to: $resultsFile" -ForegroundColor Green
$logger.Info("Exported audit results", $null, @{File = $resultsFile; Count = $auditResults.Count})

#==============================================================================
# SUMMARY
#==============================================================================

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Phase 4 Pass 1 Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Total Domains:       $totalDomains" -ForegroundColor White
Write-Host "Total Aliases:       $totalAliases" -ForegroundColor White

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY RUN] No passwords were updated" -ForegroundColor Yellow
}
else {
    Write-Host "✓ Successful:        $successCount" -ForegroundColor Green
    Write-Host "✗ Failed:            $failedCount" -ForegroundColor Red
    Write-Host "→ Skipped (no aliases): $skippedCount" -ForegroundColor Cyan
}

Write-Host ""

if ($failedCount -gt 0 -and -not $DryRun) {
    Write-Host "Failed Aliases:" -ForegroundColor Red
    $failedAliases = $auditResults | Where-Object { $_.Status -eq "Failed" }
    foreach ($failed in $failedAliases | Select-Object -First 10) {
        Write-Host "  - $($failed.Alias): $($failed.Error)" -ForegroundColor Red
    }
    if ($failedAliases.Count -gt 10) {
        Write-Host "  ... and $($failedAliases.Count - 10) more (see CSV for full list)" -ForegroundColor Red
    }
    Write-Host ""
}

# Retry statistics
if (-not $DryRun) {
    $firstAttempt = ($auditResults | Where-Object { $_.Status -eq "Success" -and $_.Attempts -eq 1 }).Count
    $retriedSuccess = ($auditResults | Where-Object { $_.Status -eq "Success" -and $_.Attempts -gt 1 }).Count
    
    Write-Host "Retry Statistics:" -ForegroundColor Cyan
    Write-Host "  First attempt:  $firstAttempt aliases" -ForegroundColor Green
    Write-Host "  After retries:  $retriedSuccess aliases" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Complete!" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "Audit results have been exported to:" -ForegroundColor Green
Write-Host "  $resultsFile" -ForegroundColor Cyan
Write-Host ""

$logger.Info("Phase 4 Pass 1 complete", $null, @{
    TotalDomains = $totalDomains
    TotalAliases = $totalAliases
    Success = $successCount
    Failed = $failedCount
    Skipped = $skippedCount
    DryRun = $DryRun.IsPresent
})
