#Requires -Version 5.1
# PowerShell sibling of setup.sh. Pure Windows-native — no Git Bash / WSL.
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "=== Fibey Agent Setup ==="

# Python setup
Write-Host "Setting up Python environment with uv..."
Push-Location $ProjectRoot
try {
    uv sync
    if ($LASTEXITCODE -ne 0) { throw "uv sync failed" }
} finally {
    Pop-Location
}

# Node setup
Write-Host "Setting up UI dependencies..."
Push-Location (Join-Path $ProjectRoot 'ui')
try {
    npm install
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }
} finally {
    Pop-Location
}

# .env
$envPath = Join-Path $ProjectRoot '.env'
$envExamplePath = Join-Path $ProjectRoot '.env.example'
if (-not (Test-Path $envPath)) {
    Copy-Item $envExamplePath $envPath
    Write-Host "Created .env from .env.example — fill in your values."
}

Write-Host "=== Setup complete ==="
Write-Host "Run ./scripts/start-dev.ps1 to start development servers."
