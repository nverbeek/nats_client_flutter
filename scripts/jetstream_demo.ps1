# Populates a local JetStream-enabled NATS server with a couple of demo
# streams and a steady trickle of sample messages, so the app's JetStream
# tab has real, growing streams to look at. See AGENTS.md "Recipe E: Local
# JetStream Testing" for full setup steps.
#
# Requires the `nats` CLI (https://github.com/nats-io/natscli) on PATH,
# pointed at a JetStream-enabled server, e.g.:
#   docker run -d --name nats-js -p 4222:4222 -p 8222:8222 nats:latest -js

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

    nats pub "orders.created" $order
    nats pub "telemetry.reading" $reading

    Start-Sleep -Seconds 2
}
