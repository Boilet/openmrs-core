# Starts the full OpenMRS monitoring stack (OpenMRS + MariaDB + Grafana/Loki/Alloy + Prometheus/exporters).
# Usage:  ./start-stack.ps1 [--build]
param(
    [switch]$Build
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (Test-Path .env) {
    Get-Content .env | Where-Object { $_ -match '^\s*[A-Za-z_][A-Za-z0-9_]*=' } | ForEach-Object {
        $kv = $_ -split '=', 2
        Set-Item -Path "Env:$($kv[0].Trim())" -Value ($kv[1].Trim().Trim('"').Trim("'"))
    }
}

$COMPOSE = 'docker-compose.yml', 'docker-compose.override.yml', 'docker-compose.grafana.yml', 'docker-compose.proxy.yml', 'docker-compose.prometheus.yml'
$ARGS = @()

if ($Build) {
    $ARGS += 'build', '--build-arg', 'MVN_ARGS=install -DskipTests'
    & docker compose -f $COMPOSE[0] -f $COMPOSE[1] build --build-arg 'MVN_ARGS=install -DskipTests'
}
& docker compose -f $COMPOSE[0] -f $COMPOSE[1] -f $COMPOSE[2] -f $COMPOSE[3] -f $COMPOSE[4] up -d

Write-Host "`nStack started:"
Write-Host "  OpenMRS UI     : https://localhost:$($env:OMRS_HTTPS_HOST_PORT ?? '8443')/openmrs  (admin / $($env:OMRS_ADMIN_USER_PASSWORD ?? 'Admin123'))"
Write-Host "                   Certificado de dev firmado por una CA local (monitoring/proxy/ca/dev-ca.crt) - importarla UNA VEZ al almacen de confianza del sistema (ver docs/arquitectura-seguridad.md #5) o el navegador va a advertir."
Write-Host "                   http://localhost:$($env:OMRS_HTTP_HOST_PORT ?? '8083')/openmrs redirige automaticamente a HTTPS."
Write-Host "  Scheduler      : http://localhost:$($env:OMRS_SCHEDULER_HOST_PORT ?? '9003')"
Write-Host "  Grafana        : http://localhost:$($env:GRAFANA_HOST_PORT ?? '3010')  (admin / $($env:GRAFANA_ADMIN_PASSWORD ?? 'Admin123'))"
Write-Host "  Prometheus     : http://localhost:$($env:PROMETHEUS_HOST_PORT ?? '9101')"
Write-Host "  Debug (JDWP)   : port $($env:OMRS_DEBUG_HOST_PORT ?? '8013')"