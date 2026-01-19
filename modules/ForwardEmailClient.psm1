# ForwardEmailClient.psm1
# Forward Email API client with retry logic and error handling

class ForwardEmailClient {
    [string]$ApiKey
    [string]$BaseUrl
    [int]$MaxRetries
    [int]$InitialRetryDelay
    [int]$MaxRetryDelay
    [int]$RateLimitDelay
    
    ForwardEmailClient([string]$apiKey, [string]$baseUrl, [hashtable]$retryConfig) {
        $this.ApiKey = $apiKey
        $this.BaseUrl = $baseUrl
        $this.MaxRetries = $retryConfig.MaxRetries
        $this.InitialRetryDelay = $retryConfig.InitialRetryDelay
        $this.MaxRetryDelay = $retryConfig.MaxRetryDelay
        $this.RateLimitDelay = $retryConfig.RateLimitDelay
    }
    
    hidden [hashtable] GetHeaders() {
        # Forward Email uses Basic Auth with API key as username, empty password
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($this.ApiKey):"))
        
        return @{
            "Authorization" = "Basic $base64Auth"
            "Content-Type" = "application/json"
            "Accept" = "application/json"
        }
    }
    
    hidden [object] InvokeWithRetry([string]$method, [string]$uri, [hashtable]$body) {
        $attempt = 0
        $lastError = $null
        
        while ($attempt -lt $this.MaxRetries) {
            $attempt++
            
            try {
                $params = @{
                    Method = $method
                    Uri = $uri
                    Headers = $this.GetHeaders()
                    ContentType = "application/json"
                }
                
                if ($body) {
                    $params.Body = ($body | ConvertTo-Json -Depth 10)
                }
                
                Write-Verbose "[$method] $uri (Attempt $attempt/$($this.MaxRetries))"
                
                $response = Invoke-RestMethod @params
                return $response
            }
            catch {
                $lastError = $_
                $statusCode = $_.Exception.Response.StatusCode.value__
                
                Write-Verbose "Request failed with status code: $statusCode"
                
                # Handle rate limiting
                if ($statusCode -eq 429) {
                    Write-Warning "Rate limited. Waiting $($this.RateLimitDelay) seconds..."
                    Start-Sleep -Seconds $this.RateLimitDelay
                    continue
                }
                
                # Handle transient errors (5xx)
                if ($statusCode -ge 500 -and $statusCode -lt 600) {
                    $delay = [Math]::Min($this.InitialRetryDelay * [Math]::Pow(2, $attempt - 1), $this.MaxRetryDelay)
                    $jitter = Get-Random -Minimum 0 -Maximum 5
                    $totalDelay = $delay + $jitter
                    
                    Write-Warning "Server error ($statusCode). Retrying in $totalDelay seconds..."
                    Start-Sleep -Seconds $totalDelay
                    continue
                }
                
                # Permanent errors - don't retry
                if ($statusCode -eq 400 -or $statusCode -eq 401 -or $statusCode -eq 403 -or $statusCode -eq 404 -or $statusCode -eq 409) {
                    throw
                }
                
                # Other errors - retry with backoff
                $delay = [Math]::Min($this.InitialRetryDelay * [Math]::Pow(2, $attempt - 1), $this.MaxRetryDelay)
                $jitter = Get-Random -Minimum 0 -Maximum 5
                $totalDelay = $delay + $jitter
                
                Write-Warning "Request failed. Retrying in $totalDelay seconds..."
                Start-Sleep -Seconds $totalDelay
            }
        }
        
        # Max retries exceeded
        throw "Max retries ($($this.MaxRetries)) exceeded. Last error: $lastError"
    }
    
    [object] CreateDomain([string]$domainName) {
        <#
        .SYNOPSIS
        Creates a domain in Forward Email.
        
        .PARAMETER domainName
        The domain name to add.
        
        .RETURNS
        Domain object with ID and verification records.
        #>
        
        $uri = "$($this.BaseUrl)/domains"
        $body = @{
            name = $domainName
        }
        
        return $this.InvokeWithRetry("POST", $uri, $body)
    }
    
    [object] GetDomain([string]$domainName) {
        <#
        .SYNOPSIS
        Retrieves domain information from Forward Email.
        
        .PARAMETER domainName
        The domain name to retrieve.
        
        .RETURNS
        Domain object with details and verification status.
        #>
        
        $uri = "$($this.BaseUrl)/domains/$domainName"
        return $this.InvokeWithRetry("GET", $uri, $null)
    }
    
