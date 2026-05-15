$ErrorActionPreference = "Stop"

Set-StrictMode -Version Latest

function Ensure-NodeAndDeps {
    param(
        [string]$BatchDir
    )

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw "Node.js is not installed or not on PATH. Install Node.js 18+ first."
    }

    if (-not (Test-Path (Join-Path $BatchDir "node_modules"))) {
        Write-Host "Installing npm dependencies..." -ForegroundColor Yellow
        npm install
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed with exit code $LASTEXITCODE"
        }

        Write-Host "Installing Playwright Chromium..." -ForegroundColor Yellow
        npx playwright install chromium
        if ($LASTEXITCODE -ne 0) {
            throw "Playwright install failed with exit code $LASTEXITCODE"
        }
    }
}

function Read-RoleSelection {
    $roleMap = [ordered]@{
        "1" = "Assassins"
        "2" = "Bandits"
        "3" = "Guardians"
        "4" = "Kings"
    }

    while ($true) {
        Write-Host ""
        Write-Host "Select role(s):" -ForegroundColor Cyan
        Write-Host "  1. Assassins"
        Write-Host "  2. Bandits"
        Write-Host "  3. Guardians"
        Write-Host "  4. Kings"
        $inputRaw = Read-Host "Enter comma-separated numbers or A for all"

        if ([string]::IsNullOrWhiteSpace($inputRaw)) {
            continue
        }

        $trimmed = $inputRaw.Trim()
        if ($trimmed -match "^[Aa]$") {
            return @("Assassins", "Bandits", "Guardians", "Kings")
        }

        $parts = @($trimmed.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        if ($parts.Count -eq 0) {
            continue
        }

        $selected = New-Object System.Collections.Generic.List[string]
        $isValid = $true
        foreach ($p in $parts) {
            if (-not $roleMap.Contains($p)) {
                $isValid = $false
                break
            }
            $roleName = [string]$roleMap[$p]
            if (-not $selected.Contains($roleName)) {
                $selected.Add($roleName)
            }
        }

        if ($isValid -and $selected.Count -gt 0) {
            return $selected.ToArray()
        }

        Write-Host "Invalid role selection. Try again." -ForegroundColor Red
    }
}

function Read-CountSelection {
    while ($true) {
        Write-Host ""
        $inputRaw = Read-Host "How many cards per role? Enter number or A for all"
        if ([string]::IsNullOrWhiteSpace($inputRaw)) {
            continue
        }

        $trimmed = $inputRaw.Trim()
        if ($trimmed -match "^[Aa]$") {
            return 0
        }

        $n = 0
        if ([int]::TryParse($trimmed, [ref]$n) -and $n -gt 0) {
            return $n
        }

        Write-Host "Invalid count. Enter a positive integer or A." -ForegroundColor Red
    }
}

function Read-QualitySelection {
    while ($true) {
        Write-Host ""
        Write-Host "Output quality:" -ForegroundColor Cyan
        Write-Host "  1 - Original full resolution PNG (2010x2814)"
        Write-Host "  2 - 50% PNG (1005x1407)"
        Write-Host "  3 - 37% PNG (750x1050, 300 DPI)"
        Write-Host "  4 - 50% JPEG quality 85 (1005x1407) [default]"
        $inputRaw = Read-Host "Choose 1-4 (default 4)"

        if ([string]::IsNullOrWhiteSpace($inputRaw)) {
            return "4"
        }

        $trimmed = $inputRaw.Trim()
        if ($trimmed -match "^[1-4]$") {
            return $trimmed
        }

        Write-Host "Invalid quality choice. Pick 1, 2, 3, or 4." -ForegroundColor Red
    }
}

function Get-QualitySettings {
    param(
        [string]$QualityChoice
    )

    switch ($QualityChoice) {
        "1" {
            return [pscustomobject]@{
                Name = "Original PNG"
                Format = "Png"
                Scale = 1.0
                Width = 0
                Height = 0
                Dpi = 0
                JpegQuality = 0
            }
        }
        "2" {
            return [pscustomobject]@{
                Name = "50% PNG"
                Format = "Png"
                Scale = 0.5
                Width = 0
                Height = 0
                Dpi = 0
                JpegQuality = 0
            }
        }
        "3" {
            return [pscustomobject]@{
                Name = "37% PNG (750x1050 @300DPI)"
                Format = "Png"
                Scale = 0
                Width = 750
                Height = 1050
                Dpi = 300
                JpegQuality = 0
            }
        }
        default {
            return [pscustomobject]@{
                Name = "50% JPEG (Q85)"
                Format = "Jpeg"
                Scale = 0.5
                Width = 0
                Height = 0
                Dpi = 0
                JpegQuality = 85
            }
        }
    }
}

function Get-GeneratedPathsFromReport {
    param(
        [string]$ReportPath
    )

    if (-not (Test-Path $ReportPath)) {
        return @()
    }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -Path $ReportPath) {
        if (-not $line.StartsWith("OK | ")) {
            continue
        }

        $parts = $line -split "\|"
        if ($parts.Length -lt 3) {
            continue
        }

        $outputPath = $parts[2].Trim()
        if (-not [string]::IsNullOrWhiteSpace($outputPath) -and (Test-Path $outputPath)) {
            $paths.Add($outputPath)
        }
    }

    return $paths.ToArray()
}

