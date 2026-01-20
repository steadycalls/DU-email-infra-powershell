<#
.SYNOPSIS
    Diagnostic tool to test the Forward Email password generation API

.DESCRIPTION
    This script performs comprehensive testing of the password generation API
    to identify the root cause of password-setting failures. It tests various
    parameter combinations and provides detailed diagnostic output.
    
    Tests performed:
    1. API authentication and permissions
    2. Alias existence and status
    3. Password generation with different parameters
    4. Response analysis and error classification
    
.PARAMETER TestDomain
    Domain name to use for testing (default: first domain from domains.txt)

.PARAMETER TestAliasId
    Specific alias ID to test (optional, will use first alias if not specified)

.PARAMETER Password
    Password to set (default: 474d6dc122cde69b6cd8b3a1)

.EXAMPLE
    .\Test-PasswordAPI.ps1

.EXAMPLE
    .\Test-PasswordAPI.ps1 -TestDomain "example.com" -TestAliasId "abc123"

.NOTES
    Author: Email Infrastructure Automation
    Version: 2.0
    Purpose: Diagnose password-setting failures
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TestDomain,
    
    [Parameter(Mandatory=$false)]
    [string]$TestAliasId,
    
    [Parameter(Mandatory=$false)]
    [string]$Password = "474d6dc122cde69b6cd8b3a1"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
$modulesPath = Join-Path (Split-Path -Parent $scriptRoot) "modules"
Import-Module (Join-Path $modulesPath "ForwardEmailClient.psm1") -Force
Import-Module (Join-Path $modulesPath "Logger.psm1") -Force

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Forward Email Password API Diagnostic Tool" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Initialize logger
$logFile = Join-Path $scriptRoot "logs/test-password-api.log"
$logDir = Split-Path -Parent $logFile
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logger = New-Logger -LogFile $logFile -MinLevel "DEBUG"

# Test results collection
$testResults = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Tests = @()
    Summary = @{
        Total = 0
        Passed = 0
        Failed = 0
        Warnings = 0
    }
}

