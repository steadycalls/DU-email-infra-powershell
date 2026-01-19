# PowerShell Script to Copy "Cached Browsers" and Distribute "Cached Transfer" Folders
# This script:
# 1. Copies C:\Users\kyle\Desktop\Cached Browsers to all subfolders in E:\Alliance Decks
# 2. Extracts the "Cached Transfer" folder from inside "Cached Browsers"
# 3. Randomly distributes 5 folders from "Cached Transfer" to each city folder (folders with state abbreviations)
# 4. Logs the distribution to a CSV file for auditing

# Define source and destination paths
$sourcePath = "C:\Users\kyle\Desktop\Cached Browsers"
$destinationRoot = "E:\Alliance Decks"
$cachedTransferFolder = "Cached Transfer"

# Create log file with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFilePath = Join-Path -Path $destinationRoot -ChildPath "Distribution_Log_$timestamp.csv"

# Initialize log array
$logEntries = @()

# Verify source folder exists
if (-not (Test-Path -Path $sourcePath)) {
    Write-Host "ERROR: Source folder not found: $sourcePath" -ForegroundColor Red
    exit 1
}

# Verify Cached Transfer folder exists inside source
$cachedTransferPath = Join-Path -Path $sourcePath -ChildPath $cachedTransferFolder
if (-not (Test-Path -Path $cachedTransferPath)) {
    Write-Host "ERROR: Cached Transfer folder not found inside: $sourcePath" -ForegroundColor Red
    exit 1
}

# Verify destination root exists
if (-not (Test-Path -Path $destinationRoot)) {
    Write-Host "ERROR: Destination root folder not found: $destinationRoot" -ForegroundColor Red
    exit 1
}

# Get all subfolders in the destination root
$allSubfolders = Get-ChildItem -Path $destinationRoot -Directory

# Check if there are any subfolders
if ($allSubfolders.Count -eq 0) {
    Write-Host "WARNING: No subfolders found in $destinationRoot" -ForegroundColor Yellow
    exit 0
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 1: Copy Cached Browsers to All Subfolders" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Counter for tracking progress
$successCount = 0
$errorCount = 0
$skippedCount = 0
$totalCount = $allSubfolders.Count

# Copy the folder to each subfolder
foreach ($subfolder in $allSubfolders) {
    $destinationPath = Join-Path -Path $subfolder.FullName -ChildPath "Cached Browsers"
    
    Write-Host "[$($successCount + $errorCount + 1)/$totalCount] Processing: $($subfolder.Name)" -ForegroundColor White
    
    try {
        # Check if destination already exists
        if (Test-Path -Path $destinationPath) {
            Write-Host "  - Cached Browsers already exists, skipping copy..." -ForegroundColor Yellow
            $skippedCount++
        }
        else {
            # Copy the folder
            Write-Host "  - Copying 'Cached Browsers' to: $destinationPath" -ForegroundColor Gray
            Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
            
            Write-Host "  - SUCCESS: Copy completed" -ForegroundColor Green
            $successCount++
        }
    }
    catch {
        Write-Host "  - ERROR: Failed to copy to $($subfolder.Name)" -ForegroundColor Red
        Write-Host "  - Error details: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    
    Write-Host ""
}

# Phase 1 Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Phase 1 Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total subfolders: $totalCount" -ForegroundColor White
Write-Host "Successful copies: $successCount" -ForegroundColor Green
Write-Host "Skipped (already exists): $skippedCount" -ForegroundColor Yellow
Write-Host "Failed copies: $errorCount" -ForegroundColor Red
Write-Host ""

# Phase 2: Distribute Cached Transfer folders to city folders
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "PHASE 2: Distribute Cached Transfer Folders" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get all folders inside Cached Transfer
$cachedTransferFolders = Get-ChildItem -Path $cachedTransferPath -Directory

if ($cachedTransferFolders.Count -eq 0) {
    Write-Host "WARNING: No folders found inside Cached Transfer" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($cachedTransferFolders.Count) folders inside Cached Transfer" -ForegroundColor Cyan
Write-Host ""

# Filter city folders (folders with state abbreviations - contain comma and space followed by 2 uppercase letters)
$cityFolders = $allSubfolders | Where-Object { $_.Name -match ',\s+[A-Z]{2}$' }

if ($cityFolders.Count -eq 0) {
    Write-Host "WARNING: No city folders with state abbreviations found" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($cityFolders.Count) city folders with state abbreviations" -ForegroundColor Cyan
Write-Host "Logging distribution to: $logFilePath" -ForegroundColor Cyan
Write-Host ""

# Reset counters
$successCount = 0
$errorCount = 0
$totalCount = $cityFolders.Count

# Distribute 5 random folders to each city folder
foreach ($cityFolder in $cityFolders) {
    Write-Host "[$($successCount + $errorCount + 1)/$totalCount] Processing: $($cityFolder.Name)" -ForegroundColor White
    
    # Get the Cached Transfer path in this city folder
    $cityTransferPath = Join-Path -Path $cityFolder.FullName -ChildPath "Cached Browsers\$cachedTransferFolder"
    
    if (-not (Test-Path -Path $cityTransferPath)) {
        Write-Host "  - WARNING: Cached Transfer folder not found in $($cityFolder.Name)" -ForegroundColor Yellow
        
        # Log the error
        $logEntries += [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            CityFolder = $cityFolder.Name
            FolderName = "N/A"
            Status = "ERROR: Cached Transfer not found"
        }
        
        $errorCount++
        Write-Host ""
        continue
    }
    
    try {
        # Get 5 random folders from Cached Transfer
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
            
            # Copy from the city's Cached Transfer folder
            $sourceFolderPath = Join-Path -Path $cityTransferPath -ChildPath $folder.Name
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
Write-Host "Phase 1 - Cached Browsers Copy:" -ForegroundColor White
Write-Host "  Total subfolders: $($allSubfolders.Count)" -ForegroundColor White
Write-Host ""
Write-Host "Phase 2 - Cached Transfer Distribution:" -ForegroundColor White
Write-Host "  Total city folders: $totalCount" -ForegroundColor White
Write-Host "  Successful distributions: $successCount" -ForegroundColor Green
Write-Host "  Failed distributions: $errorCount" -ForegroundColor Red
Write-Host ""
Write-Host "Audit Log: $logFilePath" -ForegroundColor Cyan
Write-Host ""

if ($errorCount -eq 0) {
    Write-Host "All operations completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Some operations failed. Please review the errors above and check the log file." -ForegroundColor Yellow
}
