#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Process screenshot images by cropping edges and adding rounded corners
.DESCRIPTION
    This script processes PNG images by:
    1. Cropping 4 pixels from all 4 sides (removes excess capture area)
    2. Adding rounded corners for a modern Windows 11 appearance
    3. Preserving original filenames and image quality
.PARAMETER ImagePath
    Path to the directory containing images to process. Defaults to current directory.
.EXAMPLE
    .\Process-Screenshots.ps1
    Processes all PNG files in the current directory
.EXAMPLE
    .\Process-Screenshots.ps1 -ImagePath "C:\Screenshots"
    Processes all PNG files in the specified directory
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ImagePath = "."
)

. (Join-Path $PSScriptRoot "../scripts/_image_processing.ps1")

# Main script execution
Write-Host "🖼️  Screenshot Processor" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan

# Check if ImageMagick is installed
if (-not (Test-ImageMagick)) {
    Write-Error "ImageMagick is not installed or not in PATH. Please install ImageMagick first."
    Write-Host "Download from: https://imagemagick.org/script/download.php#windows" -ForegroundColor Yellow
    exit 1
}

# Change to the specified directory
if ($ImagePath -ne ".") {
    if (-not (Test-Path $ImagePath)) {
        Write-Error "Directory not found: $ImagePath"
        exit 1
    }
    Set-Location $ImagePath
}

Write-Host "Processing images in: $(Get-Location)" -ForegroundColor Cyan

# Find all PNG files
$pngFiles = Get-ChildItem -Filter "*.png" | Where-Object { -not $_.Name.Contains("_temp_") }

if ($pngFiles.Count -eq 0) {
    Write-Warning "No PNG files found in the current directory."
    exit 0
}

Write-Host "Found $($pngFiles.Count) PNG file(s) to process:" -ForegroundColor Cyan
$pngFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor White }

# Process each image
$successCount = 0
$totalCount = $pngFiles.Count

foreach ($file in $pngFiles) {
    Write-Host "Processing: $($file.FullName)" -ForegroundColor Green
    try {
        Format-Screenshot -ImageFile $file.FullName
        Write-Host "  ✅ Successfully processed!" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Error "Failed to process $($file.FullName): $($_.Exception.Message)"
    }
}

# Summary
Write-Host "`n📊 Processing Summary:" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host "Total files: $totalCount" -ForegroundColor White
Write-Host "Successfully processed: $successCount" -ForegroundColor Green
Write-Host "Failed: $($totalCount - $successCount)" -ForegroundColor Red

if ($successCount -eq $totalCount) {
    Write-Host "`n🎉 All images processed successfully!" -ForegroundColor Green
    Write-Host "Your screenshots now have:" -ForegroundColor Green
    Write-Host "  ✅ 4 pixels cropped from all sides" -ForegroundColor Green
    Write-Host "  ✅ Rounded corners (Windows 11 style)" -ForegroundColor Green
    Write-Host "  ✅ Preserved image quality and transparency" -ForegroundColor Green
} else {
    Write-Warning "Some images failed to process. Check the error messages above."
    exit 1
}
