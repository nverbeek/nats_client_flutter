#Requires -PSEdition Core
# Populates a local JetStream-enabled NATS server with a demo Object Store
# bucket and a handful of realistic-looking objects, so the app's Object
# Store tab has real data to look at. Object Store buckets are backed by
# JetStream, so the same server used for Recipe E (see AGENTS.md "Local
# JetStream Testing") works here too — no separate setup needed.
#
# Unlike kv_demo.ps1/jetstream_demo.ps1, this does NOT use the `nats` CLI to
# upload the objects. `nats object put` leaves the object metadata's `mtime`
# field as Go's zero-value time (`0001-01-01T00:00:00Z`) — confirmed by
# inspecting the raw `$O.<bucket>.M.>` metadata directly against a real
# server — which `dart_nats`'s `ObjectInfo.fromJson` takes literally, making
# the app's relative-time column show something like "739807d ago" instead
# of "just now". Real uploads through the app's own Upload button don't hit
# this, since `dart_nats`'s `ObjectStore.put()` always sets `mtime` itself —
# but demo data seeded via the CLI would produce a visibly broken
# screenshot. `scripts/seed_object_store.dart` seeds through that same
# `dart_nats` `ObjectStore.put()` call instead, sidestepping the mismatch
# entirely.
#
# Must run under PowerShell 7+ (`pwsh`), not Windows PowerShell 5.1 — see
# jetstream_demo.ps1's identical note on why.

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$iconPath = Resolve-Path (Join-Path $PSScriptRoot "../assets/app_launcher_icon.svg")

Write-Host "Seeding Object Store demo bucket 'documents'..."
Push-Location $repoRoot
try {
    dart run --packages=.dart_tool/package_config.json `
        (Join-Path $PSScriptRoot "seed_object_store.dart") `
        127.0.0.1 4222 documents $iconPath.Path
} finally {
    Pop-Location
}
