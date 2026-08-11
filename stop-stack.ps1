# Stops the OpenMRS monitoring stack (keeps volumes/data).
# Usage:  ./stop-stack.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (Test-Path .env) {
    Get-Content .env | Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*=' } | ForEach-Object {
        $kv = $_ -split '=', 2
        Set-Item -Path "Env:$($kv[0].Trim())" -Value ($kv[1].Trim().Trim('"').Trim("'"))
    }
}

& docker compose -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.grafana.yml -f docker-compose.proxy.yml -f docker-compose.prometheus.yml stop
Write-Host "Stack stopped. Data is kept in the named volumes (db-data, openmrs-data, loki-data, grafana-data, prometheus-data)."