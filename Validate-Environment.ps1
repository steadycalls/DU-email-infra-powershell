<#
.SYNOPSIS
    Validates the environment and prerequisites for email infrastructure automation

.DESCRIPTION
    Performs comprehensive validation of:
    - PowerShell version and modules
    - Environment variables and API keys
    - File structure and permissions
    - Network connectivity
    - API accessibility
    
.EXAMPLE
    .\Validate-Environment.ps1

.NOTES
    Author: Email Infrastructure Automation
    Version: 2.0
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Environment Validation Tool" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$validationResults = @{
    Passed = 0
    Failed = 0
    Warnings = 0
    Checks = @()
}

function Test-Requirement {
    param(
        [string]$Category,
        [string]$Name,
        [scriptblock]$Test,
        [string]$SuccessMessage,
        [string]$FailureMessage,
        [string]$Severity = "ERROR"  # ERROR or WARNING
    )
    
    Write-Host "[$Category] $Name..." -ForegroundColor Yellow -NoNewline
    
    try {
        $result = & $Test
        
        if ($result) {
            Write-Host " ✓" -ForegroundColor Green
            Write-Host "  $SuccessMessage" -ForegroundColor Gray
            $validationResults.Passed++
            $validationResults.Checks += @{
                Category = $Category
                Name = $Name
                Status = "PASS"
                Message = $SuccessMessage
            }
            return $true
        }
        else {
            if ($Severity -eq "WARNING") {
                Write-Host " ⚠" -ForegroundColor Yellow
                Write-Host "  $FailureMessage" -ForegroundColor Yellow
                $validationResults.Warnings++
                $validationResults.Checks += @{
                    Category = $Category
                    Name = $Name
                    Status = "WARN"
                    Message = $FailureMessage
                }
            }
            else {
                Write-Host " ✗" -ForegroundColor Red
                Write-Host "  $FailureMessage" -ForegroundColor Red
                $validationResults.Failed++
                $validationResults.Checks += @{
                    Category = $Category
                    Name = $Name
                    Status = "FAIL"
                    Message = $FailureMessage
                }
            }
            return $false
        }
    }
    catch {
        Write-Host " ✗" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        $validationResults.Failed++
        $validationResults.Checks += @{
            Category = $Category
            Name = $Name
            Status = "FAIL"
            Message = "Error: $($_.Exception.Message)"
        }
        return $false
    }
}

#==============================================================================
# SYSTEM CHECKS
#==============================================================================

Write-Host "System Requirements" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

Test-Requirement -Category "System" -Name "PowerShell Version" -Test {
    $PSVersionTable.PSVersion.Major -ge 5
} -SuccessMessage "PowerShell $($PSVersionTable.PSVersion) (minimum 5.0 required)" `
  -FailureMessage "PowerShell version too old: $($PSVersionTable.PSVersion). Minimum 5.0 required"

Test-Requirement -Category "System" -Name "Operating System" -Test {
    $true  # Always pass, just report
} -SuccessMessage "$($PSVersionTable.OS)" `
  -FailureMessage "N/A" -Severity "WARNING"

Test-Requirement -Category "System" -Name "Execution Policy" -Test {
    $policy = Get-ExecutionPolicy
    $policy -ne "Restricted"
} -SuccessMessage "Execution policy: $(Get-ExecutionPolicy)" `
  -FailureMessage "Execution policy is Restricted. Run: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"

Write-Host ""

#==============================================================================
# FILE STRUCTURE CHECKS
#==============================================================================

Write-Host "File Structure" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

$baseDir = Split-Path -Parent $scriptRoot

Test-Requirement -Category "Files" -Name "Modules Directory" -Test {
    Test-Path (Join-Path $baseDir "modules")
} -SuccessMessage "Modules directory exists" `
  -FailureMessage "Modules directory not found at: $(Join-Path $baseDir 'modules')"

Test-Requirement -Category "Files" -Name "ForwardEmailClient Module" -Test {
    Test-Path (Join-Path $baseDir "modules/ForwardEmailClient.psm1")
} -SuccessMessage "ForwardEmailClient.psm1 found" `
  -FailureMessage "ForwardEmailClient.psm1 not found"

Test-Requirement -Category "Files" -Name "Logger Module" -Test {
    Test-Path (Join-Path $baseDir "modules/Logger.psm1")
} -SuccessMessage "Logger.psm1 found" `
  -FailureMessage "Logger.psm1 not found"

Test-Requirement -Category "Files" -Name "Data Directory" -Test {
    $dataDir = Join-Path $baseDir "data"
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
    Test-Path $dataDir
} -SuccessMessage "Data directory exists" `
  -FailureMessage "Could not create data directory"

Test-Requirement -Category "Files" -Name "Logs Directory" -Test {
    $logsDir = Join-Path $baseDir "logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }
    Test-Path $logsDir
} -SuccessMessage "Logs directory exists" `
  -FailureMessage "Could not create logs directory"

Test-Requirement -Category "Files" -Name "Domains File" -Test {
    Test-Path (Join-Path $baseDir "data/domains.txt")
} -SuccessMessage "domains.txt found" `
  -FailureMessage "domains.txt not found at: $(Join-Path $baseDir 'data/domains.txt')" `
  -Severity "WARNING"

Write-Host ""

#==============================================================================
# ENVIRONMENT VARIABLES
#==============================================================================

