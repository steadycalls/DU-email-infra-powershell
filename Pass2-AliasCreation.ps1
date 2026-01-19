<#
.SYNOPSIS
    Pass 2: Create Email Aliases with Retry Logic

.DESCRIPTION
    This script performs the second pass of email infrastructure setup:
    
    PASS 2 - Alias Creation (with retry logic):
    1. Read domains from domains.txt
    2. For each domain, attempt to create aliases
    3. Retry up to 3 times with exponential backoff if creation fails
    4. Move on to next domain after 3 failed attempts
    5. Export all created aliases to aliases.txt
    
    Run this script after Pass1-EnhancedProtection-DNS.ps1 and after
    waiting 5-10 minutes for DNS propagation.

.PARAMETER DomainsFile
    Path to text file containing list of domains (one per line).
    Default: data/domains.txt

.PARAMETER LogFile
    Path to log file.
    Default: logs/pass2-alias-creation.log

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL.
    Default: INFO

.PARAMETER AliasCount
    Number of aliases to generate per domain (default: 50, includes info@).

.PARAMETER FirstNamePercent
    Percentage of aliases using firstName only format (default: 60).

.PARAMETER MaxRetries
    Maximum number of retry attempts per domain (default: 3).

.PARAMETER InitialRetryDelay
    Initial delay in seconds before first retry (default: 10).

.PARAMETER DryRun
    If specified, performs validation only without making API calls.

.EXAMPLE
    .\Pass2-AliasCreation.ps1

.EXAMPLE
    .\Pass2-AliasCreation.ps1 -DomainsFile "verified-domains.txt"

.EXAMPLE
    .\Pass2-AliasCreation.ps1 -AliasCount 100 -MaxRetries 5

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
    [string]$LogFile = "logs/pass2-alias-creation.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [int]$AliasCount = 50,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 100)]
    [int]$FirstNamePercent = 60,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 3,
    
    [Parameter(Mandatory=$false)]
    [int]$InitialRetryDelay = 10,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

#==============================================================================
# INITIALIZATION
#==============================================================================

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
Import-Module (Join-Path $scriptRoot "ForwardEmailClient.psm1") -Force
Import-Module (Join-Path $scriptRoot "Logger.psm1") -Force

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Pass 2: Alias Creation with Retry Logic" -ForegroundColor Cyan
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

if ($DryRun) {
    Write-Host "[DRY RUN] Would create $AliasCount aliases for $totalDomains domains" -ForegroundColor Yellow
    exit 0
}

#==============================================================================
# LOAD NAME DATA
#==============================================================================

# Common first names for alias generation
$firstNames = @(
    "james", "john", "robert", "michael", "william", "david", "richard", "joseph", "thomas", "charles",
    "mary", "patricia", "jennifer", "linda", "barbara", "elizabeth", "susan", "jessica", "sarah", "karen",
    "christopher", "daniel", "matthew", "anthony", "mark", "donald", "steven", "paul", "andrew", "joshua",
    "nancy", "betty", "margaret", "sandra", "ashley", "kimberly", "emily", "donna", "michelle", "dorothy",
    "kevin", "brian", "george", "edward", "ronald", "timothy", "jason", "jeffrey", "ryan", "jacob"
)

$lastNames = @(
    "smith", "johnson", "williams", "brown", "jones", "garcia", "miller", "davis", "rodriguez", "martinez",
    "hernandez", "lopez", "gonzalez", "wilson", "anderson", "thomas", "taylor", "moore", "jackson", "martin",
    "lee", "perez", "thompson", "white", "harris", "sanchez", "clark", "ramirez", "lewis", "robinson",
    "walker", "young", "allen", "king", "wright", "scott", "torres", "nguyen", "hill", "flores",
    "green", "adams", "nelson", "baker", "hall", "rivera", "campbell", "mitchell", "carter", "roberts"
)

#==============================================================================
# HELPER FUNCTIONS
#==============================================================================

