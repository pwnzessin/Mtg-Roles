param(
    [string]$ConfigFile = "",   # path to config JSON; empty = default Rolecard_Batch_Generator.config.json
    [string]$Roles      = "",   # "A" for all, or "Assassins,Bandits" etc.; empty = ask interactively
    [int]   $Limit      = -1,   # cards per role: -1 = ask; 0 = all
    [string]$Quality    = "",   # "1"-"4"; empty = ask
    [switch]$Yes                # accept all config defaults, skip all prompts
)

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

function Read-MarginSelection {
    param(
        [bool]$Default = $false
    )

    while ($true) {
        Write-Host ""
        $defaultLabel = if ($Default) { "Y" } else { "N" }
        $inputRaw = Read-Host "Apply 1/8 inch black margin frame to output images? (Y/N, default $defaultLabel)"
        $trimmed = $inputRaw.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            return $Default
        }
        if ($trimmed -match "^[Nn]$") {
            return $false
        }
        if ($trimmed -match "^[Yy]$") {
            return $true
        }
        Write-Host "Please enter Y or N." -ForegroundColor Red
    }
}

function Read-FinalUpscaleSelection {
    param(
        [bool]$DefaultEnabled = $false,
        [int]$DefaultFactor = 2
    )

    if ($DefaultFactor -ne 2 -and $DefaultFactor -ne 4) {
        $DefaultFactor = 2
    }

    while ($true) {
        Write-Host ""
        $enabledDefaultLabel = if ($DefaultEnabled) { "Y" } else { "N" }
        $enabledRaw = Read-Host "Upscale final rendered output after margin/frame? (Y/N, default $enabledDefaultLabel)"
        $enabledTrim = $enabledRaw.Trim()
        if ([string]::IsNullOrWhiteSpace($enabledTrim)) {
            if (-not $DefaultEnabled) {
                return [pscustomobject]@{ Enabled = $false; Factor = 1 }
            }
            return [pscustomobject]@{ Enabled = $true; Factor = $DefaultFactor }
        }
        if ($enabledTrim -match "^[Nn]$") {
            return [pscustomobject]@{ Enabled = $false; Factor = 1 }
        }
        if ($enabledTrim -match "^[Yy]$") {
            while ($true) {
                $factorRaw = Read-Host "Upscale factor (2 or 4, default $DefaultFactor)"
                if ([string]::IsNullOrWhiteSpace($factorRaw)) {
                    return [pscustomobject]@{ Enabled = $true; Factor = $DefaultFactor }
                }
                $factor = 0
                if ([int]::TryParse($factorRaw.Trim(), [ref]$factor) -and ($factor -eq 2 -or $factor -eq 4)) {
                    return [pscustomobject]@{ Enabled = $true; Factor = $factor }
                }
                Write-Host "Please enter 2 or 4." -ForegroundColor Red
            }
        }
        Write-Host "Please enter Y or N." -ForegroundColor Red
    }
}

