#!/usr/bin/env pwsh
# Shared ImageMagick helpers for turning a raw window screenshot into the
# style used throughout images/*.png: 4px shaved off each edge (trims the
# capture's excess border) plus rounded corners (Windows 11 windows have
# them, but a flat screenshot loses them). Dot-sourced by both
# images/process_screenshots.ps1 (manual, whole-directory reprocessing) and
# scripts/capture_screenshots.ps1 (automated capture pipeline) so the two
# tools can't drift apart on what "processed" means.

function Test-ImageMagick {
    try {
        $null = & magick --version 2>$null
        return $true
    }
    catch {
        return $false
    }
}

# Crops 4px from each edge and rounds the corners of the PNG at $ImageFile,
# in place. Throws on failure; caller decides how to handle it.
function Format-Screenshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImageFile
    )

    $fileInfo = Get-Item $ImageFile
    $baseName = $fileInfo.BaseName
    $extension = $fileInfo.Extension
    $directory = $fileInfo.DirectoryName

    $tempCropped = Join-Path $directory "${baseName}_temp_cropped${extension}"
    $tempRounded = Join-Path $directory "${baseName}_temp_rounded${extension}"
    $maskFile = Join-Path $directory "${baseName}_mask${extension}"

    try {
        & magick $ImageFile -shave 4x4 $tempCropped
        if (-not (Test-Path $tempCropped)) {
            throw "Failed to create cropped image for $ImageFile"
        }

        & magick $tempCropped -alpha extract -fill black -colorize 100% -fill white -draw "roundrectangle 0,0 %[fx:w-1],%[fx:h-1] 8,8" $maskFile
        & magick $tempCropped $maskFile -alpha off -compose CopyOpacity -composite $tempRounded
        if (-not (Test-Path $tempRounded)) {
            throw "Failed to create rounded corner image for $ImageFile"
        }

        Copy-Item $tempRounded $ImageFile -Force
    }
    finally {
        Remove-Item $tempCropped -Force -ErrorAction SilentlyContinue
        Remove-Item $tempRounded -Force -ErrorAction SilentlyContinue
        Remove-Item $maskFile -Force -ErrorAction SilentlyContinue
    }
}
