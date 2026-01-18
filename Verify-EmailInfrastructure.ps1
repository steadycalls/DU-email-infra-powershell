#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Verifies email infrastructure setup for domains.

.DESCRIPTION
    Checks each domain's status in Forward Email and Cloudflare, validating:
    - Domain exists in Forward Email
    - Domain is verified in Forward Email
    - DNS records exist in Cloudflare (TXT verification + MX records)
    - Email aliases are configured

.PARAMETER DomainsFile
    Path to text file containing domains (one per line).

.PARAMETER OutputFormat
    Output format: Console (default), JSON, or CSV.

.PARAMETER ExportPath
    Path to export results (for JSON or CSV output).

.EXAMPLE
    .\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt

.EXAMPLE
    .\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat JSON -ExportPath verification-report.json

.EXAMPLE
    .\Verify-EmailInfrastructure.ps1 -DomainsFile domains.txt -OutputFormat CSV -ExportPath verification-report.csv
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainsFile,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Console", "JSON", "CSV")]
    [string]$OutputFormat = "Console",
    
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
$modules = @("Config", "ForwardEmailClient", "CloudflareClient", "Logger")
foreach ($moduleName in $modules) {
    Import-Module "$ScriptDir/modules/$moduleName.psm1" -Force
}

# Initialize
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Verification" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Load configuration
$config = New-EmailInfraConfig

# Check environment variables
$forwardEmailApiKey = [Environment]::GetEnvironmentVariable("FORWARD_EMAIL_API_KEY")
$cloudflareApiToken = [Environment]::GetEnvironmentVariable("CLOUDFLARE_API_TOKEN")

if (-not $forwardEmailApiKey) {
    Write-Error "FORWARD_EMAIL_API_KEY environment variable not set. Run .\Load-Environment.ps1 first."
}

if (-not $cloudflareApiToken) {
    Write-Error "CLOUDFLARE_API_TOKEN environment variable not set. Run .\Load-Environment.ps1 first."
}

# Initialize API clients
$retryConfig = @{
    MaxRetries = 3
    InitialRetryDelay = 2
    MaxRetryDelay = 10
    RateLimitDelay = 30
}

$forwardEmailClient = New-ForwardEmailClient -ApiKey $forwardEmailApiKey -RetryConfig $retryConfig
$cloudflareClient = New-CloudflareClient -ApiToken $cloudflareApiToken -RetryConfig $retryConfig

# Load domains
if (-not (Test-Path $DomainsFile)) {
    Write-Error "Domains file not found: $DomainsFile"
}

$domains = Get-Content $DomainsFile | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") }
Write-Host "Loaded $($domains.Count) domains from $DomainsFile" -ForegroundColor Cyan
Write-Host ""

# Verification results
$results = @()