function Convert-ImageQuality {
    param(
        [string]$InputPath,
        [pscustomobject]$Settings,
        [switch]$ApplyMargin,
        [int]$FinalUpscaleFactor = 1
    )

    if (-not $ApplyMargin -and $Settings.Format -eq "Png" -and $Settings.Scale -eq 1.0 -and $Settings.Width -eq 0 -and $Settings.Height -eq 0) {
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

        # When adding a bleed border the canvas is extended, not drawn over.
        $bx = 0; $by = 0
        if ($ApplyMargin) {
            $bx = [int]($targetWidth * 0.044)
            $by = [int]($targetHeight / 35.0)
        }
        $bmpWidth  = $targetWidth  + 2 * $bx
        $bmpHeight = $targetHeight + 2 * $by

        # Step 1: scale source to card dimensions with high-quality rendering.
        $scaledBmp = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
        try {
            if ($Settings.Dpi -gt 0) {
                $scaledBmp.SetResolution($Settings.Dpi, $Settings.Dpi)
            }
            else {
                $scaledBmp.SetResolution($sourceImage.HorizontalResolution, $sourceImage.VerticalResolution)
            }
            $sg = [System.Drawing.Graphics]::FromImage($scaledBmp)
            try {
                $sg.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                $sg.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                $sg.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $sg.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $sg.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $sg.DrawImage($sourceImage, 0, 0, $targetWidth, $targetHeight)
            }
            finally {
                $sg.Dispose()
            }

            # Step 2: place scaled card onto the (possibly extended) black canvas.
            # DrawImageUnscaled places pixels 1:1 at exact coordinates — no DPI adjustment.
            $bmp = New-Object System.Drawing.Bitmap($bmpWidth, $bmpHeight)
            try {
                $bmp.SetResolution($scaledBmp.HorizontalResolution, $scaledBmp.VerticalResolution)
                $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $graphics.Clear([System.Drawing.Color]::Black)
                    $graphics.DrawImageUnscaled($scaledBmp, $bx, $by)
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

                $outputBmp = $bmp
                $upscaledBmp = $null
                if ($FinalUpscaleFactor -gt 1) {
                    $upW = [Math]::Max(1, [int][Math]::Round($bmp.Width * $FinalUpscaleFactor))
                    $upH = [Math]::Max(1, [int][Math]::Round($bmp.Height * $FinalUpscaleFactor))
                    $upscaledBmp = New-Object System.Drawing.Bitmap($upW, $upH)
                    $upscaledBmp.SetResolution($bmp.HorizontalResolution, $bmp.VerticalResolution)
                    $ug = [System.Drawing.Graphics]::FromImage($upscaledBmp)
                    try {
                        $ug.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                        $ug.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                        $ug.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                        $ug.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                        $ug.DrawImage($bmp, 0, 0, $upW, $upH)
                    }
                    finally {
                        $ug.Dispose()
                    }
                    $outputBmp = $upscaledBmp
                }

                try {
                    if ($Settings.Format -eq "Jpeg") {
                        Save-Jpeg -Bitmap $outputBmp -OutPath $tempOut -Quality $Settings.JpegQuality
                    }
                    else {
                        $outputBmp.Save($tempOut, [System.Drawing.Imaging.ImageFormat]::Png)
                    }
                }
                finally {
                    if ($upscaledBmp) {
                        $upscaledBmp.Dispose()
                    }
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
            $scaledBmp.Dispose()
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

$configPath = if (-not [string]::IsNullOrWhiteSpace($ConfigFile) -and (Test-Path $ConfigFile)) { $ConfigFile } else { Join-Path $batchDir "Rolecard_Batch_Generator.config.json" }
$savedConfig = $null
if (Test-Path $configPath) {
    try {
        $savedConfig = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Host "Could not parse existing config at $configPath; using prompt defaults." -ForegroundColor Yellow
        $savedConfig = $null
    }
}

$defaultApplyMargin = $false
$defaultFinalUpscaleEnabled = $false
$defaultFinalUpscaleFactor = 2
$defaultLimit = 0
if ($savedConfig) {
    if ($savedConfig.PSObject.Properties.Match('limit').Count -gt 0 -and $null -ne $savedConfig.limit) {
        $dl = [int]$savedConfig.limit
        if ($dl -ge 0) { $defaultLimit = $dl }
    }
    if ($savedConfig.PSObject.Properties.Match('applyMargin').Count -gt 0 -and $null -ne $savedConfig.applyMargin) {
        $defaultApplyMargin = [bool]$savedConfig.applyMargin
    }
    if ($savedConfig.PSObject.Properties.Match('finalUpscaleEnabled').Count -gt 0 -and $null -ne $savedConfig.finalUpscaleEnabled) {
        $defaultFinalUpscaleEnabled = [bool]$savedConfig.finalUpscaleEnabled
    }
    if ($savedConfig.PSObject.Properties.Match('finalUpscaleFactor').Count -gt 0 -and $null -ne $savedConfig.finalUpscaleFactor) {
        $f = [int]$savedConfig.finalUpscaleFactor
        if ($f -eq 2 -or $f -eq 4) { $defaultFinalUpscaleFactor = $f }
    }
}

Ensure-NodeAndDeps -BatchDir $batchDir

# Role selection
if ($Yes -or -not [string]::IsNullOrWhiteSpace($Roles)) {
    $rolesInput = if ([string]::IsNullOrWhiteSpace($Roles)) { 'A' } else { $Roles.Trim() }
    if ($rolesInput -match '^[Aa]$') {
        [string[]]$roles = @('Assassins', 'Bandits', 'Guardians', 'Kings')
    } else {
        $roleNameMap = @{ '1'='Assassins'; '2'='Bandits'; '3'='Guardians'; '4'='Kings';
                          'Assassins'='Assassins'; 'Bandits'='Bandits'; 'Guardians'='Guardians'; 'Kings'='Kings' }
        [string[]]$roles = @($rolesInput -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object {
            if ($roleNameMap.ContainsKey($_)) { $roleNameMap[$_] } else { $_ }
        } | Where-Object { $_ -ne '' } | Select-Object -Unique)
    }
    Write-Host "  Roles: $($roles -join ', ') (auto)" -ForegroundColor DarkGray
} else {
    [string[]]$roles = @(Read-RoleSelection)
}

# Card count
if ($Yes -or $Limit -ge 0) {
    $limit = if ($Limit -ge 0) { $Limit } else { $defaultLimit }
    Write-Host "  Cards per role: $(if ($limit -eq 0) { 'All' } else { $limit }) (auto)" -ForegroundColor DarkGray
} else {
    $limit = Read-CountSelection
}

# Quality
if ($Yes -or -not [string]::IsNullOrWhiteSpace($Quality)) {
    $qualityChoice = if (-not [string]::IsNullOrWhiteSpace($Quality)) { $Quality.Trim() } else { '4' }
    Write-Host "  Quality: $qualityChoice (auto)" -ForegroundColor DarkGray
} else {
    $qualityChoice = Read-QualitySelection
}
$qualitySettings = Get-QualitySettings -QualityChoice $qualityChoice

# Margin
if ($Yes) {
    $applyMargin = $defaultApplyMargin
    Write-Host "  Apply margin: $applyMargin (auto)" -ForegroundColor DarkGray
} else {
    $applyMargin = Read-MarginSelection -Default $defaultApplyMargin
}

# Final upscale
if ($Yes) {
    $finalUpscale = [pscustomobject]@{ Enabled = $defaultFinalUpscaleEnabled; Factor = $defaultFinalUpscaleFactor }
    Write-Host "  Final upscale: $(if ($finalUpscale.Enabled) { "Yes (x$($finalUpscale.Factor))" } else { 'No' }) (auto)" -ForegroundColor DarkGray
} else {
    $finalUpscale = Read-FinalUpscaleSelection -DefaultEnabled $defaultFinalUpscaleEnabled -DefaultFactor $defaultFinalUpscaleFactor
}

Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Roles: $($roles -join ', ')"
Write-Host "  Cards per role: $(if ($limit -eq 0) { 'All' } else { $limit })"
Write-Host "  Quality: $($qualitySettings.Name)"
Write-Host "  Margin frame: $(if ($applyMargin) { 'Yes (1/8 inch)' } else { 'No' })"
Write-Host "  Final upscale: $(if ($finalUpscale.Enabled) { "Yes (x$($finalUpscale.Factor))" } else { 'No' })"

if (-not $Yes) {
    $confirm = Read-Host "Proceed? (Y/N, default Y)"
    if (-not [string]::IsNullOrWhiteSpace($confirm) -and $confirm -notmatch "^[Yy]$") {
        Write-Host "Canceled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "  Proceeding (auto)." -ForegroundColor DarkGray
}

# Export current settings to JSON config
$configObj = [ordered]@{
    roles        = $roles
    limit        = $limit
    qualityChoice = $qualityChoice
    applyMargin = [bool]$applyMargin
    finalUpscaleEnabled = [bool]$finalUpscale.Enabled
    finalUpscaleFactor = [int]$finalUpscale.Factor
}
$configObj | ConvertTo-Json | Set-Content -Path $configPath -Encoding utf8
Write-Host "Settings saved to: $configPath" -ForegroundColor DarkGray

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
        [void](Convert-ImageQuality -InputPath $p -Settings $qualitySettings -ApplyMargin:$applyMargin -FinalUpscaleFactor $finalUpscale.Factor)
        $globalConverted += 1
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Generated files seen in reports: $globalGenerated"
Write-Host "Post-processed files: $globalConverted"
