# CloudflareClient.psm1
# Cloudflare API client with DNS management and retry logic

class CloudflareClient {
    [string]$ApiToken
    [string]$BaseUrl
    [int]$MaxRetries
    [int]$InitialRetryDelay
    [int]$MaxRetryDelay
    [int]$RateLimitDelay
    
    CloudflareClient([string]$apiToken, [string]$baseUrl, [hashtable]$retryConfig) {
        $this.ApiToken = $apiToken
        $this.BaseUrl = $baseUrl
        $this.MaxRetries = $retryConfig.MaxRetries
        $this.InitialRetryDelay = $retryConfig.InitialRetryDelay
        $this.MaxRetryDelay = $retryConfig.MaxRetryDelay
        $this.RateLimitDelay = $retryConfig.RateLimitDelay
    }
    
    hidden [hashtable] GetHeaders() {
        return @{
            "Authorization" = "Bearer $($this.ApiToken)"
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
    
    [object] ListZones([string]$domainName) {
        <#
        .SYNOPSIS
        Lists zones (domains) in Cloudflare account, optionally filtered by name.
        
        .PARAMETER domainName
        Optional domain name to filter by.
        
        .RETURNS
        Array of zone objects.
        #>
        
        $uri = "$($this.BaseUrl)/zones"
        
        if ($domainName) {
            $uri += "?name=$domainName"
        }
        
        return $this.InvokeWithRetry("GET", $uri, $null)
    }
    
    [string] GetZoneId([string]$domainName) {
        <#
        .SYNOPSIS
        Gets the Zone ID for a domain.
        
        .PARAMETER domainName
        The domain name.
        
        .RETURNS
        Zone ID string.
        #>
        
        $response = $this.ListZones($domainName)
        
        if ($response.result.Count -eq 0) {
            throw "Zone not found for domain: $domainName"
        }
        
        return $response.result[0].id
    }
    
    [object] ListDnsRecords([string]$zoneId, [string]$recordType, [string]$recordName) {
        <#
        .SYNOPSIS
        Lists DNS records for a zone.
        
        .PARAMETER zoneId
        The Cloudflare Zone ID.
        
        .PARAMETER recordType
        Optional record type filter (e.g., "TXT", "MX").
        
        .PARAMETER recordName
        Optional record name filter.
        
        .RETURNS
        Array of DNS record objects.
        #>
        
        $uri = "$($this.BaseUrl)/zones/$zoneId/dns_records"
        
        $queryParams = @()
        if ($recordType) { $queryParams += "type=$recordType" }
        if ($recordName) { $queryParams += "name=$recordName" }
        
        if ($queryParams.Count -gt 0) {
            $uri += "?" + ($queryParams -join "&")
        }
        
        return $this.InvokeWithRetry("GET", $uri, $null)
    }
    
    [object] CreateDnsRecord([string]$zoneId, [string]$recordType, [string]$recordName, [string]$content, [int]$ttl, [string]$comment) {
        return $this.CreateDnsRecord($zoneId, $recordType, $recordName, $content, $ttl, $comment, $null)
    }
    
    [object] CreateDnsRecord([string]$zoneId, [string]$recordType, [string]$recordName, [string]$content, [int]$ttl, [string]$comment, [object]$priority, [bool]$proxied) {
        <#
        .SYNOPSIS
        Creates a DNS record in Cloudflare.
        
        .PARAMETER zoneId
        The Cloudflare Zone ID.
        
        .PARAMETER recordType
        Record type (e.g., "TXT", "MX", "A").
        
        .PARAMETER recordName
        Full record name (e.g., "example.com" or "_forward-email.example.com").
        
        .PARAMETER content
        Record content/value.
        
        .PARAMETER ttl
        TTL in seconds (1 for automatic, or 60-86400).
        
        .PARAMETER comment
        Optional comment for the record.
        
        .PARAMETER priority
        Optional priority for MX records (1-65535).
        
        .PARAMETER proxied
        Whether to proxy the record through Cloudflare (default: false for TXT/MX).
        
        .RETURNS
        Created DNS record object.
        #>
        
        $uri = "$($this.BaseUrl)/zones/$zoneId/dns_records"
        
        $body = @{
            type = $recordType
            name = $recordName
            content = $content
            ttl = $ttl
        }
        
        if ($comment) {
            $body.comment = $comment
        }
        
        # Add priority for MX records
        if ($recordType -eq "MX" -and $priority) {
            $body.priority = $priority
        }
        
        # Set proxied status - TXT and MX records cannot be proxied
        if ($recordType -in @("TXT", "MX")) {
            $body.proxied = $false
        } else {
            $body.proxied = $proxied
        }
        
        return $this.InvokeWithRetry("POST", $uri, $body)
    }
    
    [object] CreateDnsRecord([string]$zoneId, [string]$recordType, [string]$recordName, [string]$content, [int]$ttl, [string]$comment, [object]$priority) {
        return $this.CreateDnsRecord($zoneId, $recordType, $recordName, $content, $ttl, $comment, $priority, $false)
    }
    
    [object] UpdateDnsRecord([string]$zoneId, [string]$recordId, [hashtable]$updates) {
        <#
        .SYNOPSIS
        Updates an existing DNS record.
        
        .PARAMETER zoneId
        The Cloudflare Zone ID.
        
        .PARAMETER recordId
        The DNS record ID.
        
        .PARAMETER updates
        Hashtable of fields to update.
        
        .RETURNS
        Updated DNS record object.
        #>
        
        $uri = "$($this.BaseUrl)/zones/$zoneId/dns_records/$recordId"
        return $this.InvokeWithRetry("PATCH", $uri, $updates)
    }
    
    [void] DeleteDnsRecord([string]$zoneId, [string]$recordId) {
        <#
        .SYNOPSIS
        Deletes a DNS record.
        
        .PARAMETER zoneId
        The Cloudflare Zone ID.
        
        .PARAMETER recordId
        The DNS record ID to delete.
        #>
        
        $uri = "$($this.BaseUrl)/zones/$zoneId/dns_records/$recordId"
        $this.InvokeWithRetry("DELETE", $uri, $null) | Out-Null
    }
    
    [bool] RecordExists([string]$zoneId, [string]$recordType, [string]$recordName, [string]$content) {
        <#
        .SYNOPSIS
        Checks if a DNS record already exists.
        
        .PARAMETER zoneId
        The Cloudflare Zone ID.
        
        .PARAMETER recordType
        Record type.
        
        .PARAMETER recordName
        Record name.
        
        .PARAMETER content
        Record content to match.
        
        .RETURNS
        True if record exists with matching content, false otherwise.
        #>
        
        try {
            $response = $this.ListDnsRecords($zoneId, $recordType, $recordName)
            
            foreach ($record in $response.result) {
                if ($record.content -eq $content) {
                    return $true
                }
            }
            
            return $false
        }
        catch {
            return $false
        }
    }
    
    [object] GetOrCreateDnsRecord([string]$zoneId, [string]$recordType, [string]$recordName, [string]$content, [int]$ttl, [string]$comment) {
        return $this.GetOrCreateDnsRecord($zoneId, $recordType, $recordName, $content, $ttl, $comment, $null, $false)
    }
    
    [object] GetOrCreateDnsRecord([string]$zoneId, [string]$recordType, [string]$recordName, [string]$content, [int]$ttl, [string]$comment, [object]$priority) {
        return $this.GetOrCreateDnsRecord($zoneId, $recordType, $recordName, $content, $ttl, $comment, $priority, $false)
    }
    
    [object] GetOrCreateDnsRecord([string]$zoneId, [string]$recordType, [string]$recordName, [string]$content, [int]$ttl, [string]$comment, [object]$priority, [bool]$proxied) {
        <#
        .SYNOPSIS
        Gets an existing DNS record or creates it if it doesn't exist (idempotent).
        
        .RETURNS
        DNS record object (existing or newly created).
        #>
        
        # Check if record already exists
        $response = $this.ListDnsRecords($zoneId, $recordType, $recordName)
        
        foreach ($record in $response.result) {
            if ($record.content -eq $content) {
                Write-Verbose "DNS record already exists: $recordType $recordName = $content"
                return $record
            }
        }
        
        # Record doesn't exist, create it
        Write-Verbose "Creating DNS record: $recordType $recordName = $content"
        return $this.CreateDnsRecord($zoneId, $recordType, $recordName, $content, $ttl, $comment, $priority, $proxied)
    }
    
    [object] CreateOrUpdateDnsRecord([string]$zoneId, [string]$recordName, [string]$recordType, [string]$content, [int]$ttl) {
        return $this.CreateOrUpdateDnsRecord($zoneId, $recordName, $recordType, $content, $ttl, $null, $false)
    }
    
    [object] CreateOrUpdateDnsRecord([string]$zoneId, [string]$recordName, [string]$recordType, [string]$content, [int]$ttl, [object]$priority) {
        return $this.CreateOrUpdateDnsRecord($zoneId, $recordName, $recordType, $content, $ttl, $priority, $false)
    }
    
    [object] CreateOrUpdateDnsRecord([string]$zoneId, [string]$recordName, [string]$recordType, [string]$content, [int]$ttl, [object]$priority, [bool]$proxied) {
        <#
        .SYNOPSIS
        Creates or updates a DNS record (idempotent operation).
        
        .DESCRIPTION
        This method checks if a DNS record with the same type, name, and content exists.
        If it exists, returns the existing record. If not, creates a new one.
        
        .RETURNS
        DNS record object (existing or newly created).
        #>
        
        return $this.GetOrCreateDnsRecord($zoneId, $recordType, $recordName, $content, $ttl, "", $priority, $proxied)
    }
}

function New-CloudflareClient {
    <#
    .SYNOPSIS
    Creates a new Cloudflare API client.
    
    .PARAMETER ApiToken
    Cloudflare API token with DNS Write permissions.
    
    .PARAMETER BaseUrl
    API base URL (default: https://api.cloudflare.com/client/v4).
    
    .PARAMETER RetryConfig
    Hashtable with retry configuration.
    
    .EXAMPLE
    $client = New-CloudflareClient -ApiToken $env:CLOUDFLARE_API_TOKEN -RetryConfig @{MaxRetries=5; InitialRetryDelay=5; MaxRetryDelay=300; RateLimitDelay=60}
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ApiToken,
        
        [Parameter(Mandatory=$false)]
        [string]$BaseUrl = "https://api.cloudflare.com/client/v4",
        
        [Parameter(Mandatory=$true)]
        [hashtable]$RetryConfig
    )
    
    return [CloudflareClient]::new($ApiToken, $BaseUrl, $RetryConfig)
}

Export-ModuleMember -Function New-CloudflareClient