function Save-Jpeg {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$OutPath,
        [int]$Quality
    )

    $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1

    if ($null -eq $jpegCodec) {
        throw "JPEG codec not available on this system."
    }

    $encoder = [System.Drawing.Imaging.Encoder]::Quality
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($encoder, [long]$Quality)

    try {
        $Bitmap.Save($OutPath, $jpegCodec, $encoderParams)
    }
    finally {
        $encoderParams.Dispose()
    }
}

function Convert-ImageQuality {
    param(
        [string]$InputPath,
        [pscustomobject]$Settings
    )

    if ($Settings.Format -eq "Png" -and $Settings.Scale -eq 1.0 -and $Settings.Width -eq 0 -and $Settings.Height -eq 0) {
        return $InputPath
    }

    $sourceBytes = [System.IO.File]::ReadAllBytes($InputPath)
    $sourceStream = New-Object System.IO.MemoryStream(, $sourceBytes)
    $sourceImage = [System.Drawing.Image]::FromStream($sourceStream)
    try {
        if ($Settings.Width -gt 0 -and $Settings.Height -gt 0) {
            $targetWidth = $Settings.Width
            $targetHeight = $Settings.Height
        }
        elseif ($Settings.Scale -gt 0) {
            $targetWidth = [Math]::Max(1, [int][Math]::Round($sourceImage.Width * $Settings.Scale))
            $targetHeight = [Math]::Max(1, [int][Math]::Round($sourceImage.Height * $Settings.Scale))
        }
        else {
            $targetWidth = $sourceImage.Width
            $targetHeight = $sourceImage.Height
        }

        $bmp = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
        try {
            if ($Settings.Dpi -gt 0) {
                $bmp.SetResolution($Settings.Dpi, $Settings.Dpi)
            }
            else {
                $bmp.SetResolution($sourceImage.HorizontalResolution, $sourceImage.VerticalResolution)
            }

            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $graphics.DrawImage($sourceImage, 0, 0, $targetWidth, $targetHeight)

                # Fill 1/8-inch solid black margin border
                # Use pixel width / 20 (= 1/8 of 2.5-inch card width) — DPI metadata is unreliable
                $marginPx = [int]($targetWidth / 20.0)
                $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
                try {
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
                    $graphics.FillRectangle($brush, 0,                          0,                           $targetWidth,  $marginPx)
                    $graphics.FillRectangle($brush, 0,                          ($targetHeight - $marginPx), $targetWidth,  $marginPx)
                    $graphics.FillRectangle($brush, 0,                          $marginPx,                   $marginPx,     ($targetHeight - 2 * $marginPx))
                    $graphics.FillRectangle($brush, ($targetWidth - $marginPx), $marginPx,                   $marginPx,     ($targetHeight - 2 * $marginPx))
                }
                finally {
                    $brush.Dispose()
                }
            }
            finally {
                $graphics.Dispose()
            }

            $dir = Split-Path -Parent $InputPath
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
            if ($Settings.Format -eq "Jpeg") {
                $outPath = Join-Path $dir ($baseName + ".jpg")
            }
            else {
                $outPath = Join-Path $dir ($baseName + ".png")
            }

            $tempOut = "$outPath.tmp"
            if (Test-Path $tempOut) {
                Remove-Item -LiteralPath $tempOut -Force
            }

            if ($Settings.Format -eq "Jpeg") {
                Save-Jpeg -Bitmap $bmp -OutPath $tempOut -Quality $Settings.JpegQuality
            }
            else {
                $bmp.Save($tempOut, [System.Drawing.Imaging.ImageFormat]::Png)
            }

            Move-Item -LiteralPath $tempOut -Destination $outPath -Force

            if ($Settings.Format -eq "Jpeg" -and ($InputPath -ne $outPath) -and (Test-Path $InputPath)) {
                Remove-Item -LiteralPath $InputPath -Force
            }

            return $outPath
        }
        finally {
            $bmp.Dispose()
        }
    }
    finally {
        $sourceImage.Dispose()
        $sourceStream.Dispose()
    }
}

