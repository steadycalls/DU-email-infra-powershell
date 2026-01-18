#!/usr/bin/env pwsh
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
    Number of domains to process concurrently (default: 5).

.PARAMETER DryRun
    If specified, performs validation only without making API calls.

.EXAMPLE
    .\Setup-EmailInfrastructure.ps1 -DomainsFile "data/domains.txt"

.EXAMPLE
    .\Setup-EmailInfrastructure.ps1 -DomainsFile "cloudflare_domains.txt" -LogLevel DEBUG -ConcurrentDomains 10

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
    [string]$ConfigFile,
    
    [Parameter(Mandatory=$false)]
    [string]$StateFile = "data/state.json",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/automation.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [int]$ConcurrentDomains = 5,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import modules
Import-Module "$ScriptDir/modules/Config.psm1" -Force
Import-Module "$ScriptDir/modules/StateManager.psm1" -Force
Import-Module "$ScriptDir/modules/ForwardEmailClient.psm1" -Force
Import-Module "$ScriptDir/modules/CloudflareClient.psm1" -Force
Import-Module "$ScriptDir/modules/Logger.psm1" -Force

# Initialize logger
$logger = New-Logger -LogFile $LogFile -MinLevel $LogLevel

$logger.Info("=" * 80, $null, $null)
$logger.Info("Email Infrastructure Automation Starting", $null, $null)
$logger.Info("=" * 80, $null, $null)

# Load configuration
try {
    $config = if ($ConfigFile) {
        New-EmailInfraConfig -ConfigPath $ConfigFile
    } else {
        New-EmailInfraConfig
    }
    
    # Override config with command-line parameters
    if ($PSBoundParameters.ContainsKey('ConcurrentDomains')) {
        $config.ConcurrentDomains = $ConcurrentDomains
    }
    if ($PSBoundParameters.ContainsKey('StateFile')) {
        $config.StateFile = $StateFile
    }
    if ($PSBoundParameters.ContainsKey('DomainsFile')) {
        $config.DomainsFile = $DomainsFile
    }
    if ($PSBoundParameters.ContainsKey('LogFile')) {
        $config.LogFile = $LogFile
    }
    if ($PSBoundParameters.ContainsKey('LogLevel')) {
        $config.LogLevel = $LogLevel
    }
    
    $logger.Info("Configuration loaded successfully", $null, $null)
}
catch {
    $logger.Critical("Failed to load configuration: $_", $null, $null)
    exit 1
}

# Initialize state manager
try {
    $stateManager = New-StateManager -StateFile $config.StateFile
    $logger.Info("State manager initialized", $null, @{StateFile = $config.StateFile})
}
catch {
    $logger.Critical("Failed to initialize state manager: $_", $null, $null)
    exit 1
}

# Initialize API clients
if (-not $DryRun) {
    try {
        $retryConfig = @{
            MaxRetries = $config.MaxRetries
            InitialRetryDelay = $config.InitialRetryDelay
            MaxRetryDelay = $config.MaxRetryDelay
            RateLimitDelay = $config.RateLimitDelay
        }
        
        $forwardEmailClient = New-ForwardEmailClient -ApiKey $config.ForwardEmailApiKey -BaseUrl $config.ForwardEmailApiBase -RetryConfig $retryConfig
        $cloudflareClient = New-CloudflareClient -ApiToken $config.CloudflareApiToken -BaseUrl $config.CloudflareApiBase -RetryConfig $retryConfig
        
        $logger.Info("API clients initialized", $null, $null)
    }
    catch {
        $logger.Critical("Failed to initialize API clients: $_", $null, $null)
        exit 1
    }
}

# Load domains from file
if (-not (Test-Path $config.DomainsFile)) {
    $logger.Critical("Domains file not found: $($config.DomainsFile)", $null, $null)
    exit 1
}

$domains = Get-Content $config.DomainsFile | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
$logger.Info("Loaded $($domains.Count) domains from file", $null, @{DomainsFile = $config.DomainsFile})

if ($domains.Count -eq 0) {
    $logger.Warning("No domains found in file", $null, $null)
    exit 0
}

