$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Applies a 1/8-inch black margin guide frame to all existing JPGs in
# Cards/templates/<role>/ without regenerating cards from scratch.
# Run from workspace root:  .\Copilot\cardconjurer_batch\apply_margin_frame.ps1

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..") | Select-Object -ExpandProperty Path

$roles = @("Assassins", "Bandits", "Guardians", "Kings")

Add-Type -AssemblyName System.Drawing

function Save-Jpeg {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [string]$OutPath,
        [int]$Quality
    )

    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1

    if ($null -eq $codec) { throw "JPEG codec not available." }

    $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
        [System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)
    try {
        $Bitmap.Save($OutPath, $codec, $ep)
    }
    finally {
        $ep.Dispose()
    }
}

$total = 0
$done  = 0
$failed = New-Object System.Collections.Generic.List[string]

foreach ($role in $roles) {
    $dir = Join-Path $workspaceRoot "Cards\templates\$role"
    if (-not (Test-Path $dir)) {
        Write-Host "Skipping $role (folder not found)" -ForegroundColor DarkGray
        continue
    }

    $jpgs = Get-ChildItem -LiteralPath $dir -Filter "*.jpg"
    Write-Host "$role : $($jpgs.Count) JPG(s)" -ForegroundColor Cyan

    foreach ($jpg in $jpgs) {
        $total++
        $tempPath = $jpg.FullName + ".tmp"

        try {
            # Load source into memory so the file is not locked
            $bytes = [System.IO.File]::ReadAllBytes($jpg.FullName)
            $ms    = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
            $src   = [System.Drawing.Image]::FromStream($ms)

            $w = $src.Width
            $h = $src.Height
            # Derive margin from card pixel width (MTG card = 2.5 in wide)
            # 1/8 in = width / 20  — correct regardless of DPI metadata
            $marginPx = [int]($w / 20.0)

            $bmp = New-Object System.Drawing.Bitmap($w, $h)
            try {
                $bmp.SetResolution($src.HorizontalResolution, $src.VerticalResolution)

                $g = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $g.CompositingMode    = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                    $g.DrawImage($src, 0, 0, $w, $h)

                    # Fill 1/8-inch solid black margin border
                    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::Black)
                    try {
                        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
                        $g.FillRectangle($brush, 0,            0,            $w,        $marginPx)
                        $g.FillRectangle($brush, 0,            ($h - $marginPx), $w,   $marginPx)
                        $g.FillRectangle($brush, 0,            $marginPx,    $marginPx, ($h - 2 * $marginPx))
                        $g.FillRectangle($brush, ($w - $marginPx), $marginPx, $marginPx, ($h - 2 * $marginPx))
                    }
                    finally {
                        $brush.Dispose()
                    }
                }
                finally {
                    $g.Dispose()
                }

                $src.Dispose()
                $ms.Dispose()

                Save-Jpeg -Bitmap $bmp -OutPath $tempPath -Quality 85
                Move-Item -LiteralPath $tempPath -Destination $jpg.FullName -Force
                $done++
                Write-Host "  OK  $($jpg.Name)  [margin=${marginPx}px, ${w}x${h}]"
            }
            finally {
                $bmp.Dispose()
            }
        }
        catch {
            if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
            $failed.Add($jpg.Name)
            Write-Host "  ERR $($jpg.Name) : $_" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Done: $done / $total processed." -ForegroundColor Green
if ($failed.Count -gt 0) {
    Write-Host "Failed ($($failed.Count)):" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}
