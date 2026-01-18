# Config.psm1
# Configuration management for email infrastructure automation

class EmailInfraConfig {
    # API Credentials
    [string]$ForwardEmailApiKey
    [string]$CloudflareApiToken
    [string]$CloudflareAccountId
    
    # API Base URLs
    [string]$ForwardEmailApiBase = "https://api.forwardemail.net/v1"
    [string]$CloudflareApiBase = "https://api.cloudflare.com/client/v4"
    
    # Retry Configuration
    [int]$MaxRetries = 5
    [int]$InitialRetryDelay = 5
    [int]$MaxRetryDelay = 300
    [int]$RateLimitDelay = 60
    
    # Verification Configuration
    [int]$VerificationPollInterval = 30
    [int]$VerificationMaxAttempts = 40
    [int]$VerificationTimeoutSeconds = 1200
    
    # Processing Configuration
    [int]$ConcurrentDomains = 10
    [int]$BatchSize = 10
    
    # File Paths
    [string]$StateFile = "data/state.json"
    [string]$DomainsFile = "data/domains.txt"
    [string]$FailuresFile = "data/failures.json"
    [string]$LogFile = "logs/automation.log"
    
    # Logging Configuration
    [string]$LogLevel = "INFO"
    
    # Alias Configuration
    [hashtable[]]$Aliases = @(
        @{
            Name = "hello"
            Recipients = @("admin@example.com")
            Description = "General inquiries"
            Labels = @("contact")
        },
        @{
            Name = "admin"
            Recipients = @("admin@example.com")
            Description = "Administrative contact"
            Labels = @("admin")
        },
        @{
            Name = "support"
            Recipients = @("support@example.com")
            Description = "Customer support"
            Labels = @("support")
        },
        @{
            Name = "noreply"
            Recipients = @("noreply@example.com")
            Description = "No-reply address"
            Labels = @("system")
        }
    )
    
    EmailInfraConfig() {
        # Load from environment variables
        $this.LoadFromEnvironment()
    }
    
    [void] LoadFromEnvironment() {
        # Load API credentials from environment variables
        if ($env:FORWARD_EMAIL_API_KEY) {
            $this.ForwardEmailApiKey = $env:FORWARD_EMAIL_API_KEY
        }
        
        if ($env:CLOUDFLARE_API_TOKEN) {
            $this.CloudflareApiToken = $env:CLOUDFLARE_API_TOKEN
        }
        
        if ($env:CLOUDFLARE_ACCOUNT_ID) {
            $this.CloudflareAccountId = $env:CLOUDFLARE_ACCOUNT_ID
        }
        
        # Load other configuration from environment if present
        if ($env:LOG_LEVEL) {
            $this.LogLevel = $env:LOG_LEVEL
        }
        
        if ($env:MAX_RETRIES) {
            $this.MaxRetries = [int]$env:MAX_RETRIES
        }
        
        if ($env:CONCURRENT_DOMAINS) {
            $this.ConcurrentDomains = [int]$env:CONCURRENT_DOMAINS
        }
    }
    
    [void] LoadFromFile([string]$ConfigPath) {
        if (Test-Path $ConfigPath) {
            $configData = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            
            # Override with file values
            if ($configData.ForwardEmailApiKey) { $this.ForwardEmailApiKey = $configData.ForwardEmailApiKey }
            if ($configData.CloudflareApiToken) { $this.CloudflareApiToken = $configData.CloudflareApiToken }
            if ($configData.CloudflareAccountId) { $this.CloudflareAccountId = $configData.CloudflareAccountId }
            if ($configData.MaxRetries) { $this.MaxRetries = $configData.MaxRetries }
            if ($configData.LogLevel) { $this.LogLevel = $configData.LogLevel }
            if ($configData.Aliases) { $this.Aliases = $configData.Aliases }
        }
    }
    
    [bool] Validate() {
        $valid = $true
        
        if ([string]::IsNullOrWhiteSpace($this.ForwardEmailApiKey)) {
            Write-Error "FORWARD_EMAIL_API_KEY is required"
            $valid = $false
        }
        
        if ([string]::IsNullOrWhiteSpace($this.CloudflareApiToken)) {
            Write-Error "CLOUDFLARE_API_TOKEN is required"
            $valid = $false
        }
        
        return $valid
    }
}

function New-EmailInfraConfig {
    <#
    .SYNOPSIS
    Creates a new configuration object for email infrastructure automation.
    
    .DESCRIPTION
    Loads configuration from environment variables and optionally from a config file.
    
    .PARAMETER ConfigPath
    Optional path to a JSON configuration file.
    
    .EXAMPLE
    $config = New-EmailInfraConfig
    
    .EXAMPLE
    $config = New-EmailInfraConfig -ConfigPath "config/settings.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath
    )
    
    $config = [EmailInfraConfig]::new()
    
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $config.LoadFromFile($ConfigPath)
    }
    
    if (-not $config.Validate()) {
        throw "Configuration validation failed. Please check required environment variables."
    }
    
    return $config
}

Export-ModuleMember -Function New-EmailInfraConfig -Cmdlet *
