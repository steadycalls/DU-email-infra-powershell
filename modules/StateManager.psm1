# StateManager.psm1
# State management for domain processing pipeline

enum DomainState {
    Pending
    ForwardEmailAdded
    DnsConfigured
    Verifying
    Verified
    AliasesCreated
    Completed
    Failed
}

class DomainRecord {
    [string]$Domain
    [DomainState]$State
    [string]$ForwardEmailDomainId
    [string]$CloudflareZoneId
    [hashtable[]]$DnsRecords
    [hashtable[]]$Aliases
    [int]$Attempts
    [datetime]$LastAttempt
    [datetime]$CompletedAt
    [hashtable[]]$Errors
    [hashtable]$Metadata
    
    DomainRecord([string]$domain) {
        $this.Domain = $domain
        $this.State = [DomainState]::Pending
        $this.DnsRecords = @()
        $this.Aliases = @()
        $this.Attempts = 0
        $this.Errors = @()
        $this.Metadata = @{}
    }
    
    [void] AddError([string]$stage, [string]$message, [string]$code, [hashtable]$details) {
        $error = @{
            Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            Stage = $stage
            Message = $message
            Code = $code
            Details = $details
        }
        $this.Errors += $error
    }
    
    [void] UpdateAttempt() {
        $this.Attempts++
        $this.LastAttempt = (Get-Date).ToUniversalTime()
    }
    
    [void] MarkCompleted() {
        $this.State = [DomainState]::Completed
        $this.CompletedAt = (Get-Date).ToUniversalTime()
    }
    
    [void] MarkFailed() {
        $this.State = [DomainState]::Failed
    }
    