function Generate-UniqueAliases {
    param(
        [int]$Count,
        [int]$FirstNamePercent,
        [hashtable]$UsedNames
    )
    
    $aliases = @()
    $firstNameCount = [Math]::Floor($Count * $FirstNamePercent / 100)
    $fullNameCount = $Count - $firstNameCount
    
    # Generate firstName aliases
    for ($i = 0; $i -lt $firstNameCount; $i++) {
        $attempts = 0
        do {
            $firstName = $firstNames | Get-Random
            $attempts++
            if ($attempts -gt 100) {
                # Fallback: add number suffix
                $firstName = "$firstName$(Get-Random -Minimum 1 -Maximum 999)"
                break
            }
        } while ($UsedNames.ContainsKey($firstName))
        
        $UsedNames[$firstName] = $true
        $aliases += $firstName
    }
    
    # Generate firstName.lastName aliases
    for ($i = 0; $i -lt $fullNameCount; $i++) {
        $attempts = 0
        do {
            $firstName = $firstNames | Get-Random
            $lastName = $lastNames | Get-Random
            $fullName = "$firstName.$lastName"
            $attempts++
            if ($attempts -gt 100) {
                # Fallback: add number suffix
                $fullName = "$fullName$(Get-Random -Minimum 1 -Maximum 999)"
                break
            }
        } while ($UsedNames.ContainsKey($fullName))
        
        $UsedNames[$fullName] = $true
        $aliases += $fullName
    }
    
    return $aliases
}

function Create-AliasesForDomain {
    param(
        [string]$Domain,
        [int]$Count,
        [int]$FirstNamePercent,
        [hashtable]$UsedNames,
        [object]$Client,
        [object]$Logger
    )
    
    $createdAliases = @()
    $skippedCount = 0
    
    # Create info@ alias first
    Write-Host "  [1/50] Creating info@ alias..." -ForegroundColor Yellow
    try {
        $infoAlias = $Client.CreateAlias($Domain, "info", @("gmb@decisionsunlimited.io"), $null, $null)
        $createdAliases += "info@$Domain"
        $Logger.Info("Created info@ alias", $Domain, $null)
        Write-Host "        ✓ Created info@$Domain" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -match "already exists") {
            $createdAliases += "info@$Domain"
            $skippedCount++
            $Logger.Info("info@ alias already exists", $Domain, $null)
            Write-Host "        → info@$Domain already exists" -ForegroundColor Cyan
        }
        else {
            $Logger.Warning("Failed to create info@ alias: $($_.Exception.Message)", $Domain, $null)
            Write-Host "        ⚠ Failed to create info@: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    
    # Generate and create remaining aliases
    Write-Host "  [2/50] Generating $($Count - 1) unique aliases..." -ForegroundColor Yellow
    $aliases = Generate-UniqueAliases -Count ($Count - 1) -FirstNamePercent $FirstNamePercent -UsedNames $UsedNames
    
    $created = 0
    $batchSize = 10
    for ($i = 0; $i -lt $aliases.Count; $i++) {
        $aliasName = $aliases[$i]
        
        try {
            $alias = $Client.CreateAlias($Domain, $aliasName, @("gmb@decisionsunlimited.io"), $null, $null)
            $createdAliases += "$aliasName@$Domain"
            $created++
            
            # Progress update every 10 aliases
            if (($created % $batchSize) -eq 0) {
                Write-Host "        ✓ Created $created/$($aliases.Count) aliases" -ForegroundColor Green
            }
        }
        catch {
            if ($_.Exception.Message -match "already exists") {
                $createdAliases += "$aliasName@$Domain"
                $skippedCount++
            }
            else {
                $Logger.Warning("Failed to create alias ${aliasName}: $($_.Exception.Message)", $Domain, $null)
            }
        }
    }
    
    Write-Host "        ✓ Created $created additional aliases" -ForegroundColor Green
    if ($skippedCount -gt 0) {
        Write-Host "        → Skipped $skippedCount existing aliases" -ForegroundColor Cyan
    }
    Write-Host "        ✓ Total: $($createdAliases.Count) aliases for $Domain" -ForegroundColor Green
    
    return $createdAliases
}

#==============================================================================
# PASS 2: ALIAS CREATION WITH RETRY LOGIC
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Pass 2: Creating Aliases for Verified Domains" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$allAliases = @()
$usedNames = @{}
$successCount = 0
$failedCount = 0
$results = @()

for ($i = 0; $i -lt $totalDomains; $i++) {
    $domain = $domains[$i]
    $domainIndex = $i + 1
    
    Write-Host "[$domainIndex/$totalDomains] Creating aliases for: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("Creating aliases $domainIndex/$totalDomains", $domain, $null)
    
    $result = @{
        Domain = $domain
        Success = $false
        AliasCount = 0
        Attempts = 0
        Error = $null
    }
    
    $success = $false
    $attempt = 0
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        $result.Attempts = $attempt
        
        if ($attempt -gt 1) {
            $delay = $InitialRetryDelay * [Math]::Pow(2, $attempt - 2)
            Write-Host "  [Retry $attempt/$MaxRetries] Waiting $delay seconds before retry..." -ForegroundColor Yellow
            $logger.Info("Retrying after delay", $domain, @{Attempt = $attempt; Delay = $delay})
            Start-Sleep -Seconds $delay
        }
        
        try {
            Write-Host "  [Attempt $attempt/$MaxRetries] Creating $AliasCount aliases..." -ForegroundColor Yellow
            
            $domainAliases = Create-AliasesForDomain `
                -Domain $domain `
                -Count $AliasCount `
                -FirstNamePercent $FirstNamePercent `
                -UsedNames $usedNames `
                -Client $forwardEmailClient `
                -Logger $logger
            
            $allAliases += $domainAliases
            $result.AliasCount = $domainAliases.Count
            $result.Success = $true
            $success = $true
            $successCount++
            
            Write-Host "  ✓ Alias generation complete for $domain" -ForegroundColor Green
            $logger.Info("Alias generation complete", $domain, @{Count = $domainAliases.Count; Attempts = $attempt})
        }
        catch {
            $errorMessage = $_.Exception.Message
            $result.Error = $errorMessage
            $logger.Error("Failed to create aliases (attempt $attempt): $errorMessage", $domain, $null)
            Write-Host "  ✗ ERROR (attempt $attempt): $errorMessage" -ForegroundColor Red
            
            if ($attempt -ge $MaxRetries) {
                Write-Host "  ✗ Max retries reached, moving to next domain" -ForegroundColor Red
                $failedCount++
            }
        }
    }
    
    $results += $result
    Write-Host ""
}

