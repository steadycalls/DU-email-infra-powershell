<#
.SYNOPSIS
    Phase 3: Standalone Alias Generation for Verified Domains

.DESCRIPTION
    This script creates email aliases for domains that have been verified in Forward Email.
    It can be run independently after manually verifying domains in the Forward Email dashboard.
    
    Features:
    - Creates info@ alias for each verified domain
    - Generates 49 additional unique aliases per domain (50 total)
    - Uses 60/40 mix of firstName vs firstName.lastName format
    - Ensures uniqueness across all domains
    - Exports all aliases to aliases.txt
    - Reads from state.json to find verified domains
    - Can process specific domains or all verified domains

.PARAMETER DomainsFile
    Optional path to text file containing specific domains to process.
    If not specified, processes all domains in "Verified" state from state.json.

.PARAMETER StateFile
    Path to state persistence file (default: data/state.json).

.PARAMETER LogFile
    Path to log file (default: logs/alias-generation.log).

.PARAMETER LogLevel
    Logging level: DEBUG, INFO, WARNING, ERROR, CRITICAL (default: INFO).

.PARAMETER AliasCount
    Number of aliases to generate per domain (default: 50, includes info@).

.PARAMETER FirstNamePercent
    Percentage of aliases using firstName only format (default: 60).

.PARAMETER DryRun
    If specified, shows what would be created without making API calls.

.EXAMPLE
    .\Phase3-AliasGeneration.ps1
    
    Processes all domains in "Verified" state from state.json

.EXAMPLE
    .\Phase3-AliasGeneration.ps1 -DomainsFile "verified-domains.txt"
    
    Processes only domains listed in the specified file

.EXAMPLE
    .\Phase3-AliasGeneration.ps1 -AliasCount 100 -FirstNamePercent 50
    
    Creates 100 aliases per domain with 50/50 firstName/fullName mix

.EXAMPLE
    .\Phase3-AliasGeneration.ps1 -DryRun
    
    Shows what would be created without making API calls

.NOTES
    Requires PowerShell 7+ and FORWARD_EMAIL_API_KEY environment variable.
    Domains must be verified in Forward Email before running this script.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DomainsFile = "",
    
    [Parameter(Mandatory=$false)]
    [string]$StateFile = "data/state.json",
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "logs/alias-generation.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL")]
    [string]$LogLevel = "INFO",
    
    [Parameter(Mandatory=$false)]
    [int]$AliasCount = 50,
    
    [Parameter(Mandatory=$false)]
    [ValidateRange(0, 100)]
    [int]$FirstNamePercent = 60,
    
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
    
    Import-Module (Join-Path $modulePath "Logger.psm1") -Force
    Write-Host "[PASS] Logger module loaded" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to load modules: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Phase 3: Alias Generation for Verified Domains" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Initialize configuration
