<#
.SYNOPSIS
    Phase 3 Pass 2: Set Passwords for All Aliases with Robust Error Handling

.DESCRIPTION
    This script sets passwords for all aliases across all domains with:
    - Comprehensive error logging and reporting
    - Intelligent retry logic with exponential backoff
    - Rate limiting to avoid API throttling
    - State management for resumability
    - Parallel processing support
    - Detailed progress tracking
    - CSV export of results
    
    This is part of the redesigned Phase 3 dedicated to password management.
    
.PARAMETER DomainsFile
    Path to text file containing list of domains (one per line).
    Default: data/domains.txt

.PARAMETER LogFile
    Path to log file.
    Default: logs/pass3-2-set-passwords.log

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL.
    Default: INFO

.PARAMETER AliasPassword
    Password to set for all aliases.
    Default: 474d6dc122cde69b6cd8b3a1

.PARAMETER MaxRetries
    Maximum number of retry attempts per alias (default: 3).

.PARAMETER InitialRetryDelay
    Initial delay in seconds before first retry (default: 2).

.PARAMETER RateLimitDelay
    Delay in seconds between API operations (default: 3).
    Applied after ListAliases calls and between password operations.

.PARAMETER Parallel
    Enable parallel processing of domains (default: false).

.PARAMETER ThrottleLimit
    Maximum concurrent domain processing threads (default: 5).

.PARAMETER DryRun
    If specified, performs validation only without setting passwords.

.PARAMETER Resume
    Resume from previous incomplete run using state file.

.EXAMPLE
    .\Pass3-2-SetPasswords.ps1

.EXAMPLE
    .\Pass3-2-SetPasswords.ps1 -Parallel -ThrottleLimit 10

.EXAMPLE
    .\Pass3-2-SetPasswords.ps1 -Resume

.NOTES
    Author: Email Infrastructure Automation
    Version: 2.0
    Requires: ForwardEmailClient, Logger modules
    Environment Variables: FORWARD_EMAIL_API_KEY
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainsFile = "data/domains.txt",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/pass3-2-set-passwords.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [string]$AliasPassword = "474d6dc122cde69b6cd8b3a1",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxRetries = 3,
    
    [Parameter(Mandatory=$false)]
    [int]$InitialRetryDelay = 2,
    
    [Parameter(Mandatory=$false)]
    [int]$RateLimitDelay = 3,
    
    [Parameter(Mandatory=$false)]
    [switch]$Parallel,
    
    [Parameter(Mandatory=$false)]
    [int]$ThrottleLimit = 5,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Resume
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

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Phase 3 Pass 2: Set Passwords for All Aliases" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE] No passwords will be set" -ForegroundColor Yellow
    Write-Host ""
}

if ($Parallel) {
    Write-Host "[PARALLEL MODE] Processing up to $ThrottleLimit domains concurrently" -ForegroundColor Cyan
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
# STATE MANAGEMENT
#==============================================================================

$stateFile = Join-Path $scriptRoot "data/pass3-2-state.json"
$state = @{
    ExecutionId = (Get-Date -Format "yyyyMMdd-HHmmss")
    StartTime = (Get-Date -Format "o")
    Phase = "3"
    Pass = "2"
    Domains = @{}
}

if ($Resume -and (Test-Path $stateFile)) {
    Write-Host "[RESUME] Loading previous state..." -ForegroundColor Cyan
    try {
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json -AsHashtable
        $resumedDomains = ($state.Domains.Keys | Where-Object { $state.Domains[$_].Status -ne "completed" }).Count
        Write-Host "[RESUME] Loaded state from previous run" -ForegroundColor Green
        Write-Host "         Execution ID: $($state.ExecutionId)" -ForegroundColor Gray
        Write-Host "         Domains to resume: $resumedDomains" -ForegroundColor Gray
    }
    catch {
        Write-Host "[WARN] Could not load state file, starting fresh" -ForegroundColor Yellow
        $Resume = $false
    }
    Write-Host ""
}

function Save-State {
    $stateDir = Split-Path -Parent $stateFile
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    $state.LastUpdated = (Get-Date -Format "o")
    $state | ConvertTo-Json -Depth 10 | Out-File -FilePath $stateFile -Encoding UTF8
}

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

function Set-AliasPasswordWithRetry {
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
    $errorType = $null
    
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++
        
        if ($attempt -gt 1) {
            $delay = $InitialDelay * [Math]::Pow(2, $attempt - 2)
            Start-Sleep -Seconds $delay
        }
        
        try {
            $Client.GenerateAliasPassword($Domain, $Alias.id, $Password, $true) | Out-Null
            $success = $true
            
            if ($attempt -gt 1) {
                $Logger.Info("Password set after $attempt attempts for $($Alias.name)@$Domain", $Domain, $null)
            }
            
            return @{
                Success = $true
                Attempts = $attempt
                Error = $null
                ErrorType = $null
            }
        }
        catch {
            $lastError = $_.Exception.Message
            
            # Classify error
            $statusCode = $_.Exception.Response.StatusCode.value__
            $errorType = switch ($statusCode) {
                400 { "BadRequest" }
                401 { "Unauthorized" }
                403 { "Forbidden" }
                404 { "NotFound" }
                409 { "Conflict" }
                429 { "RateLimit" }
                { $_ -ge 500 } { "ServerError" }
                default { "Unknown" }
            }
            
            # Don't retry permanent errors
            if ($errorType -in @("Unauthorized", "Forbidden", "BadRequest")) {
                $Logger.Warning("Permanent error for $($Alias.name)@$Domain : $lastError", $Domain, $null)
                break
            }
            
            if ($attempt -ge $MaxRetries) {
                $Logger.Warning("Failed to set password for $($Alias.name)@$Domain after $attempt attempts: $lastError", $Domain, $null)
            }
        }
    }
    
    return @{
        Success = $false
        Attempts = $attempt
        Error = $lastError
        ErrorType = $errorType
    }
}