function Add-TestResult {
    param(
        [string]$TestName,
        [string]$Status,  # PASS, FAIL, WARN
        [string]$Message,
        [object]$Details = $null
    )
    
    $testResults.Tests += @{
        Name = $TestName
        Status = $Status
        Message = $Message
        Details = $Details
        Timestamp = Get-Date -Format "HH:mm:ss"
    }
    
    $testResults.Summary.Total++
    
    switch ($Status) {
        "PASS" { 
            $testResults.Summary.Passed++
            Write-Host "  ✓ $TestName" -ForegroundColor Green
            Write-Host "    $Message" -ForegroundColor Gray
        }
        "FAIL" { 
            $testResults.Summary.Failed++
            Write-Host "  ✗ $TestName" -ForegroundColor Red
            Write-Host "    $Message" -ForegroundColor Red
        }
        "WARN" { 
            $testResults.Summary.Warnings++
            Write-Host "  ⚠ $TestName" -ForegroundColor Yellow
            Write-Host "    $Message" -ForegroundColor Yellow
        }
    }
    
    if ($Details) {
        Write-Host "    Details: $($Details | ConvertTo-Json -Compress -Depth 3)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

#==============================================================================
# TEST 1: API Key Validation
#==============================================================================

Write-Host "TEST 1: API Key Validation" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

if (-not $env:FORWARD_EMAIL_API_KEY) {
    Add-TestResult -TestName "API Key Environment Variable" -Status "FAIL" `
        -Message "FORWARD_EMAIL_API_KEY not set in environment"
    Write-Host "CRITICAL: Cannot proceed without API key" -ForegroundColor Red
    exit 1
}

Add-TestResult -TestName "API Key Environment Variable" -Status "PASS" `
    -Message "API key found in environment (length: $($env:FORWARD_EMAIL_API_KEY.Length) chars)"

# Initialize client
try {
    $retryConfig = @{
        MaxRetries = 1  # Single attempt for diagnostics
        InitialRetryDelay = 5
        MaxRetryDelay = 300
        RateLimitDelay = 60
    }
    $client = New-ForwardEmailClient -ApiKey $env:FORWARD_EMAIL_API_KEY -RetryConfig $retryConfig
    
    Add-TestResult -TestName "API Client Initialization" -Status "PASS" `
        -Message "Forward Email client initialized successfully"
}
catch {
    Add-TestResult -TestName "API Client Initialization" -Status "FAIL" `
        -Message "Failed to initialize client: $($_.Exception.Message)"
    exit 1
}

#==============================================================================
# TEST 2: Account Access
#==============================================================================

Write-Host "TEST 2: Account Access & Permissions" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

try {
    $domains = $client.ListDomains()
    $domainCount = if ($domains.results) { $domains.results.Count } else { $domains.Count }
    
    Add-TestResult -TestName "List Domains API Call" -Status "PASS" `
        -Message "Successfully retrieved $domainCount domains" `
        -Details @{ DomainCount = $domainCount }
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMsg = $_.Exception.Message
    
    if ($statusCode -eq 401) {
        Add-TestResult -TestName "List Domains API Call" -Status "FAIL" `
            -Message "Authentication failed - API key is invalid or expired" `
            -Details @{ StatusCode = $statusCode; Error = $errorMsg }
    }
    elseif ($statusCode -eq 403) {
        Add-TestResult -TestName "List Domains API Call" -Status "FAIL" `
            -Message "Authorization failed - API key lacks permissions" `
            -Details @{ StatusCode = $statusCode; Error = $errorMsg }
    }
    else {
        Add-TestResult -TestName "List Domains API Call" -Status "FAIL" `
            -Message "API call failed: $errorMsg" `
            -Details @{ StatusCode = $statusCode; Error = $errorMsg }
    }
    exit 1
}

#==============================================================================
# TEST 3: Select Test Domain and Alias
#==============================================================================

Write-Host "TEST 3: Test Subject Selection" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

# Get test domain
if (-not $TestDomain) {
    $domainsFilePath = Join-Path (Split-Path -Parent $scriptRoot) "data/domains.txt"
    if (Test-Path $domainsFilePath) {
        $domainsList = Get-Content $domainsFilePath | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
        $TestDomain = $domainsList[0]
        Add-TestResult -TestName "Test Domain Selection" -Status "PASS" `
            -Message "Using first domain from domains.txt: $TestDomain"
    }
    else {
        Add-TestResult -TestName "Test Domain Selection" -Status "FAIL" `
            -Message "No test domain specified and domains.txt not found"
        exit 1
    }
}
else {
    Add-TestResult -TestName "Test Domain Selection" -Status "PASS" `
        -Message "Using specified domain: $TestDomain"
}

# Get domain details
try {
    $domainInfo = $client.GetDomain($TestDomain)
    
    $planInfo = if ($domainInfo.plan) { $domainInfo.plan } else { "free" }
    $hasEnhancedProtection = if ($domainInfo.has_enhanced_protection) { "Yes" } else { "No" }
    
    Add-TestResult -TestName "Domain Information Retrieval" -Status "PASS" `
        -Message "Domain: $TestDomain | Plan: $planInfo | Enhanced Protection: $hasEnhancedProtection" `
        -Details @{ 
            Plan = $planInfo
            HasEnhancedProtection = $hasEnhancedProtection
            Verified = $domainInfo.has_mx_record
        }
}
catch {
    Add-TestResult -TestName "Domain Information Retrieval" -Status "FAIL" `
        -Message "Failed to retrieve domain info: $($_.Exception.Message)"
    exit 1
}

# Get test alias
try {
    $aliasesResponse = $client.ListAliases($TestDomain)
    $aliases = if ($aliasesResponse.results) { $aliasesResponse.results } else { $aliasesResponse }
    
    if ($aliases.Count -eq 0) {
        Add-TestResult -TestName "Test Alias Selection" -Status "FAIL" `
            -Message "No aliases found for domain $TestDomain"
        exit 1
    }
    
    if ($TestAliasId) {
        $testAlias = $aliases | Where-Object { $_.id -eq $TestAliasId } | Select-Object -First 1
        if (-not $testAlias) {
            Add-TestResult -TestName "Test Alias Selection" -Status "FAIL" `
                -Message "Specified alias ID not found: $TestAliasId"
            exit 1
        }
    }
    else {
        # Use first non-catchall alias
        $testAlias = $aliases | Where-Object { $_.name -ne "*" -and $_.name -ne "" } | Select-Object -First 1
        if (-not $testAlias) {
            Add-TestResult -TestName "Test Alias Selection" -Status "WARN" `
                -Message "No regular aliases found, using first alias"
            $testAlias = $aliases[0]
        }
    }
    
    $aliasEmail = "$($testAlias.name)@$TestDomain"
    $hasPassword = if ($testAlias.has_imap) { "Yes" } else { "No" }
    
    Add-TestResult -TestName "Test Alias Selection" -Status "PASS" `
        -Message "Selected: $aliasEmail | ID: $($testAlias.id) | Has Password: $hasPassword" `
        -Details @{
            AliasId = $testAlias.id
            AliasName = $testAlias.name
            HasPassword = $hasPassword
        }
}
catch {
    Add-TestResult -TestName "Test Alias Selection" -Status "FAIL" `
        -Message "Failed to retrieve aliases: $($_.Exception.Message)"
    exit 1
}

#==============================================================================
# TEST 4: Password Generation API - Scenario 1 (is_override: true)
#==============================================================================

Write-Host "TEST 4: Password Generation - Override Mode" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray
Write-Host "  Testing with is_override=true (current implementation)" -ForegroundColor Gray
Write-Host ""

try {
    $result = $client.GenerateAliasPassword($TestDomain, $testAlias.id, $Password, $true)
    
    Add-TestResult -TestName "Password Generation (Override)" -Status "PASS" `
        -Message "Password set successfully with is_override=true" `
        -Details @{
            Username = $result.username
            HasPassword = $true
            Method = "override"
        }
    
    Write-Host "  Response Details:" -ForegroundColor Green
    Write-Host "    Username: $($result.username)" -ForegroundColor Gray
    if ($result.password) {
        Write-Host "    Password: [REDACTED]" -ForegroundColor Gray
    }
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMsg = $_.Exception.Message
    
    # Try to get detailed error response
    $detailedError = $null
    try {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        $detailedError = $responseBody | ConvertFrom-Json
    }
    catch {
        # Could not parse response
    }
    
    $failureReason = switch ($statusCode) {
        400 { "Bad Request - Invalid parameters or alias configuration" }
        401 { "Unauthorized - API key authentication failed" }
        403 { "Forbidden - Insufficient permissions or plan does not support IMAP/passwords" }
        404 { "Not Found - Alias or domain not found" }
        409 { "Conflict - Password already exists or alias in invalid state" }
        429 { "Rate Limited - Too many requests" }
        default { "HTTP $statusCode - $errorMsg" }
    }
    
    Add-TestResult -TestName "Password Generation (Override)" -Status "FAIL" `
        -Message $failureReason `
        -Details @{
            StatusCode = $statusCode
            ErrorMessage = $errorMsg
            DetailedError = $detailedError
            Method = "override"
        }
    
    Write-Host "  Error Analysis:" -ForegroundColor Red
    Write-Host "    Status Code: $statusCode" -ForegroundColor Gray
    Write-Host "    Error: $errorMsg" -ForegroundColor Gray
    if ($detailedError) {
        Write-Host "    Details: $($detailedError | ConvertTo-Json -Depth 3)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Provide specific recommendations based on error
    Write-Host "  Recommendations:" -ForegroundColor Yellow
    switch ($statusCode) {
        403 {
            Write-Host "    - Check if your plan supports IMAP/password features" -ForegroundColor Yellow
            Write-Host "    - Enhanced Protection plan may be required" -ForegroundColor Yellow
            Write-Host "    - Verify API key has password generation permissions" -ForegroundColor Yellow
        }
        400 {
            Write-Host "    - Verify alias is not a catch-all (*) or special alias" -ForegroundColor Yellow
            Write-Host "    - Check if alias configuration allows passwords" -ForegroundColor Yellow
            Write-Host "    - Try creating alias with IMAP enabled from the start" -ForegroundColor Yellow
        }
        409 {
            Write-Host "    - Password may already exist - try with is_override=false" -ForegroundColor Yellow
            Write-Host "    - Alias may need to be in a specific state" -ForegroundColor Yellow
        }
    }
}

#==============================================================================
# TEST 5: Password Generation API - Scenario 2 (is_override: false)
#==============================================================================

Write-Host ""
Write-Host "TEST 5: Password Generation - Non-Override Mode" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray
Write-Host "  Testing with is_override=false (alternative approach)" -ForegroundColor Gray
Write-Host ""

try {
    $result = $client.GenerateAliasPassword($TestDomain, $testAlias.id, $Password, $false)
    
    Add-TestResult -TestName "Password Generation (Non-Override)" -Status "PASS" `
        -Message "Password set successfully with is_override=false" `
        -Details @{
            Username = $result.username
            HasPassword = $true
            Method = "non-override"
        }
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMsg = $_.Exception.Message
    
    Add-TestResult -TestName "Password Generation (Non-Override)" -Status "FAIL" `
        -Message "Failed with is_override=false: HTTP $statusCode" `
        -Details @{
            StatusCode = $statusCode
            ErrorMessage = $errorMsg
            Method = "non-override"
        }
}

#==============================================================================
# TEST 6: Verify Password Status
#==============================================================================

Write-Host ""
Write-Host "TEST 6: Password Status Verification" -ForegroundColor Cyan
Write-Host "-" * 80 -ForegroundColor DarkGray

try {
    # Re-fetch alias to check current status
    $aliasesResponse = $client.ListAliases($TestDomain)
    $aliases = if ($aliasesResponse.results) { $aliasesResponse.results } else { $aliasesResponse }
    $updatedAlias = $aliases | Where-Object { $_.id -eq $testAlias.id } | Select-Object -First 1
    
    if ($updatedAlias.has_imap) {
        Add-TestResult -TestName "Password Status Verification" -Status "PASS" `
            -Message "Alias now has IMAP/password enabled" `
            -Details @{ HasIMAP = $true }
    }
    else {
        Add-TestResult -TestName "Password Status Verification" -Status "WARN" `
            -Message "Alias still shows no IMAP/password" `
            -Details @{ HasIMAP = $false }
    }
}
catch {
    Add-TestResult -TestName "Password Status Verification" -Status "FAIL" `
        -Message "Failed to verify password status: $($_.Exception.Message)"
}

#==============================================================================
# SUMMARY REPORT
#==============================================================================

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Diagnostic Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Test Results:" -ForegroundColor White
Write-Host "  Total Tests:  $($testResults.Summary.Total)" -ForegroundColor White
Write-Host "  Passed:       $($testResults.Summary.Passed)" -ForegroundColor Green
Write-Host "  Failed:       $($testResults.Summary.Failed)" -ForegroundColor Red
Write-Host "  Warnings:     $($testResults.Summary.Warnings)" -ForegroundColor Yellow
Write-Host ""

# Export detailed results
$resultsFile = Join-Path $scriptRoot "data/password-api-diagnostic-results.json"
$resultsDir = Split-Path -Parent $resultsFile
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

$testResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultsFile -Encoding UTF8
Write-Host "Detailed results exported to:" -ForegroundColor Cyan
Write-Host "  $resultsFile" -ForegroundColor Gray
Write-Host ""

# Overall assessment
if ($testResults.Summary.Failed -gt 0) {
    Write-Host "ASSESSMENT: Issues detected that prevent password setting" -ForegroundColor Red
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Review the detailed error messages above" -ForegroundColor Yellow
    Write-Host "  2. Check the exported JSON file for full details" -ForegroundColor Yellow
    Write-Host "  3. Follow the recommendations for each failed test" -ForegroundColor Yellow
    Write-Host "  4. Contact Forward Email support if needed" -ForegroundColor Yellow
    exit 1
}
elseif ($testResults.Summary.Warnings -gt 0) {
    Write-Host "ASSESSMENT: Password setting works but with warnings" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You can proceed with Pass3-2-SetPasswords.ps1" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "ASSESSMENT: All tests passed successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Password API is working correctly." -ForegroundColor Green
    Write-Host "You can proceed with Pass3-2-SetPasswords.ps1" -ForegroundColor Green
    exit 0
}
