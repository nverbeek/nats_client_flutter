#Requires -PSEdition Core
# Populates a local JetStream-enabled NATS server with a couple of demo
# streams and a steady trickle of sample messages, so the app's JetStream
# tab has real, growing streams to look at. See AGENTS.md "Recipe E: Local
# JetStream Testing" for full setup steps.
#
# Requires the `nats` CLI (https://github.com/nats-io/natscli) on PATH,
# pointed at a JetStream-enabled server, e.g.:
#   docker run -d --name nats-js -p 4222:4222 -p 8222:8222 nats:latest -js
#
# Must run under PowerShell 7+ (`pwsh`), not Windows PowerShell 5.1
# (`powershell.exe`): Windows PowerShell's Desktop edition prepends a UTF-8
# BOM when piping a string to a native process's stdin, no matter how
# $OutputEncoding is set, which corrupts the JSON payload below from Dart's
# jsonDecode()'s point of view. The #Requires line above makes that failure
# an explicit error instead of silently-corrupted test data.

# Belt-and-suspenders: also force BOM-less UTF-8 explicitly (harmless no-op
# under pwsh, which already defaults to this).
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function New-DemoStream {
    param(
        [string]$Name,
        [string]$Subjects,
        [string]$Storage
    )

    Write-Host "Creating stream '$Name' ($Subjects)..."
    try {
        nats stream add $Name --subjects $Subjects --storage $Storage --retention limits --defaults
    } catch {
        Write-Host "  Skipping '$Name' (it may already exist): $_"
    }
}

New-DemoStream -Name "orders" -Subjects "orders.>" -Storage "file"
New-DemoStream -Name "telemetry" -Subjects "telemetry.>" -Storage "memory"

Write-Host ""
Write-Host "Publishing demo messages every 2 seconds. Press Ctrl+C to stop."
Write-Host ""

$orderId = 1000
$statuses = @("placed", "shipped", "delivered", "cancelled")

while ($true) {
    $orderId++

    $order = @{
        orderId  = $orderId
        customer = "customer-$(Get-Random -Minimum 1 -Maximum 50)"
        total    = [math]::Round((Get-Random -Minimum 5 -Maximum 500) + (Get-Random), 2)
        status   = $statuses[(Get-Random -Minimum 0 -Maximum $statuses.Length)]
    } | ConvertTo-Json -Compress

    $reading = @{
        deviceId     = "sensor-$(Get-Random -Minimum 1 -Maximum 20)"
        temperatureC = [math]::Round((Get-Random -Minimum -10 -Maximum 40) + (Get-Random), 1)
        humidity     = Get-Random -Minimum 10 -Maximum 90
        timestamp    = (Get-Date).ToString("o")
    } | ConvertTo-Json -Compress

    # Piped via stdin (--force-stdin) rather than passed as a command-line
    # argument: some shells/hosts re-parse the argument list on their way to
    # nats.exe and silently strip the embedded double quotes, corrupting the
    # JSON (e.g. `{"a":1}` becomes `{a:1}`). Stdin sidesteps that entirely.
    $order | nats pub "orders.created" --force-stdin --quiet
    $reading | nats pub "telemetry.reading" --force-stdin --quiet

    Start-Sleep -Seconds 2
}
