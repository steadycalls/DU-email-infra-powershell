# Logger.psm1
# Logging functionality for email infrastructure automation

enum LogLevel {
    DEBUG = 0
    INFO = 1
    WARNING = 2
    ERROR = 3
    CRITICAL = 4
}

class Logger {
    [string]$LogFile
    [LogLevel]$MinLevel
    hidden [object]$Lock
    
    Logger([string]$logFile, [string]$minLevel) {
        $this.LogFile = $logFile
        $this.MinLevel = [LogLevel]$minLevel
        $this.Lock = [System.Threading.Mutex]::new($false, "EmailInfraLogger")
        $this.EnsureDirectory()
    }
    
    hidden [void] EnsureDirectory() {
        $directory = Split-Path -Parent $this.LogFile
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }
    
    hidden [void] WriteLog([LogLevel]$level, [string]$message, [string]$domain, [hashtable]$context) {
        if ($level -lt $this.MinLevel) {
            return
        }
        
        $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        
        $logEntry = @{
            Timestamp = $timestamp
            Level = $level.ToString()
            Message = $message
        }
        
        if ($domain) {
            $logEntry.Domain = $domain
        }
        
        if ($context) {
            $logEntry.Context = $context
        }
        
        $logLine = $logEntry | ConvertTo-Json -Compress
        
        # Write to console with color
        $color = switch ($level) {
            ([LogLevel]::DEBUG) { "Gray" }
            ([LogLevel]::INFO) { "White" }
            ([LogLevel]::WARNING) { "Yellow" }
            ([LogLevel]::ERROR) { "Red" }
            ([LogLevel]::CRITICAL) { "DarkRed" }
            default { "White" }
        }
        
        $consoleMessage = "[$timestamp] [$($level.ToString())]"
        if ($domain) {
            $consoleMessage += " [$domain]"
        }
        $consoleMessage += " $message"
        
        Write-Host $consoleMessage -ForegroundColor $color
        
        # Write to file
        $this.Lock.WaitOne() | Out-Null
        try {
            Add-Content -Path $this.LogFile -Value $logLine -Force
        }
        finally {
            $this.Lock.ReleaseMutex()
        }
    }
    
    [void] Debug([string]$message, [string]$domain, [hashtable]$context) {
        $this.WriteLog([LogLevel]::DEBUG, $message, $domain, $context)
    }
    
    [void] Info([string]$message, [string]$domain, [hashtable]$context) {
        $this.WriteLog([LogLevel]::INFO, $message, $domain, $context)
    }
    
    [void] Warning([string]$message, [string]$domain, [hashtable]$context) {
        $this.WriteLog([LogLevel]::WARNING, $message, $domain, $context)
    }
    
    [void] Error([string]$message, [string]$domain, [hashtable]$context) {
        $this.WriteLog([LogLevel]::ERROR, $message, $domain, $context)
    }
    
    [void] Critical([string]$message, [string]$domain, [hashtable]$context) {
        $this.WriteLog([LogLevel]::CRITICAL, $message, $domain, $context)
    }
}

function New-Logger {
    <#
    .SYNOPSIS
    Creates a new logger instance.
    
    .PARAMETER LogFile
    Path to the log file.
    
    .PARAMETER MinLevel
    Minimum log level to record (DEBUG, INFO, WARNING, ERROR, CRITICAL).
    
    .EXAMPLE
    $logger = New-Logger -LogFile "logs/automation.log" -MinLevel "INFO"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFile,
        
        [Parameter(Mandatory=$false)]
        [string]$MinLevel = "INFO"
    )
    
    return [Logger]::new($LogFile, $MinLevel)
}

Export-ModuleMember -Function New-Logger