    [hashtable] ToHashtable() {
        return @{
            State = $this.State.ToString()
            ForwardEmailDomainId = $this.ForwardEmailDomainId
            CloudflareZoneId = $this.CloudflareZoneId
            DnsRecords = $this.DnsRecords
            Aliases = $this.Aliases
            Attempts = $this.Attempts
            LastAttempt = if ($this.LastAttempt) { $this.LastAttempt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") } else { $null }
            CompletedAt = if ($this.CompletedAt) { $this.CompletedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") } else { $null }
            Errors = $this.Errors
            Metadata = $this.Metadata
        }
    }
    
    static [DomainRecord] FromHashtable([string]$domain, [hashtable]$data) {
        $record = [DomainRecord]::new($domain)
        $record.State = [DomainState]$data.State
        $record.ForwardEmailDomainId = $data.ForwardEmailDomainId
        $record.CloudflareZoneId = $data.CloudflareZoneId
        $record.DnsRecords = $data.DnsRecords
        $record.Aliases = $data.Aliases
        $record.Attempts = $data.Attempts
        
        if ($data.LastAttempt) {
            $record.LastAttempt = [datetime]::Parse($data.LastAttempt)
        }
        
        if ($data.CompletedAt) {
            $record.CompletedAt = [datetime]::Parse($data.CompletedAt)
        }
        
        $record.Errors = $data.Errors
        $record.Metadata = $data.Metadata
        
        return $record
    }
}

class StateManager {
    [string]$StateFile
    [hashtable]$Domains
    hidden [object]$Lock
    
    StateManager([string]$stateFile) {
        $this.StateFile = $stateFile
        $this.Domains = @{}
        $this.Lock = [System.Threading.Mutex]::new($false, "EmailInfraStateManager")
        $this.EnsureDirectory()
        $this.Load()
    }
    
    hidden [void] EnsureDirectory() {
        $directory = Split-Path -Parent $this.StateFile
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }
    
    hidden [void] Load() {
        if (-not (Test-Path $this.StateFile)) {
            Write-Host "No existing state file found. Starting fresh."
            return
        }
        
        try {
            $data = Get-Content $this.StateFile -Raw | ConvertFrom-Json
            
            foreach ($property in $data.Domains.PSObject.Properties) {
                $domain = $property.Name
                $domainData = @{}
                
                # Convert PSCustomObject to hashtable
                foreach ($prop in $property.Value.PSObject.Properties) {
                    $domainData[$prop.Name] = $prop.Value
                }
                
                $this.Domains[$domain] = [DomainRecord]::FromHashtable($domain, $domainData)
            }
            
            Write-Host "Loaded state for $($this.Domains.Count) domains from $($this.StateFile)"
        }
        catch {
            Write-Warning "Error loading state file: $_"
            
            # Backup corrupted state file
            $backupFile = "$($this.StateFile).backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            if (Test-Path $this.StateFile) {
                Copy-Item $this.StateFile $backupFile
                Write-Warning "Corrupted state file backed up to $backupFile"
            }
        }
    }
    
    hidden [void] Save() {
        $this.Lock.WaitOne() | Out-Null
        
        try {
            $domainsData = @{}
            foreach ($key in $this.Domains.Keys) {
                $domainsData[$key] = $this.Domains[$key].ToHashtable()
            }
            
            $data = @{
                Version = "1.0"
                LastUpdated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                Domains = $domainsData
            }
            
            # Write to temp file first, then rename (atomic operation)
            $tempFile = "$($this.StateFile).tmp"
            $data | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Force
            Move-Item -Path $tempFile -Destination $this.StateFile -Force
        }
        finally {
            $this.Lock.ReleaseMutex()
        }
    }
    
    [DomainRecord] GetDomain([string]$domain) {
        return $this.Domains[$domain]
    }
    
    [DomainRecord] AddDomain([string]$domain) {
        $this.Lock.WaitOne() | Out-Null
        
        try {
            if (-not $this.Domains.ContainsKey($domain)) {
                $this.Domains[$domain] = [DomainRecord]::new($domain)
                $this.Save()
            }
            return $this.Domains[$domain]
        }
        finally {
            $this.Lock.ReleaseMutex()
        }
    }
    
    [void] UpdateDomain([string]$domain, [DomainRecord]$record) {
        $this.Lock.WaitOne() | Out-Null
        
        try {
            $this.Domains[$domain] = $record
            $this.Save()
        }
        finally {
            $this.Lock.ReleaseMutex()
        }
    }
    
    [DomainRecord[]] GetDomainsByState([DomainState]$state) {
        return $this.Domains.Values | Where-Object { $_.State -eq $state }
    }
    
    [DomainRecord[]] GetAllDomains() {
        return $this.Domains.Values
    }
    
    [hashtable] GetSummary() {
        $summary = @{}
        
        foreach ($state in [Enum]::GetValues([DomainState])) {
            $summary[$state.ToString()] = 0
        }
        
        foreach ($record in $this.Domains.Values) {
            $summary[$record.State.ToString()]++
        }
        
        return $summary
    }
    
    [void] ExportFailures([string]$outputFile) {
        $failedDomains = $this.GetDomainsByState([DomainState]::Failed)
        
        $failuresData = @{
            Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            TotalFailures = $failedDomains.Count
            Domains = @{}
        }
        
        foreach ($record in $failedDomains) {
            $failuresData.Domains[$record.Domain] = @{
                Attempts = $record.Attempts
                LastAttempt = if ($record.LastAttempt) { $record.LastAttempt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") } else { $null }
                Errors = $record.Errors
                Metadata = $record.Metadata
            }
        }
        
        # Ensure directory exists
        $directory = Split-Path -Parent $outputFile
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        
        $failuresData | ConvertTo-Json -Depth 10 | Set-Content -Path $outputFile -Force
        Write-Host "Exported $($failedDomains.Count) failed domains to $outputFile"
    }
}

function New-StateManager {
    <#
    .SYNOPSIS
    Creates a new state manager for domain processing.
    
    .PARAMETER StateFile
    Path to the state file for persistence.
    
    .EXAMPLE
    $stateManager = New-StateManager -StateFile "data/state.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$StateFile
    )
    
    return [StateManager]::new($StateFile)
}

Export-ModuleMember -Function New-StateManager
