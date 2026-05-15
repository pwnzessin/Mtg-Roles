$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$batch = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspaceRoot = (Resolve-Path (Join-Path $batch "..\.."))
Set-Location $batch

# Compression profile (same default as interactive batch script option 4)
$compression = [pscustomobject]@{
    Name = "50% JPEG (Q85)"
    Format = "Jpeg"
    Scale = 0.5
    Width = 0
    Height = 0
    Dpi = 0
    JpegQuality = 85
}

$roles = @("Assassins", "Bandits", "Guardians", "Kings")

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

function Compress-Image {
    param(
        [string]$InputPath,
        [pscustomobject]$Settings
    )

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

                # Draw 1/8-inch black margin guide frame
                $marginPx = [int]($bmp.HorizontalResolution * 0.125)
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, 1)
                try {
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
                    $graphics.DrawRectangle($pen, $marginPx, $marginPx, ($targetWidth - 2 * $marginPx - 1), ($targetHeight - 2 * $marginPx - 1))
                }
                finally {
                    $pen.Dispose()
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

# Windows PowerShell ships with .NET Framework and supports System.Drawing on Windows.
Add-Type -AssemblyName System.Drawing

$totalGenerated = 0
$totalCompressed = 0

foreach ($role in $roles) {
    Write-Host "`n=== Generating $role ===" -ForegroundColor Cyan

    npm run generate -- --role $role --base-url http://localhost:8080 --start-launcher false --headless true --overwrite true
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED on $role (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    $reportPath = Join-Path $workspaceRoot ("Copilot\cardconjurer_batch_{0}_report.txt" -f $role.ToLowerInvariant())
    $generatedPathsRaw = Get-GeneratedPathsFromReport -ReportPath $reportPath
    $generatedPaths = New-Object System.Collections.Generic.List[string]
    foreach ($gp in @($generatedPathsRaw)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$gp)) {
            $generatedPaths.Add([string]$gp)
        }
    }

    $totalGenerated += $generatedPaths.Count

    if ($generatedPaths.Count -eq 0) {
        Write-Host "No generated files found for $role in report: $reportPath" -ForegroundColor Yellow
        continue
    }

    Write-Host "Compressing $($generatedPaths.Count) file(s) for $role with profile '$($compression.Name)'..." -ForegroundColor DarkCyan
    foreach ($p in $generatedPaths) {
        [void](Compress-Image -InputPath $p -Settings $compression)
        $totalCompressed += 1
    }

    Write-Host "$role done." -ForegroundColor Green
}

Write-Host "`nAll roles generated successfully." -ForegroundColor Green
Write-Host "Generated files seen in reports: $totalGenerated"
Write-Host "Compressed files: $totalCompressed"
