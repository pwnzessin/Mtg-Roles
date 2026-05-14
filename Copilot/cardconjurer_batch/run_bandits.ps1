$ErrorActionPreference = 'Stop'

Set-Location -Path $PSScriptRoot

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  Write-Error 'Node.js is not installed or not on PATH. Install Node.js 18+ first.'
}

if (-not (Test-Path (Join-Path $PSScriptRoot 'node_modules'))) {
  npm install
  npx playwright install chromium
}

npm run generate -- --role Bandits --headless false --start-launcher true --overwrite false
