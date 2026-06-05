#Requires -Version 5.1
# PowerShell sibling of start-dev.sh. Pure Windows-native — no Git Bash / WSL.
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "=== Starting Fibey Agent (dev mode) ==="

# Start FastAPI gateway
Write-Host "Starting gateway on :8080..."
$gateway = Start-Process -FilePath 'uv' `
    -ArgumentList @('run', 'uvicorn', 'fibey.gateway.api_server:app', '--reload', '--port', '8080') `
    -WorkingDirectory $ProjectRoot `
    -NoNewWindow -PassThru

# Start Vite dev server
Write-Host "Starting UI on :5173..."
$uiDir = Join-Path $ProjectRoot 'ui'
$ui = Start-Process -FilePath 'npm' `
    -ArgumentList @('run', 'dev') `
    -WorkingDirectory $uiDir `
    -NoNewWindow -PassThru

# Cleanup on exit
$cleanup = {
    Write-Host ""
    Write-Host "Stopping servers..."
    foreach ($p in @($gateway, $ui)) {
        if ($p -and -not $p.HasExited) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    Write-Host "Servers stopped."
}

# Register Ctrl+C handler
try {
    [Console]::TreatControlCAsInput = $false
    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $cleanup | Out-Null

    Write-Host "Gateway: http://localhost:8080"
    Write-Host "UI:      http://localhost:5173"
    Write-Host "Press Ctrl+C to stop."

    # Wait for either process to exit, then trigger cleanup
    while (-not $gateway.HasExited -and -not $ui.HasExited) {
        Start-Sleep -Milliseconds 500
    }
} finally {
    & $cleanup
}
