#!/usr/bin/env pwsh
# Shared ImageMagick helpers for turning a raw window screenshot into the
# style used throughout images/*.png: 4px shaved off each edge (trims the
# capture's excess border), rounded corners (Windows 11 windows have them,
# but a flat screenshot loses them), a hairline border, and a soft drop
# shadow (elevation cues a flat screenshot otherwise lacks). Dot-sourced by
# both images/process_screenshots.ps1 (manual, whole-directory reprocessing)
# and scripts/capture_screenshots.ps1 (automated capture pipeline) so the
# two tools can't drift apart on what "processed" means.

function Test-ImageMagick {
    try {
        $null = & magick --version 2>$null
        return $true
    }
    catch {
        return $false
    }
}

# Crops 4px from each edge, rounds the corners, and adds a subtle border +
# soft drop shadow to the PNG at $ImageFile, in place. The border/shadow are
# sized for the ~2.5x-DPI captures this pipeline produces (see
# scripts/capture_screenshots.ps1) so they still read once GitHub scales the
# rendered README down to typical article width; on a 1x capture they'd look
# oversized. Canvas grows to fit the shadow's soft edge, so callers that care
# about output dimensions should re-check them after calling this. Throws on
# failure; caller decides how to handle it.
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
    $tempBordered = Join-Path $directory "${baseName}_temp_bordered${extension}"
    $tempShadowed = Join-Path $directory "${baseName}_temp_shadowed${extension}"
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

        # Hairline border traced along the same rounded-rect geometry as the
        # corner mask, inset by half the stroke width so it stays fully
        # on-canvas.
        & magick $tempRounded -fill none -stroke "rgba(0,0,0,0.35)" -strokewidth 3 -draw "roundrectangle 1.5,1.5 %[fx:w-2.5],%[fx:h-2.5] 8,8" $tempBordered
        if (-not (Test-Path $tempBordered)) {
            throw "Failed to create bordered image for $ImageFile"
        }

        # Shadow is derived from $tempBordered's own alpha channel (via
        # +clone), so it follows the rounded corners rather than the
        # rectangular pre-mask shape. +swap puts the shadow clone behind the
        # original before the merge; +repage grows the canvas to fit the
        # blurred edge instead of clipping it.
        & magick $tempBordered `( +clone -background black -shadow 55x50+0+20 `) +swap -background none -layers merge +repage $tempShadowed
        if (-not (Test-Path $tempShadowed)) {
            throw "Failed to create drop-shadow image for $ImageFile"
        }

        Copy-Item $tempShadowed $ImageFile -Force
    }
    finally {
        Remove-Item $tempCropped -Force -ErrorAction SilentlyContinue
        Remove-Item $tempRounded -Force -ErrorAction SilentlyContinue
        Remove-Item $tempBordered -Force -ErrorAction SilentlyContinue
        Remove-Item $tempShadowed -Force -ErrorAction SilentlyContinue
        Remove-Item $maskFile -Force -ErrorAction SilentlyContinue
    }
}
