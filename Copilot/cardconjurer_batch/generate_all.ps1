$ErrorActionPreference = "Stop"
$batch = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $batch

$roles = @("Assassins", "Bandits", "Guardians", "Kings")

foreach ($role in $roles) {
    Write-Host "`n=== Generating $role ===" -ForegroundColor Cyan
    npm run generate -- --role $role --base-url http://localhost:8080 --start-launcher false --headless true --overwrite true
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED on $role (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "$role done." -ForegroundColor Green
}

Write-Host "`nAll roles generated successfully." -ForegroundColor Green
