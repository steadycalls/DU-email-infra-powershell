# PowerShell Script to Copy "Cached Browsers" Folder to All Subfolders
# This script copies C:\Users\kyle\Desktop\Cached Browsers to all subfolders in E:\Alliance Decks

# Define source and destination paths
$sourcePath = "C:\Users\kyle\Desktop\Cached Browsers"
$destinationRoot = "E:\Alliance Decks"

# Verify source folder exists
if (-not (Test-Path -Path $sourcePath)) {
    Write-Host "ERROR: Source folder not found: $sourcePath" -ForegroundColor Red
    exit 1
}

# Verify destination root exists
if (-not (Test-Path -Path $destinationRoot)) {
    Write-Host "ERROR: Destination root folder not found: $destinationRoot" -ForegroundColor Red
    exit 1
}

# Get all subfolders in the destination root
$subfolders = Get-ChildItem -Path $destinationRoot -Directory

# Check if there are any subfolders
if ($subfolders.Count -eq 0) {
    Write-Host "WARNING: No subfolders found in $destinationRoot" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($subfolders.Count) subfolder(s) in $destinationRoot" -ForegroundColor Cyan
Write-Host "Starting copy operation..." -ForegroundColor Cyan
Write-Host ""

# Counter for tracking progress
$successCount = 0
$errorCount = 0
$totalCount = $subfolders.Count

# Copy the folder to each subfolder
foreach ($subfolder in $subfolders) {
    $destinationPath = Join-Path -Path $subfolder.FullName -ChildPath "Cached Browsers"
    
    Write-Host "[$($successCount + $errorCount + 1)/$totalCount] Processing: $($subfolder.Name)" -ForegroundColor White
    
    try {
        # Check if destination already exists
        if (Test-Path -Path $destinationPath) {
            Write-Host "  - Destination already exists, removing old copy..." -ForegroundColor Yellow
            Remove-Item -Path $destinationPath -Recurse -Force
        }
        
        # Copy the folder
        Write-Host "  - Copying 'Cached Browsers' to: $destinationPath" -ForegroundColor Gray
        Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force
        
        Write-Host "  - SUCCESS: Copy completed" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  - ERROR: Failed to copy to $($subfolder.Name)" -ForegroundColor Red
        Write-Host "  - Error details: $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++
    }
    
    Write-Host ""
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Copy Operation Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total subfolders: $totalCount" -ForegroundColor White
Write-Host "Successful copies: $successCount" -ForegroundColor Green
Write-Host "Failed copies: $errorCount" -ForegroundColor Red
Write-Host ""

if ($errorCount -eq 0) {
    Write-Host "All operations completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Some operations failed. Please review the errors above." -ForegroundColor Yellow
}
