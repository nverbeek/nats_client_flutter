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

# Function to check if ImageMagick is installed
function Test-ImageMagick {
    try {
        $null = & magick --version 2>$null
        return $true
    }
    catch {
        return $false
    }
}

# Function to process a single image
function Process-Image {
    param(
        [string]$ImageFile
    )
    
    Write-Host "Processing: $ImageFile" -ForegroundColor Green
    
    # Get file info
    $fileInfo = Get-Item $ImageFile
    $baseName = $fileInfo.BaseName
    $extension = $fileInfo.Extension
    
    # Create temporary file names
    $tempCropped = "${baseName}_temp_cropped${extension}"
    $tempRounded = "${baseName}_temp_rounded${extension}"
    
    try {
        # Step 1: Crop 4 pixels from all sides
        Write-Host "  - Cropping 4 pixels from all sides..." -ForegroundColor Yellow
        & magick $ImageFile -shave 4x4 $tempCropped
        
        if (-not (Test-Path $tempCropped)) {
            throw "Failed to create cropped image"
        }
        
        # Step 2: Add rounded corners
        Write-Host "  - Adding rounded corners..." -ForegroundColor Yellow
        # Create a mask file first
        $maskFile = "${baseName}_mask${extension}"
        & magick $tempCropped -alpha extract -fill black -colorize 100% -fill white -draw "roundrectangle 0,0 %[fx:w-1],%[fx:h-1] 8,8" $maskFile
        
        # Apply the mask to create rounded corners
        & magick $tempCropped $maskFile -alpha off -compose CopyOpacity -composite $tempRounded
        
        # Clean up mask file
        Remove-Item $maskFile -Force -ErrorAction SilentlyContinue
        
        if (-not (Test-Path $tempRounded)) {
            throw "Failed to create rounded corner image"
        }
        
        # Step 3: Replace original file
        Write-Host "  - Replacing original file..." -ForegroundColor Yellow
        Copy-Item $tempRounded $ImageFile -Force
        
        # Clean up temporary files
        Remove-Item $tempCropped -Force -ErrorAction SilentlyContinue
        Remove-Item $tempRounded -Force -ErrorAction SilentlyContinue
        Remove-Item $maskFile -Force -ErrorAction SilentlyContinue
        
        Write-Host "  ✅ Successfully processed!" -ForegroundColor Green
        
    }
    catch {
        Write-Error "Failed to process ${ImageFile}: $($_.Exception.Message)"
        
        # Clean up any temporary files
        Remove-Item $tempCropped -Force -ErrorAction SilentlyContinue
        Remove-Item $tempRounded -Force -ErrorAction SilentlyContinue
        Remove-Item $maskFile -Force -ErrorAction SilentlyContinue
        
        return $false
    }
    
    return $true
}

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
    if (Process-Image $file.FullName) {
        $successCount++
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