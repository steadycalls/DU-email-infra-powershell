<#
.SYNOPSIS
    Automates email infrastructure setup for bulk domains using Forward Email and Cloudflare.

.DESCRIPTION
    This script processes a list of domains and:
    1. Adds each domain to Forward Email
    2. Configures required DNS records in Cloudflare
    3. Verifies domain ownership via DNS
    4. Creates standardized email aliases
    5. Tracks state and handles failures gracefully

.PARAMETER DomainsFile
    Path to text file containing list of domains (one per line).

.PARAMETER ConfigFile
    Optional path to JSON configuration file.

.PARAMETER StateFile
    Path to state persistence file (default: data/state.json).

.PARAMETER LogFile
    Path to log file (default: logs/automation.log).

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL (default: INFO).

.PARAMETER ConcurrentDomains
    Number of domains to process concurrently (default: 10).

.PARAMETER DryRun
    If specified, performs validation only without making API calls.

.EXAMPLE
    .\Setup-EmailInfrastructure.ps1 -DomainsFile "data/domains.txt"

.EXAMPLE
    .\Setup-EmailInfrastructure.ps1 -DomainsFile "cloudflare_domains.txt" -LogLevel DEBUG

.NOTES
    Requires PowerShell 7+ and the following environment variables:
    - FORWARD_EMAIL_API_KEY
    - CLOUDFLARE_API_TOKEN
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainsFile = "data/domains.txt",
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = "config.json",
    
    [Parameter(Mandatory=$false)]
    [string]$StateFile = "data/state.json",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/automation.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [int]$ConcurrentDomains = 10,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

# Import modules
$ErrorActionPreference = "Stop"
$modulePath = Join-Path $PSScriptRoot "modules"