function Invoke-RoleGeneration {
    param(
        [string]$BatchDir,
        [string]$Role,
        [int]$Limit,
        [bool]$StartLauncher,
        [string]$BaseUrl
    )

    $npmArgs = @("run", "generate", "--", "--role", $Role, "--base-url", $BaseUrl, "--start-launcher", ($StartLauncher.ToString().ToLowerInvariant()), "--headless", "true", "--overwrite", "true")
    if ($Limit -gt 0) {
        $npmArgs += @("--limit", "$Limit")
    }

    Write-Host "Running: npm $($npmArgs -join ' ')" -ForegroundColor DarkGray
    & npm @npmArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Generation failed for $Role (exit code $LASTEXITCODE)."
    }
}

# Windows PowerShell ships with .NET Framework and supports System.Drawing on Windows.
Add-Type -AssemblyName System.Drawing

$batchDir = $PSScriptRoot
$workspaceRoot = (Resolve-Path (Join-Path $batchDir "..\.."))
Set-Location -Path $batchDir

Ensure-NodeAndDeps -BatchDir $batchDir

$roles = @(Read-RoleSelection)
$limit = Read-CountSelection
$qualityChoice = Read-QualitySelection
$qualitySettings = Get-QualitySettings -QualityChoice $qualityChoice

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Roles: $($roles -join ', ')"
Write-Host "  Cards per role: $(if ($limit -eq 0) { 'All' } else { $limit })"
Write-Host "  Quality: $($qualitySettings.Name)"

$confirm = Read-Host "Proceed? (Y/N)"
if ($confirm -notmatch "^[Yy]$") {
    Write-Host "Canceled." -ForegroundColor Yellow
    exit 0
}

$activeBaseUrl = "http://localhost:8080"
$globalGenerated = 0
$globalConverted = 0

for ($i = 0; $i -lt $roles.Count; $i += 1) {
    $role = $roles[$i]
    $startLauncher = ($i -eq 0)

    Write-Host ""
    Write-Host "=== Generating $role ===" -ForegroundColor Green

    $generatedThisRole = $false
    $attemptErrors = New-Object System.Collections.Generic.List[string]

    $attempts = @(
        [pscustomobject]@{ BaseUrl = $activeBaseUrl; StartLauncher = $startLauncher },
        [pscustomobject]@{ BaseUrl = "http://localhost:4242"; StartLauncher = $false }
    )

    foreach ($attempt in $attempts) {
        # Skip duplicate attempt values.
        if ($attemptErrors.Count -gt 0 -and $attempt.BaseUrl -eq $attempts[0].BaseUrl -and $attempt.StartLauncher -eq $attempts[0].StartLauncher) {
            continue
        }

        try {
            Write-Host "Attempting generation via $($attempt.BaseUrl) (start-launcher=$($attempt.StartLauncher.ToString().ToLowerInvariant()))..." -ForegroundColor DarkCyan
            Invoke-RoleGeneration -BatchDir $batchDir -Role $role -Limit $limit -StartLauncher:$attempt.StartLauncher -BaseUrl $attempt.BaseUrl
            $activeBaseUrl = $attempt.BaseUrl
            $generatedThisRole = $true
            break
        }
        catch {
            $attemptErrors.Add($_.Exception.Message)
            Write-Host "Attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if (-not $generatedThisRole) {
        Write-Host "" 
        Write-Host "Card generation failed for role '$role' after trying launcher mode (8080) and fallback server mode (4242)." -ForegroundColor Red
        Write-Host "Make sure one of these is running, then retry:" -ForegroundColor Red
        Write-Host "  1) CardConjurer launcher (http://localhost:8080)" -ForegroundColor Red
        Write-Host "  2) Docker/local server (http://localhost:4242)" -ForegroundColor Red
        throw ($attemptErrors -join " | ")
    }

    $reportPath = Join-Path $workspaceRoot ("Copilot\cardconjurer_batch_{0}_report.txt" -f $role.ToLowerInvariant())
    $generatedPathsRaw = Get-GeneratedPathsFromReport -ReportPath $reportPath
    $generatedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($gp in @($generatedPathsRaw)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$gp)) {
            $generatedPaths.Add([string]$gp)
        }
    }
    $globalGenerated += $generatedPaths.Count

    if ($generatedPaths.Count -eq 0) {
        Write-Host "No generated files detected for $role from report: $reportPath" -ForegroundColor Yellow
        continue
    }

    Write-Host "Post-processing $($generatedPaths.Count) file(s) for quality '$($qualitySettings.Name)'..." -ForegroundColor Cyan
    foreach ($p in $generatedPaths) {
        [void](Convert-ImageQuality -InputPath $p -Settings $qualitySettings)
        $globalConverted += 1
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Generated files seen in reports: $globalGenerated"
Write-Host "Post-processed files: $globalConverted"