try {
    $config = New-EmailInfraConfig -ConfigFile "config.json"
    Write-Host "[PASS] Configuration loaded" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to load configuration: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize state manager
try {
    $stateManager = New-StateManager -StateFile $StateFile
    Write-Host "[PASS] State manager initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize state manager: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize logger
try {
    $logger = New-Logger -LogFile $LogFile -LogLevel $LogLevel
    Write-Host "[PASS] Logger initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize logger: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Initialize Forward Email client
try {
    $forwardEmailClient = New-ForwardEmailClient -Config $config
    Write-Host "[PASS] Forward Email client initialized" -ForegroundColor Green
}
catch {
    Write-Host "[FAIL] Failed to initialize Forward Email client: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Determine which domains to process
$domainsToProcess = @()

if ($DomainsFile -and (Test-Path $DomainsFile)) {
    # Load domains from file
    $domainsToProcess = Get-Content $DomainsFile | Where-Object { $_ -match '\S' } | ForEach-Object { $_.Trim() }
    Write-Host "Loaded $($domainsToProcess.Count) domains from $DomainsFile" -ForegroundColor Green
}
else {
    # Load all verified domains from state.json
    $state = $stateManager.GetState()
    $allDomains = $state.Domains.PSObject.Properties
    
    foreach ($domainProp in $allDomains) {
        $domain = $domainProp.Name
        $record = $domainProp.Value
        
        # Include domains that are Verified but not yet AliasesCreated
        if ($record.State -eq "Verified") {
            $domainsToProcess += $domain
        }
        # Also show domains that already have aliases
        elseif ($record.State -in @("AliasesCreated", "Completed")) {
            Write-Host "  ℹ $domain already has aliases (State: $($record.State))" -ForegroundColor Gray
        }
    }
    
    Write-Host "Found $($domainsToProcess.Count) verified domains ready for alias generation" -ForegroundColor Green
}

if ($domainsToProcess.Count -eq 0) {
    Write-Host ""
    Write-Host "No domains to process!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  1. Verify domains in Forward Email dashboard first" -ForegroundColor Gray
    Write-Host "  2. Update state.json to mark domains as 'Verified'" -ForegroundColor Gray
    Write-Host "  3. Provide a domains file with -DomainsFile parameter" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] Would process the following domains:" -ForegroundColor Yellow
    foreach ($domain in $domainsToProcess) {
        Write-Host "  - $domain" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "[DRY RUN] Would create $AliasCount aliases per domain" -ForegroundColor Yellow
    Write-Host "[DRY RUN] Total aliases: $($domainsToProcess.Count * $AliasCount)" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

$logger.Info("========================================", $null, $null)
$logger.Info("Phase 3: Alias Generation Starting", $null, $null)
$logger.Info("Domains to process: $($domainsToProcess.Count)", $null, $null)
$logger.Info("Aliases per domain: $AliasCount", $null, $null)
$logger.Info("FirstName %: $FirstNamePercent", $null, $null)
$logger.Info("========================================", $null, $null)

#==============================================================================
# NAME LISTS FOR ALIAS GENERATION
#==============================================================================

$firstNames = @(
    "james", "john", "robert", "michael", "william", "david", "richard", "joseph", "thomas", "charles",
    "christopher", "daniel", "matthew", "anthony", "donald", "mark", "paul", "steven", "andrew", "kenneth",
    "joshua", "kevin", "brian", "george", "edward", "ronald", "timothy", "jason", "jeffrey", "ryan",
    "jacob", "gary", "nicholas", "eric", "jonathan", "stephen", "larry", "justin", "scott", "brandon",
    "benjamin", "samuel", "frank", "gregory", "raymond", "alexander", "patrick", "jack", "dennis", "jerry",
    "mary", "patricia", "jennifer", "linda", "barbara", "elizabeth", "susan", "jessica", "sarah", "karen",
    "nancy", "lisa", "betty", "margaret", "sandra", "ashley", "kimberly", "emily", "donna", "michelle",
    "dorothy", "carol", "amanda", "melissa", "deborah", "stephanie", "rebecca", "sharon", "laura", "cynthia",
    "kathleen", "amy", "angela", "shirley", "anna", "brenda", "pamela", "emma", "nicole", "helen",
    "samantha", "katherine", "christine", "debra", "rachel", "catherine", "carolyn", "janet", "ruth", "maria"
)

$lastNames = @(
    "smith", "johnson", "williams", "brown", "jones", "garcia", "miller", "davis", "rodriguez", "martinez",
    "hernandez", "lopez", "gonzalez", "wilson", "anderson", "thomas", "taylor", "moore", "jackson", "martin",
    "lee", "perez", "thompson", "white", "harris", "sanchez", "clark", "ramirez", "lewis", "robinson",
    "walker", "young", "allen", "king", "wright", "scott", "torres", "nguyen", "hill", "flores",
    "green", "adams", "nelson", "baker", "hall", "rivera", "campbell", "mitchell", "carter", "roberts",
    "gomez", "phillips", "evans", "turner", "diaz", "parker", "cruz", "edwards", "collins", "reyes",
    "stewart", "morris", "morales", "murphy", "cook", "rogers", "gutierrez", "ortiz", "morgan", "cooper",
    "peterson", "bailey", "reed", "kelly", "howard", "ramos", "kim", "cox", "ward", "richardson",
    "watson", "brooks", "chavez", "wood", "james", "bennett", "gray", "mendoza", "ruiz", "hughes",
    "price", "alvarez", "castillo", "sanders", "patel", "myers", "long", "ross", "foster", "jimenez"
)

# Track used aliases globally to ensure uniqueness
$usedAliases = @{}

# Function to generate unique alias
function Get-UniqueAlias {
    param(
        [string]$Domain,
        [bool]$UseFullName
    )
    
    $maxAttempts = 100
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        if ($UseFullName) {
            $firstName = $firstNames | Get-Random
            $lastName = $lastNames | Get-Random
            $alias = "$firstName.$lastName"
        }
        else {
            $alias = $firstNames | Get-Random
        }
        
        $fullEmail = "$alias@$Domain"
        
        if (-not $usedAliases.ContainsKey($fullEmail)) {
            $usedAliases[$fullEmail] = $true
            return $alias
        }
    }
    
    # Fallback: append random number
    $alias = "$alias$(Get-Random -Minimum 1000 -Maximum 9999)"
    $fullEmail = "$alias@$Domain"
    $usedAliases[$fullEmail] = $true
    return $alias
}

#==============================================================================
# ALIAS GENERATION
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Creating Aliases for Verified Domains" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$failedCount = 0
$allAliases = @()
$recipient = "gmb@decisionsunlimited.io"

$domainIndex = 0
$totalDomains = $domainsToProcess.Count

foreach ($domain in $domainsToProcess) {
    $domainIndex++
    
    Write-Host "[$domainIndex/$totalDomains] Creating aliases for: $domain" -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor DarkGray
    $logger.Info("[$domain] Creating aliases $domainIndex/$totalDomains", $domain, $null)
    
    # Load domain record
    $record = $stateManager.GetDomain($domain)
    if ($null -eq $record) {
        Write-Host "  ⚠ Domain not found in state.json - creating new record" -ForegroundColor Yellow
        $record = $stateManager.CreateDomain($domain)
        $record.State = "Verified"  # Assume verified since we're processing it
        $stateManager.UpdateDomain($domain, $record)
    }
    
    # Check if domain already has aliases
    if ($record.State -in @("AliasesCreated", "Completed")) {
        Write-Host "  ℹ Domain already has aliases - skipping" -ForegroundColor Gray
        $logger.Info("Domain already has aliases, skipping", $domain, $null)
        
        # Add existing aliases to export list
        if ($record.Aliases.Count -gt 0) {
            foreach ($alias in $record.Aliases) {
                $allAliases += "$alias@$domain"
            }
        }
        $successCount++
        Write-Host ""
        continue
    }
    
    try {
        Write-Host "  Creating email aliases..." -ForegroundColor Yellow
        $logger.Info("Creating email aliases", $domain, $null)
        
        $domainAliases = @()
        
        # Create info@ alias first
        try {
            Write-Host "    [1/$AliasCount] Creating info@ alias..." -ForegroundColor Gray
            $infoAlias = $forwardEmailClient.CreateAlias($domain, "info", @($recipient), "Info alias", @())
            $domainAliases += "info"
            $allAliases += "info@$domain"
            $usedAliases["info@$domain"] = $true
            $logger.Info("Created info@ alias", $domain, @{AliasId = $infoAlias.id})
            Write-Host "      ✓ Created info@$domain" -ForegroundColor Green
        }
        catch {
            $errorMsg = $_.Exception.Message
            if ($errorMsg -match "already exists" -or $errorMsg -match "duplicate") {
                $logger.Warning("info@ alias already exists", $domain, $null)
                Write-Host "      ℹ info@ already exists (skipping)" -ForegroundColor Gray
                $domainAliases += "info"
                $allAliases += "info@$domain"
                $usedAliases["info@$domain"] = $true
            }
            else {
                $logger.Warning("Failed to create info@ alias: $errorMsg", $domain, $null)
                Write-Host "      ⚠ Failed to create info@: $errorMsg" -ForegroundColor Yellow
            }
        }
        
        # Generate additional unique aliases
        $additionalAliases = $AliasCount - 1  # Subtract 1 for info@
        Write-Host "    [2/$AliasCount] Generating $additionalAliases unique aliases..." -ForegroundColor Gray
        $aliasesCreated = 0
        $aliasesTarget = $additionalAliases
        
        for ($i = 0; $i -lt $aliasesTarget; $i++) {
            try {
                # Determine if using firstName only or firstName.lastName
                $useFullName = (Get-Random -Minimum 1 -Maximum 100) -gt $FirstNamePercent
                $aliasName = Get-UniqueAlias -Domain $domain -UseFullName $useFullName
                
                $newAlias = $forwardEmailClient.CreateAlias($domain, $aliasName, @($recipient), "Generated alias", @())
                $domainAliases += $aliasName
                $allAliases += "$aliasName@$domain"
                $aliasesCreated++
                
                # Progress updates
                if (($aliasesCreated % 10) -eq 0) {
                    Write-Host "      ✓ Created $aliasesCreated/$aliasesTarget aliases" -ForegroundColor Green
                }
            }
            catch {
                $errorMsg = $_.Exception.Message
                if ($errorMsg -match "already exists" -or $errorMsg -match "duplicate") {
                    # Alias already exists, count it as success
                    $domainAliases += $aliasName
                    $allAliases += "$aliasName@$domain"
                    $aliasesCreated++
                }
                else {
                    $logger.Warning("Failed to create alias ${aliasName}: ${errorMsg}", $domain, $null)
                }
            }
        }
        
        Write-Host "      ✓ Created $aliasesCreated additional aliases" -ForegroundColor Green
        Write-Host "      ✓ Total: $($domainAliases.Count) aliases for $domain" -ForegroundColor Green
        
        # Update state
        $record.Aliases = $domainAliases
        $record.State = "AliasesCreated"
        $stateManager.UpdateDomain($domain, $record)
        $successCount++
        
        Write-Host "  ✓ Alias generation complete for $domain" -ForegroundColor Green
    }
    catch {
        $errorMessage = $_.Exception.Message
        $logger.Error("Failed to create aliases: $errorMessage", $domain, $null)
        Write-Host "  ✗ ERROR: $errorMessage" -ForegroundColor Red
        $record.AddError("alias_generation", $errorMessage, "ALIAS_ERROR", @{})
        $record.MarkFailed()
        $stateManager.UpdateDomain($domain, $record)
        $failedCount++
    }
    
    Write-Host ""
}

#==============================================================================
# EXPORT ALIASES
#==============================================================================

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "Exporting Aliases" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

$aliasesFile = Join-Path $PSScriptRoot "data/aliases.txt"
$allAliases | Sort-Object | Out-File -FilePath $aliasesFile -Encoding UTF8
Write-Host "✓ Exported $($allAliases.Count) aliases to: $aliasesFile" -ForegroundColor Green
$logger.Info("Exported aliases to file", $null, @{Count = $allAliases.Count; File = $aliasesFile})

#==============================================================================
# FINAL SUMMARY
#==============================================================================

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "ALIAS GENERATION COMPLETE" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "Results:" -ForegroundColor Yellow
Write-Host "  - Domains Processed: $totalDomains" -ForegroundColor Cyan
Write-Host "  - Successful: $successCount" -ForegroundColor Green
Write-Host "  - Failed: $failedCount" -ForegroundColor Red
Write-Host "  - Total Aliases: $($allAliases.Count)" -ForegroundColor Cyan
Write-Host "  - Avg per Domain: $([Math]::Round($allAliases.Count / $successCount, 1))" -ForegroundColor Cyan
Write-Host ""
Write-Host "Files:" -ForegroundColor Yellow
Write-Host "  - State: $StateFile" -ForegroundColor Gray
Write-Host "  - Aliases: $aliasesFile" -ForegroundColor Gray
Write-Host "  - Logs: $LogFile" -ForegroundColor Gray
Write-Host ""

if ($failedCount -gt 0) {
    Write-Host "⚠ Some domains failed. Check logs for details:" -ForegroundColor Yellow
    Write-Host "  Get-Content $LogFile | Select-String 'ERROR'" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Review aliases.txt to see all generated email addresses" -ForegroundColor Gray
Write-Host "  2. Test email forwarding by sending to a few aliases" -ForegroundColor Gray
Write-Host "  3. Verify in Forward Email dashboard: https://forwardemail.net/my-account/domains" -ForegroundColor Gray
Write-Host ""
Write-Host "=" * 80 -ForegroundColor Cyan

$logger.Info("========================================", $null, $null)
$logger.Info("ALIAS GENERATION COMPLETE", $null, $null)
$logger.Info("Processed=$totalDomains, Success=$successCount, Failed=$failedCount, TotalAliases=$($allAliases.Count)", $null, $null)
$logger.Info("========================================", $null, $null)
