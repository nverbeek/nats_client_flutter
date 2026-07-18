#!/usr/bin/env pwsh
#Requires -PSEdition Core

<#
.SYNOPSIS
    Regenerates the README screenshots in images/ from a live run of the app.
.DESCRIPTION
    A real screenshot of a desktop window (title bar and all, matching the
    existing images/*.png) can only be taken from outside the process being
    photographed. So this script and integration_test/screenshot_tour_test.dart
    run as two cooperating processes:

      1. This script starts a disposable JetStream-enabled nats-server,
         seeds it with demo data, and launches
         `flutter test integration_test/screenshot_tour_test.dart -d windows`.
      2. That test drives the real app to each screen the README shows, and
         at each one, writes its name to build/.screenshot_signals/request.txt
         and waits.
      3. This script's watch loop notices the request, finds the "NATS
         Client" window via the Win32 API (PrintWindow), saves + crops +
         rounds it into images/<name>.png, and acks by creating
         build/.screenshot_signals/done_<name>.flag so the test can move on
         to the next screen.

    See integration_test/helpers/screenshot_signal.dart for the Dart side of
    the handshake.
.PARAMETER ContainerName
    Name for the disposable Docker container this script manages. Ignored
    (and no container is started or removed) if something is already
    listening on -Port, since that's assumed to be a server you're managing
    yourself.
.PARAMETER Port
    NATS port to connect to / publish the demo container on. Default 4222.
.PARAMETER MonitorPort
    NATS monitoring port for the demo container. Default 8222.
.PARAMETER KeepContainer
    Don't remove the Docker container this script started, once done.
.PARAMETER KeepRaw
    Don't delete the raw (pre-crop/round) captures under build/.screenshot_raw.
.EXAMPLE
    pwsh ./scripts/capture_screenshots.ps1
#>

param(
    [string]$ContainerName = "nats-screenshot-server",
    [int]$Port = 4222,
    [int]$MonitorPort = 8222,
    [switch]$KeepContainer,
    [switch]$KeepRaw
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$imagesDir = Join-Path $repoRoot "images"
$signalDir = Join-Path $repoRoot "build/.screenshot_signals"
$rawDir = Join-Path $repoRoot "build/.screenshot_raw"
$logFile = Join-Path $repoRoot "build/.screenshot_test.log"

. (Join-Path $PSScriptRoot "_image_processing.ps1")

function Test-CommandExists {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host "Checking prerequisites..." -ForegroundColor Cyan
$missing = @()
if (-not (Test-CommandExists "flutter")) { $missing += "flutter" }
if (-not (Test-CommandExists "dart")) { $missing += "dart (ships with the Flutter SDK)" }
if (-not (Test-CommandExists "docker")) { $missing += "docker" }
if (-not (Test-CommandExists "nats")) { $missing += "nats (natscli)" }
if (-not (Test-ImageMagick)) { $missing += "magick (ImageMagick)" }
if ($missing.Count -gt 0) {
    Write-Error "Missing required tool(s) on PATH: $($missing -join ', ')"
    exit 1
}

# Reset scratch directories.
foreach ($dir in @($signalDir, $rawDir)) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null

function Test-PortOpen {
    param([int]$TestPort)
    $result = Test-NetConnection -ComputerName "127.0.0.1" -Port $TestPort `
        -InformationLevel Quiet -WarningAction SilentlyContinue
    return [bool]$result
}

$managedContainer = $false
if (Test-PortOpen -TestPort $Port) {
    Write-Host "Port $Port is already in use — reusing whatever's running there instead of starting a container." -ForegroundColor Yellow
}
else {
    Write-Host "Starting disposable JetStream-enabled nats-server ('$ContainerName')..." -ForegroundColor Cyan
    docker rm -f $ContainerName *> $null
    docker run -d --name $ContainerName -p "${Port}:4222" -p "${MonitorPort}:8222" nats:latest -js | Out-Null
    $managedContainer = $true

    $deadline = (Get-Date).AddSeconds(20)
    while (-not (Test-PortOpen -TestPort $Port)) {
        if ((Get-Date) -gt $deadline) {
            docker logs $ContainerName
            Write-Error "nats-server didn't come up on port $Port within 20s."
            exit 1
        }
        Start-Sleep -Milliseconds 500
    }
}

function Remove-ManagedContainer {
    if ($managedContainer -and -not $KeepContainer) {
        Write-Host "Removing container '$ContainerName'..." -ForegroundColor Cyan
        docker rm -f $ContainerName *> $null
    }
}

try {
    Write-Host "Seeding JetStream demo streams + messages..." -ForegroundColor Cyan
    pwsh -File (Join-Path $PSScriptRoot "jetstream_demo.ps1") -Iterations 5

    Write-Host "Seeding Key-Value demo bucket..." -ForegroundColor Cyan
    pwsh -File (Join-Path $PSScriptRoot "kv_demo.ps1")

    Write-Host "Seeding Object Store demo bucket..." -ForegroundColor Cyan
    pwsh -File (Join-Path $PSScriptRoot "object_store_demo.ps1")

    # --- Win32 window capture -------------------------------------------------
    Add-Type -AssemblyName System.Drawing
    Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class ScreenshotWin32 {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdcBlt, int nFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT lpRect);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);
    [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr dpiContext);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr lpdwProcessId);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

    # PowerShell hosts are not DPI-aware by default, which makes
    # GetWindowRect return *virtualized* logical coordinates (matching the
    # size we asked the app's window to be, e.g. 1600x1000) while
    # DwmGetWindowAttribute always returns real physical pixels (e.g.
    # 2382x1491 at 150% scaling) — a huge, silent mismatch between the two
    # rects used below to size and crop the capture, which manifests as
    # either a black bar down one edge or an outright "Out of memory" from
    # Bitmap.Clone on a nonsensical crop rectangle. DPI_AWARENESS_CONTEXT_
    # PER_MONITOR_AWARE_V2 (-4) makes both APIs agree on real pixels.
    [void][ScreenshotWin32]::SetProcessDpiAwarenessContext([IntPtr](-4))

    # Deliberately not FindWindow(null, "NATS Client"): in this environment it
    # reliably returns null even for a window EnumWindows can see and
    # GetWindowText confirms is titled exactly "NATS Client" (some
    # RDP/remote-session compatibility shims intercept FindWindow
    # specifically). EnumWindows + GetWindowText is the fallback that's
    # actually been verified to work here.
    function Find-NatsClientWindowHandle {
        # Both the callback's write and this function's read below target
        # $script: scope explicitly — a bare $found would instead create a
        # function-local variable at the callback's own invocation scope
        # (PowerShell scriptblocks used as delegate callbacks don't write
        # back into their enclosing function's locals the way a normal
        # nested scriptblock invoked in-place would), silently leaving the
        # caller's copy stuck at whatever it started as.
        $script:_natsClientWindowHandle = [IntPtr]::Zero
        $callback = {
            param($hWnd, $lParam)
            $len = [ScreenshotWin32]::GetWindowTextLength($hWnd)
            if ($len -gt 0) {
                $sb = New-Object System.Text.StringBuilder ($len + 1)
                [void][ScreenshotWin32]::GetWindowText($hWnd, $sb, $sb.Capacity)
                if ($sb.ToString() -eq "NATS Client") {
                    $script:_natsClientWindowHandle = $hWnd
                    return $false
                }
            }
            return $true
        }
        [void][ScreenshotWin32]::EnumWindows($callback, [IntPtr]::Zero)
        return $script:_natsClientWindowHandle
    }

    # PrintWindow renders whatever DWM activation state the window is
    # actually in — if the NATS Client window isn't the real OS foreground
    # window (e.g. this script's own terminal has focus, which is the
    # common case since nothing else in this pipeline ever activates the
    # app window), the capture bakes in the inactive/unfocused title bar
    # style. Plain SetForegroundWindow from a background process is subject
    # to Windows' foreground-lock heuristic and can silently no-op; the
    # AttachThreadInput dance below is the standard reliable workaround —
    # temporarily joining input queues with the current real foreground
    # window tricks Windows into treating this process as eligible to hand
    # off activation.
    function Set-NatsClientWindowFocus {
        param([Parameter(Mandatory = $true)][IntPtr]$Hwnd)

        $currentForeground = [ScreenshotWin32]::GetForegroundWindow()
        if ($currentForeground -eq $Hwnd) { return }

        $foregroundThreadId = [ScreenshotWin32]::GetWindowThreadProcessId($currentForeground, [IntPtr]::Zero)
        $targetThreadId = [ScreenshotWin32]::GetWindowThreadProcessId($Hwnd, [IntPtr]::Zero)
        $currentThreadId = [ScreenshotWin32]::GetCurrentThreadId()

        [void][ScreenshotWin32]::AttachThreadInput($currentThreadId, $foregroundThreadId, $true)
        [void][ScreenshotWin32]::AttachThreadInput($targetThreadId, $foregroundThreadId, $true)
        try {
            $SW_RESTORE = 9
            [void][ScreenshotWin32]::ShowWindow($Hwnd, $SW_RESTORE)
            [void][ScreenshotWin32]::BringWindowToTop($Hwnd)
            [void][ScreenshotWin32]::SetForegroundWindow($Hwnd)
        }
        finally {
            [void][ScreenshotWin32]::AttachThreadInput($currentThreadId, $foregroundThreadId, $false)
            [void][ScreenshotWin32]::AttachThreadInput($targetThreadId, $foregroundThreadId, $false)
        }

        # Give DWM a moment to repaint the title bar in its active style
        # before PrintWindow captures it.
        Start-Sleep -Milliseconds 200
    }

    function Save-NatsClientWindowScreenshot {
        param([Parameter(Mandatory = $true)][string]$OutFile)

        $hwnd = [IntPtr]::Zero
        $deadline = (Get-Date).AddSeconds(10)
        while ($hwnd -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline) {
            $hwnd = Find-NatsClientWindowHandle
            if ($hwnd -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 300 }
        }
        if ($hwnd -eq [IntPtr]::Zero) {
            throw "Could not find a window titled 'NATS Client' — is the app still running?"
        }

        Set-NatsClientWindowFocus -Hwnd $hwnd

        # PrintWindow paints in the window's own full coordinate space —
        # i.e. relative to GetWindowRect, which on Windows 10/11 includes a
        # few pixels of invisible resize-border padding on the left/right/
        # bottom (but not the top). Sizing the capture bitmap to the
        # tighter DWM "extended frame bounds" instead (the visible-only
        # rect) was a mismatch: PrintWindow still draws as if the canvas
        # started at the full rect's origin, so the real content lands
        # shifted right within a too-small canvas, leaving a black,
        # never-painted strip down the left edge. Fix: capture at the full
        # window rect's size (matching PrintWindow's own coordinate space),
        # then crop to the extended frame bounds using the measured delta
        # between the two rects — precise regardless of how wide that
        # invisible border actually is on a given machine/DPI setting.
        $fullRect = New-Object ScreenshotWin32+RECT
        [void][ScreenshotWin32]::GetWindowRect($hwnd, [ref]$fullRect)
        $fullWidth = $fullRect.Right - $fullRect.Left
        $fullHeight = $fullRect.Bottom - $fullRect.Top

        $visibleRect = New-Object ScreenshotWin32+RECT
        $DWMWA_EXTENDED_FRAME_BOUNDS = 9
        [void][ScreenshotWin32]::DwmGetWindowAttribute($hwnd, $DWMWA_EXTENDED_FRAME_BOUNDS, [ref]$visibleRect,
            [System.Runtime.InteropServices.Marshal]::SizeOf([type]"ScreenshotWin32+RECT"))

        $cropX = $visibleRect.Left - $fullRect.Left
        $cropY = $visibleRect.Top - $fullRect.Top
        $cropWidth = $visibleRect.Right - $visibleRect.Left
        $cropHeight = $visibleRect.Bottom - $visibleRect.Top

        $fullBitmap = New-Object System.Drawing.Bitmap($fullWidth, $fullHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($fullBitmap)
        $hdc = $graphics.GetHdc()
        try {
            # PW_RENDERFULLCONTENT (2): required for hardware-accelerated
            # (ANGLE/Direct3D) surfaces like Flutter's — plain PrintWindow
            # (flag 0) captures a blank frame for these.
            [void][ScreenshotWin32]::PrintWindow($hwnd, $hdc, 2)
        }
        finally {
            $graphics.ReleaseHdc($hdc)
        }

        $croppedBitmap = $fullBitmap.Clone(
            (New-Object System.Drawing.Rectangle($cropX, $cropY, $cropWidth, $cropHeight)),
            $fullBitmap.PixelFormat)
        $croppedBitmap.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)

        $graphics.Dispose()
        $fullBitmap.Dispose()
        $croppedBitmap.Dispose()
    }

    # --- Drive the app + watch for capture/seed requests ----------------------
    Write-Host "Launching flutter test integration_test/screenshot_tour_test.dart -d windows..." -ForegroundColor Cyan
    $flutterProcess = Start-Process -FilePath "flutter" `
        -ArgumentList @("test", "integration_test/screenshot_tour_test.dart", "-d", "windows") `
        -WorkingDirectory $repoRoot `
        -RedirectStandardOutput $logFile `
        -RedirectStandardError "$logFile.err" `
        -NoNewWindow -PassThru

    $requestFile = Join-Path $signalDir "request.txt"
    $seedRequestFile = Join-Path $signalDir "seed_request.flag"
    $seedDoneFile = Join-Path $signalDir "seed_done.flag"
    $capturedNames = @()
    $overallDeadline = (Get-Date).AddMinutes(5)

    while (-not $flutterProcess.HasExited) {
        if ((Get-Date) -gt $overallDeadline) {
            Write-Warning "Timed out waiting for the screenshot tour to finish; killing flutter test."
            Stop-Process -Id $flutterProcess.Id -Force -ErrorAction SilentlyContinue
            break
        }

        if ((Test-Path $seedRequestFile) -and -not (Test-Path $seedDoneFile)) {
            Write-Host "Seeding Live Messages sample payloads..." -ForegroundColor Cyan
            pwsh -File (Join-Path $PSScriptRoot "message_pub.ps1") | Out-Null
            # Padding rows so the list overflows the screenshot window —
            # needed for the Messages capture to show a genuinely
            # scrolled-away state with the Jump-to-top button visible, not
            # just a handful of rows that already fit on screen. Styled as
            # plausible telemetry/system traffic (own subjects, never
            # matched by the 'animal'/'family' filter-and-find demo below)
            # rather than obviously-fake "padding message N" text, so the
            # screenshot still looks like a real message stream.
            $fillerTemplates = @(
                { "{`"sensor`":`"lobby-01`",`"celsius`":$(Get-Random -Minimum 18 -Maximum 24)}" },
                { "{`"sensor`":`"lobby-01`",`"humidity_pct`":$(Get-Random -Minimum 30 -Maximum 55)}" },
                { "{`"service`":`"api-gateway`",`"status`":`"ok`",`"uptime_s`":$(Get-Random -Minimum 1000 -Maximum 99999)}" },
                { "{`"route`":`"/v1/orders`",`"count`":$(Get-Random -Minimum 1 -Maximum 500),`"avg_ms`":$(Get-Random -Minimum 5 -Maximum 120)}" },
                { "{`"key`":`"session:$(Get-Random -Minimum 1000 -Maximum 9999)`",`"reason`":`"ttl_expired`"}" }
            )
            $fillerSubjects = @(
                'telemetry.temperature', 'telemetry.humidity', 'system.heartbeat',
                'metrics.requests', 'system.cache.evict'
            )
            1..15 | ForEach-Object {
                $i = $_ % $fillerTemplates.Count
                nats pub $fillerSubjects[$i] (& $fillerTemplates[$i]) | Out-Null
            }
            New-Item -ItemType File -Path $seedDoneFile -Force | Out-Null
        }

        if (Test-Path $requestFile) {
            $name = (Get-Content $requestFile -Raw).Trim()
            Remove-Item $requestFile -Force
            if ($name) {
                Write-Host "Capturing '$name'..." -ForegroundColor Cyan
                $rawFile = Join-Path $rawDir "$name.png"
                Save-NatsClientWindowScreenshot -OutFile $rawFile
                Format-Screenshot -ImageFile $rawFile
                Copy-Item $rawFile (Join-Path $imagesDir "$name.png") -Force
                $capturedNames += $name
                New-Item -ItemType File -Path (Join-Path $signalDir "done_$name.flag") -Force | Out-Null
            }
        }

        Start-Sleep -Milliseconds 300
    }

    if ($flutterProcess.ExitCode -eq 0) {
        $updatedFiles = $capturedNames | ForEach-Object { "images/$_.png" }
        Write-Host "`nCaptured $($capturedNames.Count) screenshot(s): $($capturedNames -join ', ')" -ForegroundColor Green
        Write-Host "Updated: $($updatedFiles -join ', ')" -ForegroundColor Green
    }
    else {
        Write-Warning "flutter test exited with code $($flutterProcess.ExitCode). Log tail:"
        Get-Content $logFile -Tail 40 -ErrorAction SilentlyContinue
        Get-Content "$logFile.err" -Tail 40 -ErrorAction SilentlyContinue
        exit 1
    }
}
finally {
    Remove-ManagedContainer
    Remove-Item $signalDir -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $KeepRaw) {
        Remove-Item $rawDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