# Verify each domain
foreach ($domain in $domains) {
    $domain = $domain.Trim()
    Write-Host "Verifying: $domain" -ForegroundColor Yellow
    
    $result = [PSCustomObject]@{
        Domain = $domain
        ForwardEmailExists = $false
        ForwardEmailVerified = $false
        CloudflareZoneFound = $false
        CloudflareTxtRecordExists = $false
        CloudflareMxRecordsExist = $false
        AliasCount = 0
        Status = "Unknown"
        Issues = @()
    }
    
    # Check Forward Email
    try {
        $feDomain = $forwardEmailClient.GetDomain($domain)
        if ($feDomain) {
            $result.ForwardEmailExists = $true
            Write-Host "  ✓ Domain exists in Forward Email" -ForegroundColor Green
            
            # Check verification status
            try {
                $verifyResult = $forwardEmailClient.VerifyDomain($domain)
                if ($verifyResult.verified -eq $true) {
                    $result.ForwardEmailVerified = $true
                    Write-Host "  ✓ Domain is verified in Forward Email" -ForegroundColor Green
                } else {
                    $result.ForwardEmailVerified = $false
                    Write-Host "  ✗ Domain is NOT verified in Forward Email" -ForegroundColor Red
                    $result.Issues += "Domain not verified in Forward Email"
                }
            }
            catch {
                Write-Host "  ⚠ Could not check verification status: $($_.Exception.Message)" -ForegroundColor Yellow
                $result.Issues += "Could not check verification status"
            }
            
            # Check aliases
            try {
                $aliases = $forwardEmailClient.ListAliases($domain)
                $result.AliasCount = $aliases.result.Count
                Write-Host "  ✓ $($result.AliasCount) aliases configured" -ForegroundColor Green
            }
            catch {
                Write-Host "  ⚠ Could not retrieve aliases: $($_.Exception.Message)" -ForegroundColor Yellow
                $result.Issues += "Could not retrieve aliases"
            }
        } else {
            Write-Host "  ✗ Domain does NOT exist in Forward Email" -ForegroundColor Red
            $result.Issues += "Domain not found in Forward Email"
        }
    }
    catch {
        Write-Host "  ✗ Error checking Forward Email: $($_.Exception.Message)" -ForegroundColor Red
        $result.Issues += "Error checking Forward Email: $($_.Exception.Message)"
    }
    
    # Check Cloudflare
    try {
        $zoneId = $cloudflareClient.GetZoneId($domain)
        if ($zoneId) {
            $result.CloudflareZoneFound = $true
            Write-Host "  ✓ Zone found in Cloudflare" -ForegroundColor Green
            
            # Check DNS records
            try {
                $dnsRecords = $cloudflareClient.ListDnsRecords($zoneId, $null, $null)
                
                # Check for TXT verification record
                $txtRecords = $dnsRecords.result | Where-Object { $_.type -eq "TXT" -and $_.name -eq $domain }
                if ($txtRecords) {
                    $result.CloudflareTxtRecordExists = $true
                    Write-Host "  ✓ TXT verification record exists" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ TXT verification record NOT found" -ForegroundColor Red
                    $result.Issues += "TXT verification record missing in Cloudflare"
                }
                
                # Check for MX records
                $mxRecords = $dnsRecords.result | Where-Object { $_.type -eq "MX" -and $_.name -eq $domain }
                $mx1Exists = $mxRecords | Where-Object { $_.content -like "*mx1.forwardemail.net*" }
                $mx2Exists = $mxRecords | Where-Object { $_.content -like "*mx2.forwardemail.net*" }
                
                if ($mx1Exists -and $mx2Exists) {
                    $result.CloudflareMxRecordsExist = $true
                    Write-Host "  ✓ MX records exist (mx1 + mx2)" -ForegroundColor Green
                } else {
                    Write-Host "  ✗ MX records incomplete or missing" -ForegroundColor Red
                    $result.Issues += "MX records incomplete or missing in Cloudflare"
                }
            }
            catch {
                Write-Host "  ⚠ Could not retrieve DNS records: $($_.Exception.Message)" -ForegroundColor Yellow
                $result.Issues += "Could not retrieve DNS records"
            }
        } else {
            Write-Host "  ✗ Zone NOT found in Cloudflare" -ForegroundColor Red
            $result.Issues += "Zone not found in Cloudflare"
        }
    }
    catch {
        Write-Host "  ✗ Error checking Cloudflare: $($_.Exception.Message)" -ForegroundColor Red
        $result.Issues += "Error checking Cloudflare: $($_.Exception.Message)"
    }
    
    # Determine overall status
    if ($result.ForwardEmailExists -and $result.ForwardEmailVerified -and 
        $result.CloudflareZoneFound -and $result.CloudflareTxtRecordExists -and 
        $result.CloudflareMxRecordsExist) {
        $result.Status = "✓ Fully Configured"
        Write-Host "  Status: Fully Configured" -ForegroundColor Green
    } elseif ($result.ForwardEmailExists -and $result.CloudflareZoneFound) {
        $result.Status = "⚠ Partially Configured"
        Write-Host "  Status: Partially Configured" -ForegroundColor Yellow
    } else {
        $result.Status = "✗ Not Configured"
        Write-Host "  Status: Not Configured" -ForegroundColor Red
    }
    
    $results += $result
    Write-Host ""
}

# Summary
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Verification Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

$fullyConfigured = ($results | Where-Object { $_.Status -eq "✓ Fully Configured" }).Count
$partiallyConfigured = ($results | Where-Object { $_.Status -eq "⚠ Partially Configured" }).Count
$notConfigured = ($results | Where-Object { $_.Status -eq "✗ Not Configured" }).Count

Write-Host "Total Domains: $($results.Count)" -ForegroundColor White
Write-Host "  ✓ Fully Configured: $fullyConfigured" -ForegroundColor Green
Write-Host "  ⚠ Partially Configured: $partiallyConfigured" -ForegroundColor Yellow
Write-Host "  ✗ Not Configured: $notConfigured" -ForegroundColor Red
Write-Host ""

# Detailed issues
$domainsWithIssues = $results | Where-Object { $_.Issues.Count -gt 0 }
if ($domainsWithIssues.Count -gt 0) {
    Write-Host "Domains with Issues:" -ForegroundColor Yellow
    foreach ($result in $domainsWithIssues) {
        Write-Host "  $($result.Domain):" -ForegroundColor White
        foreach ($issue in $result.Issues) {
            Write-Host "    - $issue" -ForegroundColor Red
        }
    }
    Write-Host ""
}

# Export results
if ($OutputFormat -eq "JSON") {
    if ([string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportPath = "verification-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    }
    
    $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportPath -Encoding UTF8
    Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
}
elseif ($OutputFormat -eq "CSV") {
    if ([string]::IsNullOrWhiteSpace($ExportPath)) {
        $ExportPath = "verification-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    }
    
    # Flatten issues array for CSV
    $csvResults = $results | Select-Object Domain, ForwardEmailExists, ForwardEmailVerified, 
        CloudflareZoneFound, CloudflareTxtRecordExists, CloudflareMxRecordsExist, 
        AliasCount, Status, @{Name="Issues"; Expression={$_.Issues -join "; "}}
    
    $csvResults | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $ExportPath" -ForegroundColor Green
}

Write-Host ""
