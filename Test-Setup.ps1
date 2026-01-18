#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Tests the email infrastructure automation setup.

.DESCRIPTION
    Validates configuration, API connectivity, and module functionality.

.EXAMPLE
    .\Test-Setup.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Automation - Setup Test" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Test 1: PowerShell Version
Write-Host "[TEST] Checking PowerShell version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -ge 7) {
    Write-Host "  [PASS] PowerShell $($psVersion.Major).$($psVersion.Minor) detected" -ForegroundColor Green
} else {
    Write-Host "  [FAIL] PowerShell 7+ required. Current version: $($psVersion.Major).$($psVersion.Minor)" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Test 2: Module Loading
Write-Host "[TEST] Loading modules..." -ForegroundColor Yellow
$modules = @("Config", "StateManager", "ForwardEmailClient", "CloudflareClient", "Logger")
$moduleLoadFailed = $false

foreach ($moduleName in $modules) {
    try {
        Import-Module "$ScriptDir/modules/$moduleName.psm1" -Force
        Write-Host "  [PASS] $moduleName module loaded" -ForegroundColor Green
    }
    catch {
        Write-Host "  [FAIL] Failed to load $moduleName module: $_" -ForegroundColor Red
        $moduleLoadFailed = $true
    }
}

if ($moduleLoadFailed) {
    exit 1
}
Write-Host ""

# Test 3: Environment Variables
Write-Host "[TEST] Checking environment variables..." -ForegroundColor Yellow
$envVars = @("FORWARD_EMAIL_API_KEY", "CLOUDFLARE_API_TOKEN")
$envVarMissing = $false

foreach ($varName in $envVars) {
    $envValue = [Environment]::GetEnvironmentVariable($varName)
    if ($envValue) {
        $maskedValue = $envValue.Substring(0, [Math]::Min(8, $envValue.Length)) + "..."
        Write-Host "  [PASS] $varName is set ($maskedValue)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $varName is not set" -ForegroundColor Red
        $envVarMissing = $true
    }
}

if ($envVarMissing) {
    Write-Host ""
    Write-Host "  Please set the required environment variables in .env file or system environment" -ForegroundColor Yellow
    Write-Host "  See .env.example for reference" -ForegroundColor Yellow
}
Write-Host ""

# Test 4: Configuration Loading
Write-Host "[TEST] Loading configuration..." -ForegroundColor Yellow
try {
    $config = New-EmailInfraConfig
    Write-Host "  [PASS] Configuration loaded successfully" -ForegroundColor Green
    Write-Host "    - Forward Email API Base: $($config.ForwardEmailApiBase)" -ForegroundColor Gray
    Write-Host "    - Cloudflare API Base: $($config.CloudflareApiBase)" -ForegroundColor Gray
    Write-Host "    - Max Retries: $($config.MaxRetries)" -ForegroundColor Gray
    Write-Host "    - Concurrent Domains: $($config.ConcurrentDomains)" -ForegroundColor Gray
    Write-Host "    - Aliases Configured: $($config.Aliases.Count)" -ForegroundColor Gray
}
catch {
    Write-Host "  [FAIL] Configuration loading failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 5: State Manager
Write-Host "[TEST] Testing state manager..." -ForegroundColor Yellow
try {
    $testStateFile = "data/test_state.json"
    $stateManager = New-StateManager -StateFile $testStateFile
    
    # Add a test domain
    $testDomain = "test-$(Get-Random).example.com"
    $record = $stateManager.AddDomain($testDomain)
    
    # Verify domain was added
    $retrieved = $stateManager.GetDomain($testDomain)
    if ($retrieved.Domain -eq $testDomain) {
        Write-Host "  [PASS] State manager working correctly" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] State manager domain retrieval failed" -ForegroundColor Red
    }
    
    # Clean up test state file
    if (Test-Path $testStateFile) {
        Remove-Item $testStateFile -Force
    }
}
catch {
    Write-Host "  [FAIL] State manager test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 6: Logger
Write-Host "[TEST] Testing logger..." -ForegroundColor Yellow
try {
    $testLogFile = "logs/test_log.log"
    $logger = New-Logger -LogFile $testLogFile -MinLevel "INFO"
    
    $logger.Info("Test log message", "test.example.com", @{TestKey = "TestValue"})
    
    if (Test-Path $testLogFile) {
        Write-Host "  [PASS] Logger working correctly" -ForegroundColor Green
        Remove-Item $testLogFile -Force
    } else {
        Write-Host "  [FAIL] Logger did not create log file" -ForegroundColor Red
    }
}
catch {
    Write-Host "  [FAIL] Logger test failed: $_" -ForegroundColor Red
}
Write-Host ""

# Test 7: API Clients (if credentials available)
if (-not $envVarMissing) {
    Write-Host "[TEST] Testing API clients..." -ForegroundColor Yellow
    
    try {
        $retryConfig = @{
            MaxRetries = 3
            InitialRetryDelay = 2
            MaxRetryDelay = 10
            RateLimitDelay = 30
        }
        
        # Test Forward Email client
        try {
            $apiKey = [Environment]::GetEnvironmentVariable("FORWARD_EMAIL_API_KEY")
            $forwardEmailClient = New-ForwardEmailClient -ApiKey $apiKey -RetryConfig $retryConfig
            $domains = $forwardEmailClient.ListDomains()
            Write-Host "  [PASS] Forward Email API connection successful" -ForegroundColor Green
            Write-Host "    - Domains in account: $($domains.result.Count)" -ForegroundColor Gray
        }
        catch {
            Write-Host "  [FAIL] Forward Email API connection failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        # Test Cloudflare client
        try {
            $apiToken = [Environment]::GetEnvironmentVariable("CLOUDFLARE_API_TOKEN")
            $cloudflareClient = New-CloudflareClient -ApiToken $apiToken -RetryConfig $retryConfig
            $zones = $cloudflareClient.ListZones($null)
            Write-Host "  [PASS] Cloudflare API connection successful" -ForegroundColor Green
            Write-Host "    - Zones in account: $($zones.result.Count)" -ForegroundColor Gray
        }
        catch {
            Write-Host "  [FAIL] Cloudflare API connection failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  [FAIL] API client test failed: $_" -ForegroundColor Red
    }
    Write-Host ""
}

# Summary
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

if (-not $moduleLoadFailed -and -not $envVarMissing) {
    Write-Host "All tests passed! The system is ready to use." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Create a domains file (e.g., data/domains.txt) with one domain per line" -ForegroundColor White
    Write-Host "  2. Run: .\Setup-EmailInfrastructure.ps1 -DomainsFile data/domains.txt" -ForegroundColor White
} else {
    Write-Host "Some tests failed. Please fix the issues before running the automation." -ForegroundColor Red
}

Write-Host ""
