<#
.SYNOPSIS
Export all aliases for domains to CSV with domain, alias, recipients, and password status.

.DESCRIPTION
This script retrieves all aliases for each domain in domains.txt and exports them to a CSV file.
The CSV includes: Domain, Alias, Recipients (backup emails), and HasPassword (boolean).

.PARAMETER DomainsFile
Path to the domains file. Default: data/domains.txt

.PARAMETER OutputFile
Path to the output CSV file. Default: data/exported-aliases.csv

.PARAMETER LogFile
Path to the log file. Default: logs/export-aliases.log

.PARAMETER LogLevel
Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL). Default: INFO

.EXAMPLE
.\Export-Aliases.ps1

.EXAMPLE
.\Export-Aliases.ps1 -OutputFile "my-aliases.csv"

.NOTES
Author: Manus AI
Date: 2026-01-19
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainsFile = "data/domains.txt",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "data/exported-aliases.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/export-aliases.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO"
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

#==============================================================================
# IMPORT MODULES
#==============================================================================

# Import modules
$modulesPath = Join-Path $scriptRoot "modules"
Import-Module (Join-Path $modulesPath "ForwardEmailClient.psm1") -Force
Import-Module (Join-Path $modulesPath "Logger.psm1") -Force

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Export Aliases Script" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "[PASS] Modules imported" -ForegroundColor Green

#==============================================================================
# INITIALIZE LOGGER
#==============================================================================

$logFilePath = if ([System.IO.Path]::IsPathRooted($LogFile)) {
    $LogFile
} else {
    Join-Path $scriptRoot $LogFile
}

$logDir = Split-Path -Parent $logFilePath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$logger = New-Logger -LogFile $logFilePath -MinLevel $LogLevel
Write-Host "[PASS] Logger initialized" -ForegroundColor Green

#==============================================================================
# INITIALIZE FORWARD EMAIL CLIENT
#==============================================================================

Write-Host "[CHECK] Verifying API key..." -ForegroundColor Yellow

$apiKey = $env:FORWARD_EMAIL_API_KEY
if (-not $apiKey) {
    Write-Host "[FAIL] FORWARD_EMAIL_API_KEY environment variable not set" -ForegroundColor Red
    $logger.Error("FORWARD_EMAIL_API_KEY not set", $null, $null)
    exit 1
}

Write-Host "[PASS] Forward Email API key found" -ForegroundColor Green

$retryConfig = @{
    MaxRetries = 3
    InitialRetryDelay = 5
    MaxRetryDelay = 60
    RateLimitDelay = 60
}

$forwardEmailClient = New-ForwardEmailClient -ApiKey $apiKey -RetryConfig $retryConfig

Write-Host "[PASS] Forward Email client initialized" -ForegroundColor Green

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
# EXPORT ALIASES
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Exporting Aliases" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$exportedAliases = @()
$totalAliases = 0
$domainsProcessed = 0
$domainsWithErrors = 0

for ($i = 0; $i -lt $totalDomains; $i++) {
    $domain = $domains[$i]
    $domainIndex = $i + 1
    
    Write-Host "[$domainIndex/$totalDomains] Exporting aliases for: $domain" -ForegroundColor Cyan
    $logger.Info("Exporting aliases for domain $domainIndex/$totalDomains", $domain, $null)
    
    try {
        # Retrieve all aliases for the domain
        $aliasesResponse = $forwardEmailClient.ListAliases($domain)
        $aliases = $aliasesResponse
        
        if ($aliases.Count -eq 0) {
            Write-Host "  → No aliases found" -ForegroundColor Yellow
            $logger.Info("No aliases found for domain", $domain, $null)
        }
        else {
            Write-Host "  ✓ Found $($aliases.Count) aliases" -ForegroundColor Green
            $logger.Info("Found aliases", $domain, @{Count = $aliases.Count})
            
            foreach ($alias in $aliases) {
                $aliasName = $alias.name
                $recipients = if ($alias.recipients -and $alias.recipients.Count -gt 0) {
                    $alias.recipients -join "; "
                } else {
                    ""
                }
                
                # Check if password is set
                # Note: Forward Email API doesn't directly expose password status
                # We'll check if the alias has a password by looking for has_imap or similar fields
                # For now, we'll mark it as "Unknown" unless we can determine it
                $hasPassword = "Unknown"
                
                # If the alias has certain properties, we can infer password status
                # This is a best-effort approach
                if ($alias.PSObject.Properties.Name -contains "has_imap") {
                    $hasPassword = $alias.has_imap
                }
                elseif ($alias.PSObject.Properties.Name -contains "has_password") {
                    $hasPassword = $alias.has_password
                }
                
                $exportedAliases += [PSCustomObject]@{
                    Domain = $domain
                    Alias = "$aliasName@$domain"
                    Recipients = $recipients
                    HasPassword = $hasPassword
                    IsEnabled = $alias.is_enabled
                    AliasId = $alias.id
                }
                
                $totalAliases++
            }
        }
        
        $domainsProcessed++
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "  ✗ ERROR: Failed to retrieve aliases: $errorMessage" -ForegroundColor Red
        $logger.Error("Failed to retrieve aliases for domain: $errorMessage", $domain, $null)
        $domainsWithErrors++
    }
    
    Write-Host ""
}

#==============================================================================
# EXPORT TO CSV
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Saving Results" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$outputFilePath = if ([System.IO.Path]::IsPathRooted($OutputFile)) {
    $OutputFile
} else {
    Join-Path $scriptRoot $OutputFile
}

$outputDir = Split-Path -Parent $outputFilePath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$exportedAliases | Export-Csv -Path $outputFilePath -NoTypeInformation -Encoding UTF8

Write-Host "✓ Exported $totalAliases aliases to: $outputFilePath" -ForegroundColor Green
$logger.Info("Exported aliases to CSV", $null, @{Count = $totalAliases; File = $outputFilePath})

#==============================================================================
# SUMMARY
#==============================================================================

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Export Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Total Domains:       $totalDomains" -ForegroundColor White
Write-Host "✓ Processed:         $domainsProcessed" -ForegroundColor Green
Write-Host "✗ Errors:            $domainsWithErrors" -ForegroundColor Red
Write-Host "Total Aliases:       $totalAliases" -ForegroundColor White

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Complete!" -ForegroundColor Green
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

Write-Host "Aliases have been exported to:" -ForegroundColor White
Write-Host "  $outputFilePath" -ForegroundColor Cyan
Write-Host ""

$logger.Info("Export complete", $null, @{
    TotalDomains = $totalDomains
    DomainsProcessed = $domainsProcessed
    DomainsWithErrors = $domainsWithErrors
    TotalAliases = $totalAliases
})
