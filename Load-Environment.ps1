<#
.SYNOPSIS
    Loads environment variables from .env file into the current PowerShell session.

.DESCRIPTION
    This script reads the .env file and sets environment variables for the current process.
    This is useful on Windows where .env files are not automatically loaded.

.PARAMETER EnvFile
    Path to the .env file (default: .env in the current directory).

.EXAMPLE
    .\Load-Environment.ps1

.EXAMPLE
    .\Load-Environment.ps1 -EnvFile "config\.env"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$EnvFile = ".env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path $EnvFile)) {
    Write-Error "Environment file not found: $EnvFile"
    Write-Host ""
    Write-Host "Please create a .env file with your API credentials:" -ForegroundColor Yellow
    Write-Host "  1. Copy .env.example to .env" -ForegroundColor White
    Write-Host "  2. Edit .env and add your API keys" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "Loading environment variables from $EnvFile..." -ForegroundColor Cyan

$envVarsLoaded = 0

Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    
    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
        return
    }
    
    # Parse key=value
    if ($line -match '^([^=]+)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        
        # Remove quotes if present
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        elseif ($value.StartsWith("'") -and $value.EndsWith("'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        
        # Set environment variable for current process
        [Environment]::SetEnvironmentVariable($key, $value, 'Process')
        
        # Mask sensitive values in output
        if ($key -like "*KEY*" -or $key -like "*TOKEN*" -or $key -like "*SECRET*" -or $key -like "*PASSWORD*") {
            $maskedValue = if ($value.Length -gt 8) { $value.Substring(0, 8) + "..." } else { "***" }
            Write-Host "  ✓ $key = $maskedValue" -ForegroundColor Green
        } else {
            Write-Host "  ✓ $key = $value" -ForegroundColor Green
        }
        
        $envVarsLoaded++
    }
}

Write-Host ""
Write-Host "Loaded $envVarsLoaded environment variables" -ForegroundColor Green
Write-Host ""
Write-Host "Environment variables are now available in this PowerShell session." -ForegroundColor Cyan
Write-Host "You can now run the automation scripts:" -ForegroundColor Cyan
Write-Host "  .\Test-Setup.ps1" -ForegroundColor White
Write-Host "  .\Setup-EmailInfrastructure.ps1 -DomainsFile data\domains.txt" -ForegroundColor White
Write-Host ""