Write-Host "Environment Variables" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

Test-Requirement -Category "Environment" -Name "FORWARD_EMAIL_API_KEY" -Test {
    -not [string]::IsNullOrEmpty($env:FORWARD_EMAIL_API_KEY)
} -SuccessMessage "API key is set (length: $($env:FORWARD_EMAIL_API_KEY.Length) characters)" `
  -FailureMessage "FORWARD_EMAIL_API_KEY environment variable is not set"

Write-Host ""

#==============================================================================
# MODULE LOADING
#==============================================================================

Write-Host "Module Loading" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

Test-Requirement -Category "Modules" -Name "Load ForwardEmailClient" -Test {
    try {
        Import-Module (Join-Path $baseDir "modules/ForwardEmailClient.psm1") -Force -ErrorAction Stop
        $true
    }
    catch {
        $false
    }
} -SuccessMessage "ForwardEmailClient module loaded successfully" `
  -FailureMessage "Failed to load ForwardEmailClient module"

Test-Requirement -Category "Modules" -Name "Load Logger" -Test {
    try {
        Import-Module (Join-Path $baseDir "modules/Logger.psm1") -Force -ErrorAction Stop
        $true
    }
    catch {
        $false
    }
} -SuccessMessage "Logger module loaded successfully" `
  -FailureMessage "Failed to load Logger module"

Write-Host ""

#==============================================================================
# NETWORK CONNECTIVITY
#==============================================================================

Write-Host "Network Connectivity" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

Test-Requirement -Category "Network" -Name "Internet Connectivity" -Test {
    try {
        $response = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $response.StatusCode -eq 200
    }
    catch {
        $false
    }
} -SuccessMessage "Internet connection is working" `
  -FailureMessage "No internet connectivity detected"

Test-Requirement -Category "Network" -Name "Forward Email API Reachability" -Test {
    try {
        $response = Invoke-WebRequest -Uri "https://api.forwardemail.net" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        $true
    }
    catch {
        $false
    }
} -SuccessMessage "Forward Email API is reachable" `
  -FailureMessage "Cannot reach Forward Email API at https://api.forwardemail.net"

Write-Host ""

#==============================================================================
# API AUTHENTICATION
#==============================================================================

Write-Host "API Authentication" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

if ($env:FORWARD_EMAIL_API_KEY) {
    Test-Requirement -Category "API" -Name "API Key Authentication" -Test {
        try {
            $retryConfig = @{
                MaxRetries = 1
                InitialRetryDelay = 5
                MaxRetryDelay = 300
                RateLimitDelay = 60
            }
            $client = New-ForwardEmailClient -ApiKey $env:FORWARD_EMAIL_API_KEY -RetryConfig $retryConfig
            $domains = $client.ListDomains()
            $true
        }
        catch {
            $false
        }
    } -SuccessMessage "API key is valid and authenticated" `
      -FailureMessage "API key authentication failed - key may be invalid or expired"
    
    Test-Requirement -Category "API" -Name "Domain Access" -Test {
        try {
            $retryConfig = @{
                MaxRetries = 1
                InitialRetryDelay = 5
                MaxRetryDelay = 300
                RateLimitDelay = 60
            }
            $client = New-ForwardEmailClient -ApiKey $env:FORWARD_EMAIL_API_KEY -RetryConfig $retryConfig
            $domains = $client.ListDomains()
            $domainCount = if ($domains.results) { $domains.results.Count } else { $domains.Count }
            $domainCount -gt 0
        }
        catch {
            $false
        }
    } -SuccessMessage "Can access domains (found: $domainCount)" `
      -FailureMessage "No domains accessible with this API key" `
      -Severity "WARNING"
}
else {
    Write-Host "[API] API Key Authentication... ⊘ SKIPPED" -ForegroundColor DarkGray
    Write-Host "  API key not set, skipping authentication test" -ForegroundColor DarkGray
}

Write-Host ""

#==============================================================================
# SUMMARY
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$total = $validationResults.Passed + $validationResults.Failed + $validationResults.Warnings

Write-Host "Total Checks: $total" -ForegroundColor White
Write-Host "  Passed:     $($validationResults.Passed)" -ForegroundColor Green
Write-Host "  Failed:     $($validationResults.Failed)" -ForegroundColor Red
Write-Host "  Warnings:   $($validationResults.Warnings)" -ForegroundColor Yellow
Write-Host ""

# Export results
$resultsFile = Join-Path $scriptRoot "data/environment-validation-results.json"
$resultsDir = Split-Path -Parent $resultsFile
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

$validationResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Host "Results exported to: $resultsFile" -ForegroundColor Cyan
Write-Host ""

# Overall status
if ($validationResults.Failed -gt 0) {
    Write-Host "STATUS: FAILED - Environment is not ready" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the failed checks before running automation scripts." -ForegroundColor Yellow
    exit 1
}
elseif ($validationResults.Warnings -gt 0) {
    Write-Host "STATUS: READY WITH WARNINGS" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Environment is functional but some optional components are missing." -ForegroundColor Yellow
    Write-Host "You can proceed, but review the warnings above." -ForegroundColor Yellow
    exit 0
}
else {
    Write-Host "STATUS: READY - All checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Environment is fully configured and ready for automation." -ForegroundColor Green
    exit 0
}