    [object] ListDomains() {
        <#
        .SYNOPSIS
        Lists all domains in the Forward Email account.
        
        .RETURNS
        Array of domain objects.
        #>
        
        $uri = "$($this.BaseUrl)/domains?pagination=true&limit=100"
        return $this.InvokeWithRetry("GET", $uri, $null)
    }
    
    [object] VerifyDomain([string]$domainName) {
        <#
        .SYNOPSIS
        Checks domain verification status.
        
        .PARAMETER domainName
        The domain name to verify.
        
        .RETURNS
        Verification result with status and details.
        #>
        
        $uri = "$($this.BaseUrl)/domains/$domainName/verify-records"
        return $this.InvokeWithRetry("GET", $uri, $null)
    }
    
    [object] CreateAlias([string]$domainName, [string]$aliasName, [string[]]$recipients, [string]$description, [string[]]$labels) {
        <#
        .SYNOPSIS
        Creates an email alias for a domain.
        
        .PARAMETER domainName
        The domain name.
        
        .PARAMETER aliasName
        The local part of the email address (e.g., "hello" for hello@domain.com).
        
        .PARAMETER recipients
        Array of recipient email addresses.
        
        .PARAMETER description
        Optional description for the alias.
        
        .PARAMETER labels
        Optional array of labels.
        
        .RETURNS
        Created alias object.
        #>
        
        $uri = "$($this.BaseUrl)/domains/$domainName/aliases"
        $body = @{
            name = $aliasName
            recipients = $recipients
        }
        
        if ($description) {
            $body.description = $description
        }
        
        if ($labels -and $labels.Count -gt 0) {
            $body.labels = $labels
        }
        
        return $this.InvokeWithRetry("POST", $uri, $body)
    }
    
    [object] ListAliases([string]$domainName) {
        <#
        .SYNOPSIS
        Lists all aliases for a domain.
        
        .PARAMETER domainName
        The domain name.
        
        .RETURNS
        Array of alias objects.
        #>
        
        $uri = "$($this.BaseUrl)/domains/$domainName/aliases?pagination=true&limit=100"
        return $this.InvokeWithRetry("GET", $uri, $null)
    }
    
    [bool] DomainExists([string]$domainName) {
        <#
        .SYNOPSIS
        Checks if a domain exists in Forward Email.
        
        .PARAMETER domainName
        The domain name to check.
        
        .RETURNS
        True if domain exists, false otherwise.
        #>
        
        try {
            $this.GetDomain($domainName) | Out-Null
            return $true
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 404) {
                return $false
            }
            throw
        }
    }
    
    [object] EnableEnhancedProtection([string]$domainName) {
        <#
        .SYNOPSIS
        Enables Enhanced Protection for a domain.
        Enhanced Protection hides forwarding configuration from public DNS lookups
        using a cryptographically generated random string.
        
        .PARAMETER domainName
        The domain name to enable Enhanced Protection for.
        
        .RETURNS
        Updated domain object with has_enhanced_protection set to true.
        
        .NOTES
        This is a paid feature (typically $3/month plan).
        Requires domain to be verified with correct MX and TXT records.
        #>
        
        $uri = "$($this.BaseUrl)/domains/$domainName"
        $body = @{
            has_enhanced_protection = $true
        }
        
        return $this.InvokeWithRetry("PATCH", $uri, $body)
    }
}

function New-ForwardEmailClient {
    <#
    .SYNOPSIS
    Creates a new Forward Email API client.
    
    .PARAMETER ApiKey
    Forward Email API key.
    
    .PARAMETER BaseUrl
    API base URL (default: https://api.forwardemail.net/v1).
    
    .PARAMETER RetryConfig
    Hashtable with retry configuration (MaxRetries, InitialRetryDelay, MaxRetryDelay, RateLimitDelay).
    
    .EXAMPLE
    $client = New-ForwardEmailClient -ApiKey $env:FORWARD_EMAIL_API_KEY -RetryConfig @{MaxRetries=5; InitialRetryDelay=5; MaxRetryDelay=300; RateLimitDelay=60}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApiKey,
        
        [Parameter(Mandatory=$false)]
        [string]$BaseUrl = "https://api.forwardemail.net/v1",
        
        [Parameter(Mandatory=$true)]
        [hashtable]$RetryConfig
    )
    
    return [ForwardEmailClient]::new($ApiKey, $BaseUrl, $RetryConfig)
}

Export-ModuleMember -Function New-ForwardEmailClient