function Process-DomainPasswords {
    param(
        [string]$Domain,
        [string]$Password,
        [object]$Client,
        [object]$Logger,
        [int]$MaxRetries,
        [int]$InitialDelay,
        [int]$RateDelay,
        [bool]$IsDryRun
    )
    
    $result = @{
        Domain = $Domain
        TotalAliases = 0
        PasswordsSet = 0
        PasswordsFailed = 0
        Skipped = 0
        Failures = @()
    }
    
    try {
        # Retrieve all aliases for the domain
        $aliasesResponse = $Client.ListAliases($Domain)
        
        # Rate limiting after API call
        Start-Sleep -Seconds $RateDelay
        
        # Handle pagination response
        $aliases = if ($aliasesResponse -is [array]) {
            $aliasesResponse
        } elseif ($aliasesResponse.PSObject.Properties.Name -contains 'results') {
            $aliasesResponse.results
        } else {
            @($aliasesResponse)
        }
        
        $result.TotalAliases = $aliases.Count
        
        if ($aliases.Count -eq 0) {
            return $result
        }
        
        foreach ($alias in $aliases) {
            $aliasName = $alias.name
            $aliasId = $alias.id
            
            # Skip catch-all aliases (*) and other special aliases
            if ($aliasName -eq "*" -or $aliasName -eq "" -or $aliasName -match "^[\*\+]") {
                $result.Skipped++
                continue
            }
            
            if ($IsDryRun) {
                $result.PasswordsSet++
                continue
            }
            
            $passwordResult = Set-AliasPasswordWithRetry `
                -Domain $Domain `
                -Alias $alias `
                -Password $Password `
                -Client $Client `
                -Logger $Logger `
                -MaxRetries $MaxRetries `
                -InitialDelay $InitialDelay
            
            if ($passwordResult.Success) {
                $result.PasswordsSet++
            }
            else {
                $result.PasswordsFailed++
                $result.Failures += @{
                    Alias = "$aliasName@$Domain"
                    AliasId = $aliasId
                    Error = $passwordResult.Error
                    ErrorType = $passwordResult.ErrorType
                    Attempts = $passwordResult.Attempts
                }
            }
            
            # Rate limiting
            Start-Sleep -Seconds $RateDelay
        }
    }
    catch {
        $result.Failures += @{
            Alias = "N/A"
            AliasId = "N/A"
            Error = "Domain processing error: $($_.Exception.Message)"
            ErrorType = "DomainError"
            Attempts = 0
        }
    }
    
    return $result
}

#==============================================================================
# MAIN PROCESSING
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Setting Passwords for All Aliases" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$startTime = Get-Date
$allResults = @()
$totalAliases = 0
$totalPasswordsSet = 0
$totalPasswordsFailed = 0
$totalSkipped = 0

if ($Parallel) {
    # Parallel processing
    Write-Host "Processing domains in parallel (throttle limit: $ThrottleLimit)..." -ForegroundColor Cyan
    Write-Host ""
    
    $domainsWithIndex = $domains | ForEach-Object -Begin { $i = 0 } -Process { [PSCustomObject]@{ Index = ++$i; Domain = $_ } }
    
    $allResults = $domainsWithIndex | ForEach-Object -Parallel {
        $domainIndex = $_.Index
        $domain = $_.Domain
        $totalDomains = $using:totalDomains
        
        # Import modules in parallel context
        Import-Module $using:modulesPath\ForwardEmailClient.psm1 -Force
        Import-Module $using:modulesPath\Logger.psm1 -Force
        
        # Initialize client in parallel context
        $retryConfig = @{
            MaxRetries = 5
            InitialRetryDelay = 5
            MaxRetryDelay = 300
            RateLimitDelay = 60
        }
        $client = New-ForwardEmailClient -ApiKey $using:env:FORWARD_EMAIL_API_KEY -RetryConfig $retryConfig
        $logger = New-Logger -LogFile "$using:LogFile.$domain" -MinLevel $using:LogLevel
        
        Write-Host "[$domainIndex/$totalDomains] Processing: $domain" -ForegroundColor Cyan
        
        $result = Process-DomainPasswords `
            -Domain $domain `
            -Password $using:AliasPassword `
            -Client $client `
            -Logger $logger `
            -MaxRetries $using:MaxRetries `
            -InitialDelay $using:InitialRetryDelay `
            -RateDelay $using:RateLimitDelay `
            -IsDryRun $using:DryRun.IsPresent
        
        Write-Host "[$domainIndex/$totalDomains] $domain : ✓ $($result.PasswordsSet) | ✗ $($result.PasswordsFailed) | → $($result.Skipped)" -ForegroundColor $(if ($result.PasswordsFailed -eq 0) { "Green" } else { "Yellow" })
        
        $result
    } -ThrottleLimit $ThrottleLimit
}
else {
    # Sequential processing
    for ($i = 0; $i -lt $totalDomains; $i++) {
        $domain = $domains[$i]
        $domainIndex = $i + 1
        
        Write-Host "[$domainIndex/$totalDomains] Processing domain: $domain" -ForegroundColor Cyan
        Write-Host "=" * 80 -ForegroundColor DarkGray
        $logger.Info("Processing domain $domainIndex/$totalDomains", $domain, $null)
        
        # Check if already completed (resume mode)
        if ($Resume -and $state.Domains.ContainsKey($domain) -and $state.Domains[$domain].Status -eq "completed") {
            Write-Host "  → Already completed, skipping" -ForegroundColor Cyan
            $allResults += $state.Domains[$domain].Result
            Write-Host ""
            continue
        }
        
        $result = Process-DomainPasswords `
            -Domain $domain `
            -Password $AliasPassword `
            -Client $forwardEmailClient `
            -Logger $logger `
            -MaxRetries $MaxRetries `
            -InitialDelay $InitialRetryDelay `
            -RateDelay $RateLimitDelay `
            -IsDryRun $DryRun.IsPresent
        
        $allResults += $result
        
        # Update state
        $state.Domains[$domain] = @{
            Status = "completed"
            Result = $result
            CompletedAt = (Get-Date -Format "o")
        }
        Save-State
        
        if (-not $DryRun) {
            Write-Host "  ✓ Set: $($result.PasswordsSet) | ✗ Failed: $($result.PasswordsFailed) | → Skipped: $($result.Skipped)" -ForegroundColor $(if ($result.PasswordsFailed -eq 0) { "Green" } else { "Yellow" })
        }
        
        $logger.Info("Completed domain", $domain, @{
            PasswordsSet = $result.PasswordsSet
            PasswordsFailed = $result.PasswordsFailed
            Skipped = $result.Skipped
        })
        
        Write-Host ""
    }
}

# Aggregate results
foreach ($result in $allResults) {
    $totalAliases += $result.TotalAliases
    $totalPasswordsSet += $result.PasswordsSet
    $totalPasswordsFailed += $result.PasswordsFailed
    $totalSkipped += $result.Skipped
}

$endTime = Get-Date
$duration = $endTime - $startTime

#==============================================================================
# EXPORT RESULTS
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Exporting Results" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Export detailed results CSV
$detailedResults = @()
foreach ($result in $allResults) {
    foreach ($failure in $result.Failures) {
        $detailedResults += [PSCustomObject]@{
            Domain = $result.Domain
            Alias = $failure.Alias
            AliasId = $failure.AliasId
            Status = "Failed"
            Error = $failure.Error
            ErrorType = $failure.ErrorType
            Attempts = $failure.Attempts
        }
    }
}

$resultsFile = Join-Path $scriptRoot "data/pass3-2-password-results.csv"
$resultsDir = Split-Path -Parent $resultsFile
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

if ($detailedResults.Count -gt 0) {
    $detailedResults | Export-Csv -Path $resultsFile -NoTypeInformation -Encoding UTF8
    Write-Host "✓ Exported detailed results to: $resultsFile" -ForegroundColor Green
}
else {
    Write-Host "✓ No failures to export" -ForegroundColor Green
}

# Export summary JSON
$summaryFile = Join-Path $scriptRoot "data/pass3-2-summary.json"
$summary = @{
    ExecutionId = $state.ExecutionId
    StartTime = $startTime.ToString("o")
    EndTime = $endTime.ToString("o")
    Duration = $duration.ToString()
    TotalDomains = $totalDomains
    TotalAliases = $totalAliases
    PasswordsSet = $totalPasswordsSet
    PasswordsFailed = $totalPasswordsFailed
    Skipped = $totalSkipped
    SuccessRate = if ($totalAliases -gt 0) { [Math]::Round(($totalPasswordsSet / ($totalAliases - $totalSkipped)) * 100, 2) } else { 0 }
    DryRun = $DryRun.IsPresent
    Parallel = $Parallel.IsPresent
}

$summary | ConvertTo-Json -Depth 10 | Out-File -FilePath $summaryFile -Encoding UTF8
Write-Host "✓ Exported summary to: $summaryFile" -ForegroundColor Green

$logger.Info("Exported results", $null, @{
    ResultsFile = $resultsFile
    SummaryFile = $summaryFile
    FailureCount = $detailedResults.Count
})

#==============================================================================
# SUMMARY
#==============================================================================

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Phase 3 Pass 2 Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Execution Time:      $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "Total Domains:       $totalDomains" -ForegroundColor White
Write-Host "Total Aliases:       $totalAliases" -ForegroundColor White

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY RUN] No passwords were set" -ForegroundColor Yellow
}
else {
    Write-Host "✓ Passwords Set:     $totalPasswordsSet" -ForegroundColor Green
    Write-Host "✗ Failed:            $totalPasswordsFailed" -ForegroundColor $(if ($totalPasswordsFailed -gt 0) { "Red" } else { "Green" })
    Write-Host "→ Skipped:           $totalSkipped (catch-all/special aliases)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Success Rate:        $($summary.SuccessRate)%" -ForegroundColor $(if ($summary.SuccessRate -ge 95) { "Green" } elseif ($summary.SuccessRate -ge 80) { "Yellow" } else { "Red" })
}

Write-Host ""

# Show top failures
if ($totalPasswordsFailed -gt 0 -and -not $DryRun) {
    Write-Host "Top Failure Reasons:" -ForegroundColor Red
    $failuresByType = $detailedResults | Group-Object ErrorType | Sort-Object Count -Descending
    foreach ($group in $failuresByType | Select-Object -First 5) {
        Write-Host "  $($group.Name): $($group.Count) aliases" -ForegroundColor Red
    }
    Write-Host ""
    
    Write-Host "Sample Failed Aliases:" -ForegroundColor Red
    foreach ($failure in $detailedResults | Select-Object -First 10) {
        Write-Host "  - $($failure.Alias): $($failure.Error)" -ForegroundColor Red
    }
    if ($detailedResults.Count -gt 10) {
        Write-Host "  ... and $($detailedResults.Count - 10) more (see CSV for full list)" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Complete!" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

if ($totalPasswordsFailed -gt 0) {
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Review the detailed results CSV: $resultsFile" -ForegroundColor Yellow
    Write-Host "  2. Run Pass3-3-VerifyPasswords.ps1 to verify current status" -ForegroundColor Yellow
    Write-Host "  3. Address any permanent errors (403, 400) manually" -ForegroundColor Yellow
    Write-Host "  4. Re-run this script with -Resume to retry failed aliases" -ForegroundColor Yellow
}
else {
    Write-Host "All passwords set successfully!" -ForegroundColor Green
    Write-Host "Run Pass3-3-VerifyPasswords.ps1 to verify the results." -ForegroundColor Cyan
}

Write-Host ""

$logger.Info("Phase 3 Pass 2 complete", $null, @{
    TotalDomains = $totalDomains
    TotalAliases = $totalAliases
    PasswordsSet = $totalPasswordsSet
    PasswordsFailed = $totalPasswordsFailed
    Skipped = $totalSkipped
    SuccessRate = $summary.SuccessRate
    Duration = $duration.ToString()
    DryRun = $DryRun.IsPresent
})

# Exit code based on success rate
if ($summary.SuccessRate -ge 95) {
    exit 0
}
elseif ($summary.SuccessRate -ge 80) {
    exit 1
}
else {
    exit 2
}
