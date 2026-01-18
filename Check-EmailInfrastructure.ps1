<#
.SYNOPSIS
    Quick check of email infrastructure final state for domains.

.DESCRIPTION
    Performs rapid validation of domain configuration across Forward Email and Cloudflare:
    - Checks if domain exists and is verified in Forward Email
    - Validates DNS records (TXT + MX) in Cloudflare
    - Lists configured aliases
    - Provides pass/fail status for each domain

.PARAMETER DomainsFile
    Path to text file containing domains (one per line).

.PARAMETER ShowDetails
    Display detailed information for each domain (default: summary only).

.PARAMETER OnlyFailed
    Show only domains that have issues.

.PARAMETER ExportJson
    Export results to JSON file.

.PARAMETER ExportCsv
    Export results to CSV file.

.EXAMPLE
    .\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt

.EXAMPLE
    .\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ShowDetails

.EXAMPLE
    .\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -OnlyFailed

.EXAMPLE
    .\Check-EmailInfrastructure.ps1 -DomainsFile domains.txt -ExportJson results.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DomainsFile,
    
    [Parameter(Mandatory=$false)]
    [switch]$ShowDetails,
    
    [Parameter(Mandatory=$false)]
    [switch]$OnlyFailed,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportJson,
    
    [Parameter(Mandatory=$false)]
    [string]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
$modules = @("Config", "ForwardEmailClient", "CloudflareClient")
foreach ($moduleName in $modules) {
    Import-Module "$ScriptDir/modules/$moduleName.psm1" -Force
}

# Display header
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Status Check" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Check environment variables
$forwardEmailApiKey = [Environment]::GetEnvironmentVariable("FORWARD_EMAIL_API_KEY")
$cloudflareApiToken = [Environment]::GetEnvironmentVariable("CLOUDFLARE_API_TOKEN")

if (-not $forwardEmailApiKey) {
    Write-Error "FORWARD_EMAIL_API_KEY not set. Run .\Load-Environment.ps1 first."
}

if (-not $cloudflareApiToken) {
    Write-Error "CLOUDFLARE_API_TOKEN not set. Run .\Load-Environment.ps1 first."
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

$domains = Get-Content $DomainsFile | Where-Object { $_.Trim() -ne "" -and -not $_.StartsWith("#") } | ForEach-Object { $_.Trim() }

Write-Host "Checking $($domains.Count) domains..." -ForegroundColor Cyan
Write-Host ""

# Check each domain
$results = @()
$passCount = 0
$failCount = 0

foreach ($domain in $domains) {
    $result = [PSCustomObject]@{
        Domain = $domain
        Status = "UNKNOWN"
        ForwardEmailExists = $false
        ForwardEmailVerified = $false
        CloudflareTxtRecord = $false
        CloudflareMxRecords = $false
        AliasCount = 0
        Issues = @()
        CheckedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
    
    # Check Forward Email
    try {
        $feDomain = $forwardEmailClient.GetDomain($domain)
        if ($feDomain) {
            $result.ForwardEmailExists = $true
            
            # Check verification
            try {
                $verifyResult = $forwardEmailClient.VerifyDomain($domain)
                if ($verifyResult.verified -eq $true) {
                    $result.ForwardEmailVerified = $true
                } else {
                    $result.Issues += "Not verified in Forward Email"
                }
            }
            catch {
                $result.Issues += "Could not check verification status"
            }
            
            # Count aliases
            try {
                $aliases = $forwardEmailClient.ListAliases($domain)
                $result.AliasCount = $aliases.result.Count
            }
            catch {
                $result.Issues += "Could not retrieve aliases"
            }
        } else {
            $result.Issues += "Domain not found in Forward Email"
        }
    }
    catch {
        $result.Issues += "Forward Email API error: $($_.Exception.Message)"
    }
    
    # Check Cloudflare
    try {
        $zoneId = $cloudflareClient.GetZoneId($domain)
        if ($zoneId) {
            try {
                $dnsRecords = $cloudflareClient.ListDnsRecords($zoneId, $null, $null)
                
                # Check TXT record
                $txtRecords = $dnsRecords.result | Where-Object { 
                    $_.type -eq "TXT" -and $_.name -eq $domain -and $_.content -like "*forward-email*"
                }
                if ($txtRecords) {
                    $result.CloudflareTxtRecord = $true
                } else {
                    $result.Issues += "TXT verification record missing"
                }
                
                # Check MX records
                $mxRecords = $dnsRecords.result | Where-Object { $_.type -eq "MX" -and $_.name -eq $domain }
                $mx1 = $mxRecords | Where-Object { $_.content -like "*mx1.forwardemail.net*" }
                $mx2 = $mxRecords | Where-Object { $_.content -like "*mx2.forwardemail.net*" }
                
                if ($mx1 -and $mx2) {
                    $result.CloudflareMxRecords = $true
                } else {
                    $result.Issues += "MX records incomplete"
                }
            }
            catch {
                $result.Issues += "Could not retrieve DNS records"
            }
        } else {
            $result.Issues += "Zone not found in Cloudflare"
        }
    }
    catch {
        $result.Issues += "Cloudflare API error: $($_.Exception.Message)"
    }
    
    # Determine status
    if ($result.ForwardEmailExists -and $result.ForwardEmailVerified -and 
        $result.CloudflareTxtRecord -and $result.CloudflareMxRecords) {
        $result.Status = "PASS"
        $passCount++
    } else {
        $result.Status = "FAIL"
        $failCount++
    }
    
    # Display result
    if (-not $OnlyFailed -or $result.Status -eq "FAIL") {
        if ($result.Status -eq "PASS") {
            Write-Host "✓ $domain" -ForegroundColor Green -NoNewline
            if ($ShowDetails) {
                Write-Host " ($($result.AliasCount) aliases)" -ForegroundColor Gray
            } else {
                Write-Host ""
            }
        } else {
            Write-Host "✗ $domain" -ForegroundColor Red
            if ($ShowDetails -or $OnlyFailed) {
                foreach ($issue in $result.Issues) {
                    Write-Host "    - $issue" -ForegroundColor Yellow
                }
            }
        }
    }
    
    $results += $result
}

# Summary
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Total Domains: $($domains.Count)" -ForegroundColor White
Write-Host "  ✓ Passed: $passCount" -ForegroundColor Green
Write-Host "  ✗ Failed: $failCount" -ForegroundColor Red

if ($failCount -gt 0) {
    $passRate = [math]::Round(($passCount / $domains.Count) * 100, 1)
    Write-Host "  Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })
}

Write-Host ""

# Export results
if ($ExportJson) {
    $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $ExportJson -Encoding UTF8
    Write-Host "Results exported to: $ExportJson" -ForegroundColor Green
}

if ($ExportCsv) {
    $csvResults = $results | Select-Object Domain, Status, ForwardEmailExists, ForwardEmailVerified, 
        CloudflareTxtRecord, CloudflareMxRecords, AliasCount, CheckedAt,
        @{Name="Issues"; Expression={$_.Issues -join "; "}}
    
    $csvResults | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Results exported to: $ExportCsv" -ForegroundColor Green
}

# Exit with appropriate code
if ($failCount -gt 0) {
    exit 1
} else {
    exit 0
}
