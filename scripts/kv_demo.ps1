#Requires -PSEdition Core
# Populates a local JetStream-enabled NATS server with a demo Key-Value
# bucket and a handful of realistic-looking keys, so the app's Key-Value
# Stores tab has real data to look at. KV buckets are backed by JetStream,
# so the same server used for Recipe E (see AGENTS.md "Local JetStream
# Testing") works here too — no separate setup needed.
#
# Requires the `nats` CLI (https://github.com/nats-io/natscli) on PATH,
# pointed at a JetStream-enabled server, e.g.:
#   docker run -d --name nats-js -p 4222:4222 -p 8222:8222 nats:latest -js
#
# Must run under PowerShell 7+ (`pwsh`), not Windows PowerShell 5.1 — see
# jetstream_demo.ps1's identical note on why (BOM corruption of values piped
# to a native process's stdin).

$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$bucket = "app-config"

Write-Host "Creating KV bucket '$bucket'..."
try {
    nats kv add $bucket --history 5
} catch {
    Write-Host "  Skipping '$bucket' (it may already exist): $_"
}

# An ordered hashtable so the resulting screenshot's key order is
# deterministic run to run.
$entries = [ordered]@{
    "db.host"             = "db.internal.example.com"
    "db.port"             = "5432"
    "api.rate_limit"      = "1000"
    "feature.dark_mode"   = "true"
    "feature.beta_search" = "false"
    "maintenance.mode"    = "false"
}

Write-Host "Putting demo keys into '$bucket'..."
foreach ($key in $entries.Keys) {
    nats kv put $bucket $key $entries[$key] | Out-Null
}