# Process each domain
function Process-Domain {
    param(
        [string]$domain,
        [object]$config,
        [object]$stateManager,
        [object]$forwardEmailClient,
        [object]$cloudflareClient,
        [object]$logger
    )
    
    $logger.Info("Processing domain", $domain, $null)
    Write-Host ""
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Processing: $domain" -ForegroundColor Cyan
    Write-Host "$('=' * 80)" -ForegroundColor DarkGray
    
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
        return $record
    }
    
    # Skip if failed and max retries exceeded
    if ($record.State -eq [DomainState]::Failed -and $record.Attempts -ge $config.MaxRetries) {
        $logger.Warning("Domain failed with max retries, skipping", $domain, @{Attempts = $record.Attempts})
        return $record
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
                return $record
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
                Write-Host "        ✓ Found Cloudflare zone" -ForegroundColor Green
                
                # Get domain info from Forward Email to get required DNS records
                $domainInfo = $forwardEmailClient.GetDomain($domain)
                
                # Extract TXT record for verification
                # Forward Email typically requires a TXT record like: forward-email=...
                # The exact format is in the domain response
                
                # Create verification TXT record
                $verificationRecord = $cloudflareClient.GetOrCreateDnsRecord(
                    $zoneId,
                    "TXT",
                    $domain,
                    "forward-email-site-verification=$($domainInfo.verification_record)",
                    1,
                    "Forward Email verification"
                )
                
                $record.DnsRecords += @{
                    Type = "TXT"
                    Name = $domain
                    Content = "forward-email-site-verification=$($domainInfo.verification_record)"
                    CloudflareRecordId = $verificationRecord.id
                }
                
                # Create MX records for Forward Email
                $mxRecords = @(
                    @{Priority = 10; Value = "mx1.forwardemail.net"},
                    @{Priority = 20; Value = "mx2.forwardemail.net"}
                )
                
                foreach ($mx in $mxRecords) {
                    $mxRecord = $cloudflareClient.GetOrCreateDnsRecord(
                        $zoneId,
                        "MX",
                        $domain,
                        "$($mx.Priority) $($mx.Value)",
                        1,
                        "Forward Email MX record"
                    )
                    
                    $record.DnsRecords += @{
                        Type = "MX"
                        Name = $domain
                        Content = "$($mx.Priority) $($mx.Value)"
                        CloudflareRecordId = $mxRecord.id
                    }
                }
                
                $logger.Info("DNS records configured", $domain, @{RecordCount = $record.DnsRecords.Count})
                Write-Host "        ✓ Created TXT verification record" -ForegroundColor Green
                Write-Host "        ✓ Created MX records (mx1 + mx2)" -ForegroundColor Green
                
                $record.State = [DomainState]::DnsConfigured
                $stateManager.UpdateDomain($domain, $record)
            }
            catch {
                $errorMessage = $_.Exception.Message
                $logger.Error("Failed to configure DNS records: $errorMessage", $domain, $null)
                Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                $record.AddError("dns_configuration", $errorMessage, "DNS_CONFIG_ERROR", @{})
                $record.MarkFailed()
                $stateManager.UpdateDomain($domain, $record)
                return $record
            }
        }
        
        # Step 3: Verify domain (with polling and retry)
        if ($record.State -eq [DomainState]::DnsConfigured -or $record.State -eq [DomainState]::Verifying) {
            Write-Host "  [3/5] Verifying domain ownership (DNS propagation)..." -ForegroundColor Yellow
            $logger.Info("Verifying domain", $domain, $null)
            $record.State = [DomainState]::Verifying
            $stateManager.UpdateDomain($domain, $record)
            
            $verificationAttempts = 0
            $verified = $false
            
            while ($verificationAttempts -lt $config.VerificationMaxAttempts) {
                $verificationAttempts++
                
                try {
                    $verifyResult = $forwardEmailClient.VerifyDomain($domain)
                    
                    if ($verifyResult.verified -eq $true) {
                        $logger.Info("Domain verified successfully", $domain, @{Attempts = $verificationAttempts})
                        Write-Host "        ✓ Domain verified successfully (attempt $verificationAttempts/$($config.VerificationMaxAttempts))" -ForegroundColor Green
                        $verified = $true
                        break
                    }
                    
                    $logger.Info("Domain not yet verified, waiting...", $domain, @{Attempt = $verificationAttempts; MaxAttempts = $config.VerificationMaxAttempts})
                    Write-Host "        ⏳ Not verified yet, waiting 30s... (attempt $verificationAttempts/$($config.VerificationMaxAttempts))" -ForegroundColor DarkYellow
                    Start-Sleep -Seconds $config.VerificationPollInterval
                }
                catch {
                    $logger.Warning("Verification check failed: $($_.Exception.Message)", $domain, @{Attempt = $verificationAttempts})
                    Start-Sleep -Seconds $config.VerificationPollInterval
                }
            }
            
            if (-not $verified) {
                $errorMessage = "Domain verification timed out after $verificationAttempts attempts"
                $logger.Error($errorMessage, $domain, $null)
                Write-Host "        ✗ ERROR: $errorMessage" -ForegroundColor Red
                $record.AddError("verification", $errorMessage, "VERIFICATION_TIMEOUT", @{Attempts = $verificationAttempts})
                $record.MarkFailed()
                $stateManager.UpdateDomain($domain, $record)
                return $record
            }
            
            $record.State = [DomainState]::Verified
            $stateManager.UpdateDomain($domain, $record)
        }
        
        # Step 4: Create aliases
        if ($record.State -eq [DomainState]::Verified) {
            Write-Host "  [4/5] Creating email aliases..." -ForegroundColor Yellow
            $logger.Info("Creating email aliases", $domain, $null)
            
            foreach ($aliasConfig in $config.Aliases) {
                try {
                    $alias = $forwardEmailClient.CreateAlias(
                        $domain,
                        $aliasConfig.Name,
                        $aliasConfig.Recipients,
                        $aliasConfig.Description,
                        $aliasConfig.Labels
                    )
                    
                    $record.Aliases += @{
                        Name = $aliasConfig.Name
                        Recipients = $aliasConfig.Recipients
                        ForwardEmailAliasId = $alias.id
                        Description = $aliasConfig.Description
                        Labels = $aliasConfig.Labels
                    }
                    
                    $logger.Info("Created alias: $($aliasConfig.Name)@$domain", $domain, $null)
                    Write-Host "        ✓ Created alias: $($aliasConfig.Name)@$domain" -ForegroundColor Green
                }
                catch {
                    # Log alias creation failure but don't fail the entire domain
                    $logger.Warning("Failed to create alias $($aliasConfig.Name): $($_.Exception.Message)", $domain, $null)
                }
            }
            
            $record.State = [DomainState]::AliasesCreated
            $stateManager.UpdateDomain($domain, $record)
        }
        
        # Step 5: Final validation before marking as completed
        if ($record.State -eq [DomainState]::AliasesCreated) {
            Write-Host "  [5/5] Running final validation..." -ForegroundColor Yellow
            
            $validationPassed = $false
            try {
                # Perform final validation checks
                $validationResult = [PSCustomObject]@{
                    ForwardEmailExists = $false
                    ForwardEmailVerified = $false
                    CloudflareTxtRecord = $false
                    CloudflareMxRecords = $false
                }
                
                # Check Forward Email
                try {
                    $feDomain = $forwardEmailClient.GetDomain($domain)
                    if ($feDomain) {
                        $validationResult.ForwardEmailExists = $true
                        Write-Host "        ✓ Domain exists in Forward Email" -ForegroundColor Green
                        
                        $verifyResult = $forwardEmailClient.VerifyDomain($domain)
                        if ($verifyResult.verified -eq $true) {
                            $validationResult.ForwardEmailVerified = $true
                            Write-Host "        ✓ Domain is verified in Forward Email" -ForegroundColor Green
                        } else {
                            Write-Host "        ✗ Domain not verified in Forward Email" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    Write-Host "        ✗ Could not validate Forward Email: $($_.Exception.Message)" -ForegroundColor Red
                }
                
                # Check Cloudflare DNS
                try {
                    $zoneId = $cloudflareClient.GetZoneId($domain)
                    if ($zoneId) {
                        $dnsRecords = $cloudflareClient.ListDnsRecords($zoneId, $null, $null)
                        
                        # Check TXT record
                        $txtRecords = $dnsRecords.result | Where-Object { 
                            $_.type -eq "TXT" -and $_.name -eq $domain -and $_.content -like "*forward-email*"
                        }
                        if ($txtRecords) {
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
                Write-Host "$('=' * 80)" -ForegroundColor DarkGray
            } else {
                $errorMessage = "Final validation failed - domain may not be fully operational"
                $logger.Warning($errorMessage, $domain, $null)
                Write-Host ""
                Write-Host "  ⚠ WARNING: $domain setup completed but validation failed" -ForegroundColor Yellow
                Write-Host "    Domain has been configured but may need manual verification" -ForegroundColor Yellow
                Write-Host "$('=' * 80)" -ForegroundColor DarkGray
                
                # Mark as completed anyway since setup steps finished
                # But add a warning to the record
                $record.AddError("validation", $errorMessage, "VALIDATION_WARNING", @{})
                $record.MarkCompleted()
                $stateManager.UpdateDomain($domain, $record)
            }
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $logger.Error("Unexpected error processing domain: $errorMessage", $domain, $null)
        $record.AddError("unexpected", $errorMessage, "UNEXPECTED_ERROR", @{})
        $record.MarkFailed()
        $stateManager.UpdateDomain($domain, $record)
    }
    
    return $record
}

# Process domains
if ($DryRun) {
    $logger.Info("DRY RUN MODE - No API calls will be made", $null, $null)
    foreach ($domain in $domains) {
        $logger.Info("Would process domain", $domain, $null)
    }
} else {
    $startTime = Get-Date
    
    # Process domains with concurrency control
    $jobs = @()
    $processedCount = 0
    
    foreach ($domain in $domains) {
        # Wait if we've hit the concurrency limit
        while ($jobs.Count -ge $config.ConcurrentDomains) {
            $completed = $jobs | Where-Object { $_.State -eq 'Completed' }
            foreach ($job in $completed) {
                $jobs = $jobs | Where-Object { $_ -ne $job }
                Remove-Job $job
            }
            Start-Sleep -Milliseconds 100
        }
        
        # Start processing domain in background job
        $job = Start-Job -ScriptBlock {
            param($domain, $config, $stateManager, $forwardEmailClient, $cloudflareClient, $logger, $functionDef)
            
            # Define the function in the job scope
            Invoke-Expression $functionDef
            
            Process-Domain -domain $domain -config $config -stateManager $stateManager -forwardEmailClient $forwardEmailClient -cloudflareClient $cloudflareClient -logger $logger
        } -ArgumentList $domain, $config, $stateManager, $forwardEmailClient, $cloudflareClient, $logger, ${function:Process-Domain}.ToString()
        
        $jobs += $job
        $processedCount++
    }
    
    # Wait for all jobs to complete
    $logger.Info("Waiting for all domain processing jobs to complete...", $null, $null)
    $jobs | Wait-Job | Out-Null
    $jobs | Remove-Job
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Generate summary
    $logger.Info("=" * 80, $null, $null)
    $logger.Info("Processing Summary", $null, $null)
    $logger.Info("=" * 80, $null, $null)
    
    $summary = $stateManager.GetSummary()
    foreach ($state in $summary.Keys | Sort-Object) {
        $count = $summary[$state]
        if ($count -gt 0) {
            $logger.Info("$state`: $count", $null, $null)
        }
    }
    
    $logger.Info("Total processing time: $($duration.ToString('hh\:mm\:ss'))", $null, $null)
    
    # Export failures
    if ($summary["Failed"] -gt 0) {
        $stateManager.ExportFailures($config.FailuresFile)
        $logger.Warning("$($summary['Failed']) domains failed. See $($config.FailuresFile) for details.", $null, $null)
    }
}

$logger.Info("=" * 80, $null, $null)
$logger.Info("Email Infrastructure Automation Completed", $null, $null)
$logger.Info("=" * 80, $null, $null)