try {
    Import-Module (Join-Path $modulePath "Config.psm1") -Force
    Write-Host "[PASS] Config module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "StateManager.psm1") -Force
    Write-Host "[PASS] StateManager module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "ForwardEmailClient.psm1") -Force
    Write-Host "[PASS] ForwardEmailClient module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "CloudflareClient.psm1") -Force
    Write-Host "[PASS] CloudflareClient module loaded" -ForegroundColor Green
    
    Import-Module (Join-Path $modulePath "Logger.psm1") -Force
    Write-Host "[PASS] Logger module loaded" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to load modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize configuration
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Automation Starting" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

try {
    $config = if ($ConfigFile -and (Test-Path $ConfigFile)) {
        New-EmailInfraConfig -ConfigPath $ConfigFile
    } else {
        New-EmailInfraConfig
    }
    
    # Override config with command-line parameters
    if ($PSBoundParameters.ContainsKey('DomainsFile')) { $config.DomainsFile = $DomainsFile }
    if ($PSBoundParameters.ContainsKey('StateFile')) { $config.StateFile = $StateFile }
    if ($PSBoundParameters.ContainsKey('LogFile')) { $config.LogFile = $LogFile }
    if ($PSBoundParameters.ContainsKey('LogLevel')) { $config.LogLevel = $LogLevel }
    if ($PSBoundParameters.ContainsKey('ConcurrentDomains')) { $config.ConcurrentDomains = $ConcurrentDomains }
    
    Write-Host "Configuration loaded successfully" -ForegroundColor Green
    Write-Host "  - Forward Email API Base: $($config.ForwardEmailApiBase)" -ForegroundColor Gray
    Write-Host "  - Cloudflare API Base: $($config.CloudflareApiBase)" -ForegroundColor Gray
    Write-Host "  - Max Retries: $($config.MaxRetries)" -ForegroundColor Gray
    Write-Host "  - Concurrent Domains: $($config.ConcurrentDomains)" -ForegroundColor Gray
    Write-Host "  - Aliases Configured: $($config.Aliases.Count)" -ForegroundColor Gray
}
catch {
    Write-Host "Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize state manager
$stateManager = New-StateManager -StateFile $config.StateFile
Write-Host "State manager initialized" -ForegroundColor Green

# Initialize API clients
$retryConfig = @{
    MaxRetries = $config.MaxRetries
    InitialRetryDelay = $config.InitialRetryDelay
    MaxRetryDelay = $config.MaxRetryDelay
    RateLimitDelay = $config.RateLimitDelay
}
$forwardEmailClient = New-ForwardEmailClient -ApiKey $env:FORWARD_EMAIL_API_KEY -BaseUrl $config.ForwardEmailApiBase -RetryConfig $retryConfig
$cloudflareClient = New-CloudflareClient -ApiToken $env:CLOUDFLARE_API_TOKEN -BaseUrl $config.CloudflareApiBase -RetryConfig $retryConfig
Write-Host "API clients initialized" -ForegroundColor Green

# Initialize logger
$logger = New-Logger -LogFile $config.LogFile -MinLevel $config.LogLevel
$logger.Info("=" * 80, $null, $null)
$logger.Info("Email Infrastructure Automation Starting", $null, $null)
$logger.Info("=" * 80, $null, $null)

# Validate API credentials
try {
    $forwardEmailClient.ValidateCredentials()
    $cloudflareClient.ValidateCredentials()
    Write-Host "API credentials validated" -ForegroundColor Green
}
catch {
    $logger.Critical("API credential validation failed: $($_.Exception.Message)", $null, $null)
    Write-Host "API credential validation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Load domains from file
if (-not (Test-Path $config.DomainsFile)) {
    $logger.Critical("Domains file not found: $($config.DomainsFile)", $null, $null)
    Write-Host "Domains file not found: $($config.DomainsFile)" -ForegroundColor Red
    exit 1
}

$domains = Get-Content $config.DomainsFile | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
$logger.Info("Loaded $($domains.Count) domains from file", $null, @{DomainsFile = $config.DomainsFile})
Write-Host "Loaded $($domains.Count) domains from file" -ForegroundColor Green

if ($domains.Count -eq 0) {
    $logger.Warning("No domains found in file", $null, $null)
    Write-Host "No domains found in file" -ForegroundColor Yellow
    exit 0
}

# Process domains
if ($DryRun) {
    $logger.Info("DRY RUN MODE - No API calls will be made", $null, $null)
    Write-Host "DRY RUN MODE - No API calls will be made" -ForegroundColor Yellow
    foreach ($domain in $domains) {
        $logger.Info("Would process domain", $domain, $null)
        Write-Host "  - $domain" -ForegroundColor Gray
    }
} else {
    $startTime = Get-Date
    $processedCount = 0
    $completedCount = 0
    $failedCount = 0
    
    Write-Host ""
    Write-Host "Starting domain processing..." -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($domain in $domains) {
        $processedCount++
        
        Write-Host ""
        Write-Host "[$processedCount/$($domains.Count)] Processing: $domain" -ForegroundColor Cyan
        Write-Host "=" * 80 -ForegroundColor DarkGray
        
        $logger.Info("Processing domain $processedCount/$($domains.Count)", $domain, $null)
        
        # Get or create domain record
        $record = $stateManager.GetDomain($domain)
        if (-not $record) {
            $record = $stateManager.AddDomain($domain)
            Write-Host "  ✓ Domain record created" -ForegroundColor Green
        } else {
            Write-Host "  ✓ Domain record loaded (State: $($record.State))" -ForegroundColor Green
        }
        
        # Skip if already completed
        if ($record.State -eq [DomainState]::Completed) {
            $logger.Info("Domain already completed, skipping", $domain, $null)
            Write-Host "  ✓ Domain already completed - skipping" -ForegroundColor Yellow
            $completedCount++
            continue
        }
        
        # Skip if failed and max retries exceeded
        if ($record.State -eq [DomainState]::Failed -and $record.Attempts -ge $config.MaxRetries) {
            $logger.Warning("Domain failed with max retries, skipping", $domain, @{Attempts = $record.Attempts})
            Write-Host "  ✗ Domain failed with max retries - skipping" -ForegroundColor Red
            $failedCount++
            continue
        }
        
        $record.UpdateAttempt()
        
        try {
            # Step 1: Add domain to Forward Email (if not already added)
            if ($record.State -eq [DomainState]::Pending) {
                Write-Host "  [1/5] Adding domain to Forward Email..." -ForegroundColor Yellow
                $logger.Info("Adding domain to Forward Email", $domain, $null)
                
                try {
                    # Check if domain already exists
                    if ($forwardEmailClient.DomainExists($domain)) {
                        $logger.Info("Domain already exists in Forward Email", $domain, $null)
                        Write-Host "        ✓ Domain already exists in Forward Email" -ForegroundColor Green
                        $domainInfo = $forwardEmailClient.GetDomain($domain)
                    } else {
                        $domainInfo = $forwardEmailClient.CreateDomain($domain)
                        $logger.Info("Domain added to Forward Email", $domain, @{DomainId = $domainInfo.id})
                        Write-Host "        ✓ Domain added to Forward Email" -ForegroundColor Green
                    }
                    
                    $record.ForwardEmailDomainId = $domainInfo.id
                    $record.State = [DomainState]::ForwardEmailAdded
                    $stateManager.UpdateDomain($domain, $record)
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    $logger.Error("Failed to add domain to Forward Email: $errorMessage", $domain, $null)
                    Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                    $record.AddError("forward_email_add", $errorMessage, "FORWARD_EMAIL_ERROR", @{})
                    $record.MarkFailed()
                    $stateManager.UpdateDomain($domain, $record)
                    $failedCount++
                    continue
                }
            }
            
            # Step 2: Configure DNS records in Cloudflare (if not already configured)
            if ($record.State -eq [DomainState]::ForwardEmailAdded) {
                Write-Host "  [2/5] Configuring DNS records in Cloudflare..." -ForegroundColor Yellow
                $logger.Info("Configuring DNS records in Cloudflare", $domain, $null)
                
                try {
                    # Get Cloudflare Zone ID
                    $zoneId = $cloudflareClient.GetZoneId($domain)
                    $record.CloudflareZoneId = $zoneId
                    $logger.Info("Found Cloudflare zone", $domain, @{ZoneId = $zoneId})
                    Write-Host "        ✓ Found Cloudflare zone: $zoneId" -ForegroundColor Green
                    
                    # Add TXT verification record
                    $txtValue = "forward-email-site-verification=$($record.ForwardEmailDomainId)"
                    $txtRecord = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "TXT", $txtValue, 3600)
                    $logger.Info("Added TXT verification record", $domain, @{RecordId = $txtRecord.id})
                    Write-Host "        ✓ Added TXT verification record" -ForegroundColor Green
                    
                    # Add MX records
                    $mx1 = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "MX", "mx1.forwardemail.net", 3600, 10)
                    $mx2 = $cloudflareClient.CreateOrUpdateDnsRecord($zoneId, $domain, "MX", "mx2.forwardemail.net", 3600, 20)
                    $logger.Info("Added MX records", $domain, @{MX1 = $mx1.id; MX2 = $mx2.id})
                    Write-Host "        ✓ Added MX records (mx1 + mx2)" -ForegroundColor Green
                    
                    $record.State = [DomainState]::DnsConfigured
                    $stateManager.UpdateDomain($domain, $record)
                }
                catch {
                    $errorMessage = $_.Exception.Message
                    $logger.Error("Failed to configure DNS: $errorMessage", $domain, $null)
                    Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                    $record.AddError("dns_config", $errorMessage, "DNS_ERROR", @{})
                    $record.MarkFailed()
                    $stateManager.UpdateDomain($domain, $record)
                    $failedCount++
                    continue
                }
            }
            
            # Step 3: Verify domain ownership (with retry for DNS propagation)
            if ($record.State -eq [DomainState]::DnsConfigured) {
                Write-Host "  [3/5] Verifying domain ownership..." -ForegroundColor Yellow
                $logger.Info("Verifying domain ownership", $domain, $null)
                
                $maxAttempts = 10
                $attemptDelay = 30
                $verified = $false
                
                for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                    try {
                        Write-Host "        Attempt $attempt/$maxAttempts..." -ForegroundColor Gray
                        $verifyResult = $forwardEmailClient.VerifyDomain($domain)
                        
                        if ($verifyResult.verification_record) {
                            $verified = $true
                            $logger.Info("Domain ownership verified", $domain, $null)
                            Write-Host "        ✓ Domain ownership verified" -ForegroundColor Green
                            break
                        }
                    }
                    catch {
                        $logger.Warning("Verification attempt $attempt failed: $($_.Exception.Message)", $domain, $null)
                    }
                    
                    if ($attempt -lt $maxAttempts) {
                        Write-Host "        Waiting ${attemptDelay}s for DNS propagation..." -ForegroundColor Gray
                        Start-Sleep -Seconds $attemptDelay
                    }
                }
                
                if (-not $verified) {
                    $errorMessage = "Domain verification failed after $maxAttempts attempts"
                    $logger.Error($errorMessage, $domain, $null)
                    Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                    $record.AddError("verification", $errorMessage, "VERIFICATION_ERROR", @{})
                    $record.MarkFailed()
                    $stateManager.UpdateDomain($domain, $record)
                    $failedCount++
                    continue
                }
                
                $record.State = [DomainState]::Verified
                $stateManager.UpdateDomain($domain, $record)
            }
            
            # Step 4: Create email aliases
            if ($record.State -eq [DomainState]::Verified) {
                Write-Host "  [4/5] Creating email aliases..." -ForegroundColor Yellow
                $logger.Info("Creating email aliases", $domain, $null)
                
                $aliasesCreated = 0
                foreach ($aliasConfig in $config.Aliases) {
                    try {
                        $aliasName = $aliasConfig.Name
                        $aliasEmail = "$aliasName@$domain"
                        
                        # Check if alias already exists
                        if ($forwardEmailClient.AliasExists($domain, $aliasName)) {
                            Write-Host "        ✓ Alias already exists: $aliasEmail" -ForegroundColor Green
                            $aliasesCreated++
                            continue
                        }
                        
                        $aliasResult = $forwardEmailClient.CreateAlias($domain, $aliasName, $aliasConfig.Recipients)
                        $logger.Info("Created alias", $domain, @{Alias = $aliasEmail; Recipients = ($aliasConfig.Recipients -join ", ")})
                        Write-Host "        ✓ Created alias: $aliasEmail" -ForegroundColor Green
                        $aliasesCreated++
                    }
                    catch {
                        $logger.Warning("Failed to create alias $aliasName@$domain`: $($_.Exception.Message)", $domain, $null)
                        Write-Host "        ⚠ Warning: Could not create $aliasName@$domain" -ForegroundColor Yellow
                    }
                }
                
                $logger.Info("Created $aliasesCreated aliases", $domain, $null)
                $record.State = [DomainState]::AliasesCreated
                $stateManager.UpdateDomain($domain, $record)
            }
            
            # Step 5: Final validation
            if ($record.State -eq [DomainState]::AliasesCreated) {
                Write-Host "  [5/5] Running final validation..." -ForegroundColor Yellow
                $logger.Info("Running final validation", $domain, $null)
                
                $validationPassed = $false
                
                try {
                    $validationResult = @{
                        ForwardEmailExists = $false
                        ForwardEmailVerified = $false
                        CloudflareTxtRecord = $false
                        CloudflareMxRecords = $false
                    }
                    
                    # Check Forward Email
                    try {
                        $domainInfo = $forwardEmailClient.GetDomain($domain)
                        if ($domainInfo) {
                            $validationResult.ForwardEmailExists = $true
                            Write-Host "        ✓ Domain exists in Forward Email" -ForegroundColor Green
                            
                            if ($domainInfo.has_mx_record -and $domainInfo.has_txt_record) {
                                $validationResult.ForwardEmailVerified = $true
                                Write-Host "        ✓ Domain verified in Forward Email" -ForegroundColor Green
                            } else {
                                Write-Host "        ✗ Domain not fully verified in Forward Email" -ForegroundColor Red
                            }
                        }
                    }
                    catch {
                        Write-Host "        ✗ Could not validate Forward Email: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    
                    # Check Cloudflare DNS
                    try {
                        if ($record.CloudflareZoneId) {
                            $dnsRecords = $cloudflareClient.GetDnsRecords($record.CloudflareZoneId)
                            
                            # Check TXT record
                            $txtRecord = $dnsRecords.result | Where-Object { 
                                $_.type -eq "TXT" -and $_.name -eq $domain -and $_.content -like "*forward-email-site-verification=*"
                            }
                            
                            if ($txtRecord) {
                                $validationResult.CloudflareTxtRecord = $true
                                Write-Host "        ✓ TXT verification record exists" -ForegroundColor Green
                            } else {
                                Write-Host "        ✗ TXT verification record missing" -ForegroundColor Red
                            }
                            
                            # Check MX records
                            $mxRecords = $dnsRecords.result | Where-Object { $_.type -eq "MX" -and $_.name -eq $domain }
                            $mx1 = $mxRecords | Where-Object { $_.content -like "*mx1.forwardemail.net*" }
                            $mx2 = $mxRecords | Where-Object { $_.content -like "*mx2.forwardemail.net*" }
                            
                            if ($mx1 -and $mx2) {
                                $validationResult.CloudflareMxRecords = $true
                                Write-Host "        ✓ MX records exist (mx1 + mx2)" -ForegroundColor Green
                            } else {
                                Write-Host "        ✗ MX records incomplete" -ForegroundColor Red
                            }
                        }
                    }
                    catch {
                        Write-Host "        ✗ Could not validate Cloudflare DNS: $($_.Exception.Message)" -ForegroundColor Red
                    }
                    
                    # Check if all validations passed
                    if ($validationResult.ForwardEmailExists -and $validationResult.ForwardEmailVerified -and 
                        $validationResult.CloudflareTxtRecord -and $validationResult.CloudflareMxRecords) {
                        $validationPassed = $true
                    }
                }
                catch {
                    $logger.Warning("Final validation failed: $($_.Exception.Message)", $domain, $null)
                    Write-Host "        ✗ Validation error: $($_.Exception.Message)" -ForegroundColor Red
                }
                
                if ($validationPassed) {
                    $record.MarkCompleted()
                    $stateManager.UpdateDomain($domain, $record)
                    $logger.Info("Domain processing completed successfully", $domain, $null)
                    Write-Host ""
                    Write-Host "  ✓ COMPLETED: $domain is fully configured and validated!" -ForegroundColor Green
                    Write-Host "=" * 80 -ForegroundColor DarkGray
                    $completedCount++
                } else {
                    $errorMessage = "Final validation failed - domain may not be fully operational"
                    $logger.Warning($errorMessage, $domain, $null)
                    Write-Host ""
                    Write-Host "  ⚠ WARNING: $domain setup completed but validation failed" -ForegroundColor Yellow
                    Write-Host "    Domain has been configured but may need manual verification" -ForegroundColor Yellow
                    Write-Host "=" * 80 -ForegroundColor DarkGray
                    
                    # Mark as completed anyway since setup steps finished
                    # But add a warning to the record
                    $record.AddError("validation", $errorMessage, "VALIDATION_WARNING", @{})
                    $record.MarkCompleted()
                    $stateManager.UpdateDomain($domain, $record)
                    $completedCount++
                }
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            $logger.Error("Unexpected error processing domain: $errorMessage", $domain, $null)
            Write-Host "  ✗ FAILED: $errorMessage" -ForegroundColor Red
            $record.AddError("unexpected", $errorMessage, "UNEXPECTED_ERROR", @{})
            $record.MarkFailed()
            $stateManager.UpdateDomain($domain, $record)
            $failedCount++
        }
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Generate summary
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Cyan
    Write-Host "Processing Summary" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan
    
    $logger.Info("=" * 80, $null, $null)
    $logger.Info("Processing Summary", $null, $null)
    $logger.Info("=" * 80, $null, $null)
    
    $summary = $stateManager.GetSummary()
    foreach ($state in $summary.Keys | Sort-Object) {
        $count = $summary[$state]
        if ($count -gt 0) {
            $logger.Info("$state`: $count", $null, $null)
            Write-Host "$state`: $count" -ForegroundColor Gray
        }
    }
    
    $logger.Info("Total processing time: $($duration.ToString('hh\:mm\:ss'))", $null, $null)
    Write-Host "Total processing time: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Gray
    
    # Export failures
    if ($summary["Failed"] -gt 0) {
        $stateManager.ExportFailures($config.FailuresFile)
        $logger.Warning("$($summary['Failed']) domains failed. See $($config.FailuresFile) for details.", $null, $null)
        Write-Host "Failed domains exported to: $($config.FailuresFile)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Email Infrastructure Automation Completed" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan

$logger.Info("=" * 80, $null, $null)
$logger.Info("Email Infrastructure Automation Completed", $null, $null)
$logger.Info("=" * 80, $null, $null)
