# PowerShell Script to Distribute Cached Transfer Folders to City Folders
# This script:
# 1. Extracts "Cached Transfer.zip" from C:\Users\kyle\Desktop\Cached Browsers
# 2. Finds all city folders (folders with state abbreviations) in E:\Alliance Decks
# 3. Randomly distributes 5 folders from the extracted content to each city folder
# 4. Logs the distribution to a CSV file for auditing

# Define source and destination paths
$sourceCachedBrowsers = "C:\Users\kyle\Desktop\Cached Browsers"
$cachedTransferZipName = "Cached Transfer.zip"
$destinationRoot = "E:\Alliance Decks"
$extractFolderName = "_CachedTransferExtracted"

# Create log file with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFilePath = Join-Path -Path $destinationRoot -ChildPath "Distribution_Log_$timestamp.csv"

# Initialize log array
$logEntries = @()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cached Transfer Distribution Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify source Cached Browsers folder exists
if (-not (Test-Path -Path $sourceCachedBrowsers)) {
    Write-Host "ERROR: Source folder not found: $sourceCachedBrowsers" -ForegroundColor Red
    exit 1
}

# Verify Cached Transfer ZIP file exists
$cachedTransferZipPath = Join-Path -Path $sourceCachedBrowsers -ChildPath $cachedTransferZipName
if (-not (Test-Path -Path $cachedTransferZipPath)) {
    Write-Host "ERROR: Cached Transfer ZIP file not found: $cachedTransferZipPath" -ForegroundColor Red
    exit 1
}

# Verify destination root exists
if (-not (Test-Path -Path $destinationRoot)) {
    Write-Host "ERROR: Destination root folder not found: $destinationRoot" -ForegroundColor Red
    exit 1
}

# ========================================
# PHASE 1: Extract Cached Transfer ZIP
# ========================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 1: Extract Cached Transfer ZIP" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$extractPath = Join-Path -Path $sourceCachedBrowsers -ChildPath $extractFolderName

if (Test-Path -Path $extractPath) {
    Write-Host "Extracted folder already exists, skipping extraction..." -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "Extracting Cached Transfer ZIP file..." -ForegroundColor Cyan
    try {
        Expand-Archive -Path $cachedTransferZipPath -DestinationPath $extractPath -Force
        Write-Host "Extraction completed successfully" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Host "ERROR: Failed to extract ZIP file: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Get all folders inside the extracted Cached Transfer
$cachedTransferFolders = Get-ChildItem -Path $extractPath -Directory

if ($cachedTransferFolders.Count -eq 0) {
    Write-Host "ERROR: No folders found inside extracted Cached Transfer" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($cachedTransferFolders.Count) folders inside Cached Transfer" -ForegroundColor Cyan
Write-Host ""

# ========================================
# PHASE 2: Find All City Folders
# ========================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 2: Find All City Folders" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get all city folders from inside each state folder
$cityFolders = @()
$stateFolders = Get-ChildItem -Path $destinationRoot -Directory | Sort-Object Name

foreach ($stateFolder in $stateFolders) {
    # Get subfolders inside each state folder that match city pattern (City, ST)
    $stateCityFolders = Get-ChildItem -Path $stateFolder.FullName -Directory | Where-Object { $_.Name -match ',\s+[A-Z]{2}$' }
    if ($stateCityFolders) {
        $cityFolders += $stateCityFolders
    }
}

if ($cityFolders.Count -eq 0) {
    Write-Host "WARNING: No city folders with state abbreviations found inside state folders" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($cityFolders.Count) city folders with state abbreviations" -ForegroundColor Cyan
Write-Host "Logging distribution to: $logFilePath" -ForegroundColor Cyan
Write-Host ""

# ========================================
# PHASE 3: Distribute Folders to Cities
# ========================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 3: Distribute Folders to Cities" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$successCount = 0
$errorCount = 0
$totalCount = $cityFolders.Count

# Distribute 5 random folders to each city folder
foreach ($cityFolder in $cityFolders) {
    Write-Host "[$($successCount + $errorCount + 1)/$totalCount] Processing: $($cityFolder.Name)" -ForegroundColor White
    
    try {
        # Get 5 random folders from the extracted Cached Transfer
        $randomFolders = $cachedTransferFolders | Get-Random -Count 5
        
        Write-Host "  - Selected 5 random folders to distribute" -ForegroundColor Gray
        
        # Copy each random folder to the city folder root
        $foldersCopied = 0
        foreach ($folder in $randomFolders) {
            $destinationFolderPath = Join-Path -Path $cityFolder.FullName -ChildPath $folder.Name
            
            # Remove if already exists
            if (Test-Path -Path $destinationFolderPath) {
                Remove-Item -Path $destinationFolderPath -Recurse -Force
            }
            
            # Copy from the extracted Cached Transfer folder
            $sourceFolderPath = Join-Path -Path $extractPath -ChildPath $folder.Name
            Copy-Item -Path $sourceFolderPath -Destination $destinationFolderPath -Recurse -Force
            
            Write-Host "    * Copied: $($folder.Name)" -ForegroundColor Gray
            
            # Log the successful copy
            $logEntries += [PSCustomObject]@{
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                CityFolder = $cityFolder.Name
                FolderName = $folder.Name
                Status = "SUCCESS"
            }
            
            $foldersCopied++
        }
        
        Write-Host "  - SUCCESS: Distributed $foldersCopied folders" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  - ERROR: Failed to distribute folders to $($cityFolder.Name)" -ForegroundColor Red
        Write-Host "  - Error details: $($_.Exception.Message)" -ForegroundColor Red
        
        # Log the error
        $logEntries += [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            CityFolder = $cityFolder.Name
            FolderName = "N/A"
            Status = "ERROR: $($_.Exception.Message)"
        }
        
        $errorCount++
    }
    
    Write-Host ""
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 3 Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total city folders: $totalCount" -ForegroundColor White
Write-Host "Successful distributions: $successCount" -ForegroundColor Green
Write-Host "Failed distributions: $errorCount" -ForegroundColor Red
Write-Host ""

# Export log to CSV
try {
    $logEntries | Export-Csv -Path $logFilePath -NoTypeInformation -Encoding UTF8
    Write-Host "Log file created successfully: $logFilePath" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Host "WARNING: Failed to create log file: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ""
}

# Final Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "All Operations Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total city folders processed: $totalCount" -ForegroundColor White
Write-Host "Successful distributions: $successCount" -ForegroundColor Green
Write-Host "Failed distributions: $errorCount" -ForegroundColor Red
Write-Host ""
Write-Host "Audit Log: $logFilePath" -ForegroundColor Cyan
Write-Host ""

if ($errorCount -eq 0) {
    Write-Host "All operations completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Some operations failed. Please review the errors above and check the log file." -ForegroundColor Yellow
}