#==============================================================================
# EXPORT ALIASES
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Exporting Aliases" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$aliasesFile = Join-Path $scriptRoot "data/aliases.txt"
$dataDir = Split-Path -Parent $aliasesFile
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$allAliases | Sort-Object | Out-File -FilePath $aliasesFile -Encoding UTF8
Write-Host "✓ Exported $($allAliases.Count) aliases to: $aliasesFile" -ForegroundColor Green
$logger.Info("Exported aliases to file", $null, @{Count = $allAliases.Count; File = $aliasesFile})

#==============================================================================
# SUMMARY
#==============================================================================

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Pass 2 Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Total Domains:      $totalDomains" -ForegroundColor White
Write-Host "✓ Successful:       $successCount" -ForegroundColor Green
Write-Host "✗ Failed:           $failedCount" -ForegroundColor Red
Write-Host "Total Aliases:      $($allAliases.Count)" -ForegroundColor Cyan
Write-Host "Aliases per Domain: $([Math]::Round($allAliases.Count / [Math]::Max($successCount, 1), 2))" -ForegroundColor Cyan
Write-Host ""

if ($failedCount -gt 0) {
    Write-Host "Failed Domains:" -ForegroundColor Red
    foreach ($result in $results) {
        if (-not $result.Success) {
            Write-Host "  - $($result.Domain): $($result.Error) (after $($result.Attempts) attempts)" -ForegroundColor Red
        }
    }
    Write-Host ""
}

Write-Host "Retry Statistics:" -ForegroundColor Cyan
$firstAttempt = ($results | Where-Object { $_.Success -and $_.Attempts -eq 1 }).Count
$retriedSuccess = ($results | Where-Object { $_.Success -and $_.Attempts -gt 1 }).Count
Write-Host "  First attempt:  $firstAttempt domains" -ForegroundColor Green
Write-Host "  After retries:  $retriedSuccess domains" -ForegroundColor Yellow
Write-Host ""

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Complete!" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "All aliases have been exported to:" -ForegroundColor Green
Write-Host "  $aliasesFile" -ForegroundColor Cyan
Write-Host ""

$logger.Info("Pass 2 complete", $null, @{
    Total = $totalDomains
    Success = $successCount
    Failed = $failedCount
    TotalAliases = $allAliases.Count
    FirstAttempt = $firstAttempt
    Retried = $retriedSuccess
})
