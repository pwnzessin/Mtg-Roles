<#
.SYNOPSIS
    Interactive pipeline: Scryfall fetch → CardConjurer card render.

.DESCRIPTION
    Walks you through fetching card data + artwork from Scryfall and/or
    rendering .txt card files into PNGs via CardConjurer.

    Defaults are loaded from generic_card_config.json in the same folder.
    Edit that file to change your personal defaults.

.PARAMETER ConfigFile
    Path to the JSON config file. Defaults to generic_card_config.json
    in the same directory as this script.
#>
param(
    [string]$ConfigFile   = "$PSScriptRoot\generic_card_config.json",
    [int]   $RunMode      = 0,       # 1-5; 0 = ask interactively
    [string]$CardListFile = "",     # path to .txt card list (mode 2)
    [switch]$Yes                     # accept all config defaults, no prompts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Config loading ─────────────────────────────────────────────────────────────

function Read-Config {
    param([string]$Path)
    if (Test-Path $Path) {
        $raw = Get-Content $Path -Raw | ConvertFrom-Json
        return $raw
    }
    Write-Host "  [warn] Config not found at '$Path' - using built-in defaults." -ForegroundColor Yellow
    $fallbackRoot = $null
    try { $fallbackRoot = (Resolve-Path "$PSScriptRoot\..\.." -ErrorAction Stop).Path } catch { $fallbackRoot = $PSScriptRoot }
    return [pscustomobject]@{
        workspaceRoot = $fallbackRoot
        fetch    = [pscustomobject]@{ cardsDir="Cards\Generic"; preferSet=""; overwrite=$false; downloadArt=$true; artMode=2; artVersion="art_crop"; pngCropJpegQuality=95 }
        generate = [pscustomobject]@{ outputSubDir="output"; baseUrl="http://localhost:8080"; headless=$true; startLauncher=$true; overwrite=$false; limit=0 }
    }
}

# ── Prompt helpers ─────────────────────────────────────────────────────────────

function Ask-String {
    param([string]$Label, [string]$Default)
    if ($Yes) { Write-Host "  $Label [$Default] (auto)" -ForegroundColor DarkGray; return $Default }
    $hint = if ($Default) { " [$Default]" } else { "" }
    $val  = Read-Host "  $Label$hint"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim()
}

function Ask-Bool {
    param([string]$Label, [bool]$Default)
    if ($Yes) { Write-Host "  $Label (auto: $(if ($Default) { 'Y' } else { 'N' }))" -ForegroundColor DarkGray; return $Default }
    $defLabel = if ($Default) { "Y" } else { "N" }
    $val  = Read-Host "  $Label [Y/N, default $defLabel]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim() -imatch '^(y|yes|true|1)$'
}

function Ask-Int {
    param([string]$Label, [int]$Default)
    if ($Yes) { Write-Host "  $Label (auto: $Default)" -ForegroundColor DarkGray; return $Default }
    $val = Read-Host "  $Label [$Default]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    $n = 0
    if ([int]::TryParse($val, [ref]$n)) { return $n }
    return $Default
}

function Normalize-ArtVersion {
    param([string]$Raw)
    $valid = @("art_crop", "border_crop", "normal", "large", "png")
    $v = [string]$Raw
    if ([string]::IsNullOrWhiteSpace($v)) { return "art_crop" }
    $v = $v.Trim().ToLower()
    if ($valid -contains $v) { return $v }
    Write-Host "  [warn] Invalid art version '$Raw'. Falling back to 'art_crop'." -ForegroundColor Yellow
    return "art_crop"
}

function Normalize-ArtMode {
    param([string]$Raw)
    $v = [string]$Raw
    if ([string]::IsNullOrWhiteSpace($v)) { return "2" }
    $v = $v.Trim().ToLower()
    if ($v -in @("1", "direct")) { return "1" }
    if ($v -in @("2", "png_crop", "png-crop", "pngcrop")) { return "2" }
    Write-Host "  [warn] Invalid art mode '$Raw'. Falling back to '2' (png+crop)." -ForegroundColor Yellow
    return "2"
}

function Normalize-UpscaleEngine {
    param([string]$Raw)
    $valid = @("auto", "realesrgan", "lanczos")
    $v = [string]$Raw
    if ([string]::IsNullOrWhiteSpace($v)) { return "auto" }
    $v = $v.Trim().ToLower()
    if ($valid -contains $v) { return $v }
    Write-Host "  [warn] Invalid upscale engine '$Raw'. Falling back to 'auto'." -ForegroundColor Yellow
    return "auto"
}

function Get-RelativePath {
    param([string]$Base, [string]$Target)
    $baseUri   = [System.Uri]([System.IO.Path]::GetFullPath($Base).TrimEnd('\') + '\')
    $targetUri = [System.Uri]([System.IO.Path]::GetFullPath($Target))
    $rel = [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString())
    return $rel -replace '/', '\'
}

function Resolve-ConfigPath([string]$Base, [string]$Value) {
    # Returns $Value unchanged when absolute; otherwise joins with $Base.
    if ([System.IO.Path]::IsPathRooted($Value)) { $Value } else { Join-Path $Base $Value }
}

function Find-RealEsrganExe {
    $candidates = @(
        "realesrgan-ncnn-vulkan.exe",
        "realesrgan-ncnn-vulkan"
    )
    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

function Convert-PngArtToJpegCrop {
    param(
        [string]$ArtDir,
        [datetime]$SinceUtc,
        [int]$JpegQuality = 95,
        [bool]$Overwrite = $true
    )

    if (-not (Test-Path $ArtDir)) { return }

    $pngs = @(Get-ChildItem $ArtDir -Filter "*.png" -File | Where-Object { $_.LastWriteTimeUtc -ge $SinceUtc })
    if ($pngs.Count -eq 0) { return }

    Add-Type -AssemblyName System.Drawing

    $jpegEncoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1
    $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$JpegQuality)

    $converted = 0
    foreach ($png in $pngs) {
        $jpgPath = Join-Path $ArtDir ("{0}.jpg" -f [System.IO.Path]::GetFileNameWithoutExtension($png.Name))
        if ((-not $Overwrite) -and (Test-Path $jpgPath)) { continue }

        $src = $null
        $bmp = $null
        $gfx = $null
        try {
            $src = [System.Drawing.Image]::FromFile($png.FullName)

            $x = [int][Math]::Round($src.Width  * 0.0767)
            $y = [int][Math]::Round($src.Height * 0.1129)
            $w = [int][Math]::Round($src.Width  * 0.8476)
            $h = [int][Math]::Round($src.Height * 0.4429)

            if ($x -lt 0) { $x = 0 }
            if ($y -lt 0) { $y = 0 }
            if ($x + $w -gt $src.Width)  { $w = $src.Width - $x }
            if ($y + $h -gt $src.Height) { $h = $src.Height - $y }

            $bmp = New-Object System.Drawing.Bitmap($w, $h)
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gfx.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $gfx.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $gfx.DrawImage($src, 0, 0, (New-Object System.Drawing.Rectangle($x, $y, $w, $h)), [System.Drawing.GraphicsUnit]::Pixel)

            if ($jpegEncoder) {
                $bmp.Save($jpgPath, $jpegEncoder, $encParams)
            } else {
                $bmp.Save($jpgPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            }
            $converted++
        } catch {
            Write-Host "  [warn] PNG crop failed for '$($png.Name)': $($_.Exception.Message)" -ForegroundColor Yellow
        } finally {
            if ($gfx) { $gfx.Dispose() }
            if ($bmp) { $bmp.Dispose() }
            if ($src) { $src.Dispose() }
        }
    }

    if ($converted -gt 0) {
        Write-Host "  Converted $converted PNG artwork file(s) to cropped JPG art." -ForegroundColor Green
    }
}

function Invoke-ArtUpscale {
    param(
        [string]$ArtDir,
        [datetime]$SinceUtc,
        [string]$Engine = "auto",
        [int]$Factor = 2,
        [bool]$Overwrite = $true,
        [string[]]$Extensions = @('.jpg', '.jpeg', '.png')
    )

    if (-not (Test-Path $ArtDir)) { return }
    if ($Factor -lt 2) { return }

    $targets = @(Get-ChildItem $ArtDir -File | Where-Object {
        $_.LastWriteTimeUtc -ge $SinceUtc -and $_.Extension.ToLower() -in $Extensions
    })
    if ($targets.Count -eq 0) { return }

    $resolvedEngine = Normalize-UpscaleEngine $Engine
    $realesrganExe = $null
    if ($resolvedEngine -in @("auto", "realesrgan")) {
        $realesrganExe = Find-RealEsrganExe
        if (-not $realesrganExe -and $resolvedEngine -eq "realesrgan") {
            Write-Host "  [warn] Real-ESRGAN not found in PATH. Falling back to Lanczos." -ForegroundColor Yellow
            $resolvedEngine = "lanczos"
        }
        if (-not $realesrganExe -and $resolvedEngine -eq "auto") {
            $resolvedEngine = "lanczos"
        }
    }

    Add-Type -AssemblyName System.Drawing

    $jpegEncoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
        Where-Object { $_.MimeType -eq "image/jpeg" } |
        Select-Object -First 1
    $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]95)

    $upscaled = 0
    foreach ($file in $targets) {
        if (-not $Overwrite) { continue }

        if ($resolvedEngine -eq "realesrgan" -or ($resolvedEngine -eq "auto" -and $realesrganExe)) {
            $tmpOut = Join-Path $file.DirectoryName ("{0}.upscaled{1}" -f [System.IO.Path]::GetFileNameWithoutExtension($file.Name), $file.Extension)
            $model = if ($Factor -ge 4) { "realesrgan-x4plus" } else { "realesrgan-x4plus" }
            $scale = if ($Factor -ge 4) { 4 } else { 2 }
            $args = @(
                "-i", $file.FullName,
                "-o", $tmpOut,
                "-n", $model,
                "-s", "$scale"
            )

            $ok = $false
            try {
                & $realesrganExe @args | Out-Null
                if ($LASTEXITCODE -eq 0 -and (Test-Path $tmpOut)) {
                    Move-Item -Force -Path $tmpOut -Destination $file.FullName
                    $ok = $true
                    $upscaled++
                }
            } catch {
                $ok = $false
            }
            if (-not $ok -and (Test-Path $tmpOut)) { Remove-Item -Force $tmpOut }
            if ($ok) { continue }
            Write-Host "  [warn] Real-ESRGAN failed for '$($file.Name)'. Falling back to Lanczos for this file." -ForegroundColor Yellow
        }

        $src = $null
        $bmp = $null
        $gfx = $null
        $tmpLanczosOut = Join-Path $file.DirectoryName ("{0}.upscaled{1}" -f [System.IO.Path]::GetFileNameWithoutExtension($file.Name), $file.Extension)
        $savedLanczos = $false
        try {
            $src = [System.Drawing.Image]::FromFile($file.FullName)
            $w = [int][Math]::Round($src.Width * $Factor)
            $h = [int][Math]::Round($src.Height * $Factor)
            $bmp = New-Object System.Drawing.Bitmap($w, $h)
            $gfx = [System.Drawing.Graphics]::FromImage($bmp)
            $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gfx.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $gfx.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $gfx.CompositingQuality= [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $gfx.DrawImage($src, 0, 0, $w, $h)

            switch ($file.Extension.ToLower()) {
                ".png"  { $bmp.Save($tmpLanczosOut, [System.Drawing.Imaging.ImageFormat]::Png) }
                default {
                    if ($jpegEncoder) {
                        $bmp.Save($tmpLanczosOut, $jpegEncoder, $encParams)
                    } else {
                        $bmp.Save($tmpLanczosOut, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                    }
                }
            }
            $savedLanczos = $true
        } catch {
            Write-Host "  [warn] Upscale failed for '$($file.Name)': $($_.Exception.Message)" -ForegroundColor Yellow
        } finally {
            if ($gfx) { $gfx.Dispose() }
            if ($bmp) { $bmp.Dispose() }
            if ($src) { $src.Dispose() }
        }

        if ($savedLanczos -and (Test-Path $tmpLanczosOut)) {
            try {
                Move-Item -Force -Path $tmpLanczosOut -Destination $file.FullName
                $upscaled++
            } catch {
                Write-Host "  [warn] Upscale replace failed for '$($file.Name)': $($_.Exception.Message)" -ForegroundColor Yellow
                if (Test-Path $tmpLanczosOut) { Remove-Item -Force $tmpLanczosOut }
            }
        } elseif (Test-Path $tmpLanczosOut) {
            Remove-Item -Force $tmpLanczosOut
        }
    }

    if ($upscaled -gt 0) {
        Write-Host "  Upscaled $upscaled artwork file(s) using $resolvedEngine (x$Factor)." -ForegroundColor Green
    }
}

function Expand-CardList {
    # Parses lines like "9 Forest" or "1x Sacred Foundry" and expands to individual names.
    # Quantities > 1 produce  CardName_1, CardName_2, ..., CardName_N  (forced suffix).
    # Quantity   = 1 produces  CardName  (no suffix).
    param([string[]]$Lines)
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $Lines) {
        $line = $line.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { continue }
        if ($line -match '^(\d+)x?\s+(.+)$') {
            $qty  = [int]$Matches[1]
            $name = $Matches[2].Trim()
        } else {
            $qty  = 1
            $name = $line
        }
        if ($qty -le 1) {
            $result.Add($name)
        } else {
            for ($n = 1; $n -le $qty; $n++) { $result.Add("${name}_${n}") }
        }
    }
    return $result.ToArray()
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * [Math]::Max($Title.Length, 40))) -ForegroundColor DarkGray
}

function Write-KV {
    param([string]$Key, $Value)
    Write-Host ("    {0,-22} {1}" -f $Key, $Value)
}

# ── Load config ────────────────────────────────────────────────────────────────

$cfg  = Read-Config $ConfigFile
$root = $cfg.workspaceRoot

# If workspaceRoot is null/empty in config, auto-detect from script location
if ([string]::IsNullOrWhiteSpace($root)) {
    try {
        $root = (Resolve-Path "$PSScriptRoot\..\.." -ErrorAction Stop).Path
    } catch {
        $root = $PSScriptRoot
    }
    Write-Host "  [info] Auto-detected workspace root: $root" -ForegroundColor DarkGray
}

$fetchScript    = Join-Path $PSScriptRoot "fetch_card.mjs"
$generateScript = Join-Path $PSScriptRoot "generate_generic_card.mjs"

foreach ($s in @($fetchScript, $generateScript)) {
    if (-not (Test-Path $s)) {
        Write-Host "  [error] Script not found: $s" -ForegroundColor Red
        exit 1
    }
}

# ── Mode selection ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ==========================================" -ForegroundColor White
    Write-Host "       Generic Card Pipeline               " -ForegroundColor White
    Write-Host "  ==========================================" -ForegroundColor White

Write-Section "Select mode"
Write-Host "    1  Render custom art files"
Write-Host "    2  Load card list file + fetch + render"
Write-Host ""

if ($RunMode -gt 0) {
    $mode = [string]$RunMode
    Write-Host "  Mode: $mode" -ForegroundColor DarkGray
} else {
    $mode = Ask-String "Mode" "1"
}

$doFetch    = $true
$doGenerate = $true

if ($mode -notin @("1","2")) {
    Write-Host "  Invalid mode '$mode'. Choose 1 or 2." -ForegroundColor Red
    exit 1
}

# ── Card list file picker (mode 2) ───────────────────────────────────────────────

$preloadedCardNames = @()

if ($mode -eq "2") {
    Write-Section "Select Card List"

    if ($CardListFile -and (Test-Path $CardListFile)) {
        $preloadedCardNames = Expand-CardList (Get-Content $CardListFile)
        Write-Host "    Loaded $($preloadedCardNames.Count) card(s) from $(Split-Path $CardListFile -Leaf)" -ForegroundColor DarkGray
    } else {
        $cardlistsDir = Resolve-ConfigPath $root $cfg.fetch.cardlistsDir
        $txtFiles = @(Get-ChildItem $cardlistsDir -Filter "*.txt" -ErrorAction SilentlyContinue | Sort-Object Name)

        if ($txtFiles.Count -eq 0) {
            Write-Host "  No .txt files found in $cardlistsDir" -ForegroundColor Yellow
            exit 0
        }

        for ($i = 0; $i -lt $txtFiles.Count; $i++) {
            Write-Host ("    {0}  {1}" -f ($i + 1), $txtFiles[$i].Name)
        }
        Write-Host ""

        $pick = Ask-String "Select file" "1"
        $idx  = 0
        if (-not [int]::TryParse($pick, [ref]$idx) -or $idx -lt 1 -or $idx -gt $txtFiles.Count) {
            Write-Host "  Invalid selection." -ForegroundColor Red
            exit 1
        }

        $selectedFile = $txtFiles[$idx - 1].FullName
        $preloadedCardNames = Expand-CardList (Get-Content $selectedFile)
        Write-Host "    Loaded $($preloadedCardNames.Count) card(s) from $($txtFiles[$idx-1].Name)" -ForegroundColor DarkGray
    }
}

# ── Art scan (mode 1) ────────────────────────────────────────────

$mode2ArtDir = $null

if ($mode -eq "1") {
    Write-Section "Scan Art Directory"

    $defaultArtDir = if ($cfg.fetch.artScanDir) {
        $raw = $cfg.fetch.artScanDir
        if ([System.IO.Path]::IsPathRooted($raw)) { $raw } else { Join-Path $root $raw }
    } else { Resolve-ConfigPath $root $cfg.fetch.artDir }
    $mode2ArtDir   = Ask-String "Art directory to scan" $defaultArtDir

    if (-not (Test-Path $mode2ArtDir)) {
        Write-Host "  Directory not found: $mode2ArtDir" -ForegroundColor Red
        exit 1
    }

    $artFiles = @(Get-ChildItem $mode2ArtDir -File | Where-Object { $_.Extension -in @('.jpg','.jpeg','.png') } | Sort-Object Name)

    if ($artFiles.Count -eq 0) {
        Write-Host "  No image files (.jpg/.jpeg/.png) found in $mode2ArtDir" -ForegroundColor Yellow
        exit 0
    }

    $preloadedCardNames = @($artFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
    Write-Host "    Found $($preloadedCardNames.Count) artwork file(s):" -ForegroundColor DarkGray
    $preloadedCardNames | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    Write-Host ""
}

# ── Fetch options ──────────────────────────────────────────────────────────────

if ($doFetch) {
    Write-Section "Scryfall Fetch"

    [string[]]$cardNames = @($preloadedCardNames)

    if ($cardNames.Count -lt 1) {
        Write-Host "  No card names provided. Exiting." -ForegroundColor Yellow
        exit 0
    }

    $defaultFetchOut = Resolve-ConfigPath $root $cfg.fetch.cardsDir
    $fetchOutDir     = Ask-String "Output directory (.txt files)" $defaultFetchOut
    if ($mode -eq "1") {
        # Art already on disk — use the scanned directory, skip downloading
        $fetchArtDir = $mode2ArtDir
        Write-Host "    Art directory: $fetchArtDir (existing, will not re-download)" -ForegroundColor DarkGray
        $fetchArt = $false
    } else {
        $fetchArtDir = Resolve-ConfigPath $root $cfg.fetch.artDir
        Write-Host "    Art output: $fetchArtDir" -ForegroundColor DarkGray
        $fetchArt = Ask-Bool "Download artwork" ([bool]$cfg.fetch.downloadArt)
    }
    $fetchSet        = Ask-String "Prefer set code (blank = any printing)" $cfg.fetch.preferSet
    $fetchOverwrite  = Ask-Bool   "Overwrite existing files" ([bool]$cfg.fetch.overwrite)
    $defaultArtMode = if ($cfg.fetch.artMode) { [string]$cfg.fetch.artMode } else { "2" }
    $fetchArtMode = if ($fetchArt) {
        Normalize-ArtMode (Ask-String "Art mode (1=direct image variant, 2=png then auto-crop)" $defaultArtMode)
    } else {
        "1"
    }
    $defaultArtVersion = if ($cfg.fetch.artVersion) { [string]$cfg.fetch.artVersion } else { "art_crop" }
    $fetchArtVersion = if ($fetchArt -and $fetchArtMode -eq "1") {
        Normalize-ArtVersion (Ask-String "Art version (art_crop, border_crop, normal, large, png)" $defaultArtVersion)
    } elseif ($fetchArt -and $fetchArtMode -eq "2") {
        "png"
    } else {
        "art_crop"
    }
    $fetchPngCropJpegQuality = if ($cfg.fetch.pngCropJpegQuality) { [int]$cfg.fetch.pngCropJpegQuality } else { 95 }
    $defaultUpscaleEnabled = if ($null -ne $cfg.fetch.upscaleEnabled) { [bool]$cfg.fetch.upscaleEnabled } else { $false }
    $fetchUpscaleEnabled = if ($fetchArt) { Ask-Bool "Upscale artwork after fetch/crop" $defaultUpscaleEnabled } else { $false }
    $defaultUpscaleEngine = if ($cfg.fetch.upscaleEngine) { [string]$cfg.fetch.upscaleEngine } else { "auto" }
    $fetchUpscaleEngine = if ($fetchUpscaleEnabled) {
        Normalize-UpscaleEngine (Ask-String "Upscale engine (auto, realesrgan, lanczos)" $defaultUpscaleEngine)
    } else {
        "auto"
    }
    $defaultUpscaleFactor = if ($cfg.fetch.upscaleFactor) { [int]$cfg.fetch.upscaleFactor } else { 2 }
    $fetchUpscaleFactor = if ($fetchUpscaleEnabled) { Ask-Int "Upscale factor (2 or 4)" $defaultUpscaleFactor } else { 2 }
    if ($fetchUpscaleFactor -lt 2) { $fetchUpscaleFactor = 2 }
    if ($fetchUpscaleFactor -gt 4) { $fetchUpscaleFactor = 4 }
    $fetchDryRun     = [bool]$cfg.fetch.dryRun
    $defaultIncludeFlavor = if ($null -ne $cfg.fetch.includeFlavor) { [bool]$cfg.fetch.includeFlavor } else { $true }
    $fetchIncludeFlavor = Ask-Bool "Include flavor text" $defaultIncludeFlavor
}

# ── Generate options ───────────────────────────────────────────────────────────

if ($doGenerate) {
    Write-Section "Card Renderer"

    # URL, headless, launcher come silently from config
    $genBaseUrl  = $cfg.generate.baseUrl
    $genHeadless = [bool]$cfg.generate.headless
    $genLauncher = [bool]$cfg.generate.startLauncher

    # Input dir: auto-set when chaining from fetch, otherwise ask
    if ($doFetch) {
        $genInputDir = $fetchOutDir
        $genArtDir   = $fetchArtDir
        Write-Host "    Input:  $genInputDir" -ForegroundColor DarkGray
        Write-Host "    Art:    $genArtDir"   -ForegroundColor DarkGray
    } else {
        $genInputDir = Ask-String "Input directory (.txt files)" (Resolve-ConfigPath $root $cfg.fetch.cardsDir)
        $defaultArtDir = Resolve-ConfigPath $root $cfg.fetch.artDir
        $artDirRaw   = Ask-String "Art directory (blank = same as input)" $defaultArtDir
        $genArtDir   = if ($artDirRaw -and $artDirRaw -ne $genInputDir) { $artDirRaw } else { $null }
    }

    $defaultOutput = Resolve-ConfigPath $genInputDir $cfg.generate.outputSubDir
    $genOutputDir  = Ask-String "Output directory (PNG files)" $defaultOutput
    $genOverwrite  = Ask-Bool   "Overwrite existing PNGs" ([bool]$cfg.generate.overwrite)
    $genLimit      = Ask-Int    "Card limit (0 = all)" ([int]$cfg.generate.limit)
    $defaultRenderUpscaleEnabled = if ($null -ne $cfg.generate.upscaleEnabled) { [bool]$cfg.generate.upscaleEnabled } else { $false }
    $genUpscaleEnabled = Ask-Bool "Upscale rendered output after render" $defaultRenderUpscaleEnabled
    $defaultRenderUpscaleEngine = if ($cfg.generate.upscaleEngine) { [string]$cfg.generate.upscaleEngine } else { "auto" }
    $genUpscaleEngine = if ($genUpscaleEnabled) {
        Normalize-UpscaleEngine (Ask-String "Render upscale engine (auto, realesrgan, lanczos)" $defaultRenderUpscaleEngine)
    } else {
        "auto"
    }
    $defaultRenderUpscaleFactor = if ($cfg.generate.upscaleFactor) { [int]$cfg.generate.upscaleFactor } else { 2 }
    $genUpscaleFactor = if ($genUpscaleEnabled) { Ask-Int "Render upscale factor (2 or 4)" $defaultRenderUpscaleFactor } else { 2 }
    if ($genUpscaleFactor -lt 2) { $genUpscaleFactor = 2 }
    if ($genUpscaleFactor -gt 4) { $genUpscaleFactor = 4 }
    $genDryRun     = [bool]$cfg.generate.dryRun
}

$chunkSize   = [int]$cfg.fetch.chunkSize
$useChunked  = $doFetch -and $doGenerate -and $chunkSize -gt 0 -and $cardNames.Count -gt $chunkSize

# ── Summary ────────────────────────────────────────────────────────────────────

Write-Section "Summary"

if ($doFetch) {
    Write-Host "  Fetch" -ForegroundColor White
    Write-KV "Cards:"       ($cardNames -join ", ")
    Write-KV "Output dir:"  $fetchOutDir
    if ($fetchArt) { Write-KV "Art dir:" $fetchArtDir }
    if ($fetchSet)       { Write-KV "Set:"         $fetchSet }
    Write-KV "Overwrite:"   $fetchOverwrite
    Write-KV "Download art:" $fetchArt
    if ($fetchArt) {
        Write-KV "Art mode:"    $(if ($fetchArtMode -eq "2") { "2 (png + auto-crop)" } else { "1 (direct)" })
        if ($fetchArtMode -eq "2") {
            Write-KV "Art version:" "png (forced)"
            Write-KV "Crop JPG quality:" $fetchPngCropJpegQuality
        } else {
            Write-KV "Art version:" $fetchArtVersion
        }
        Write-KV "Upscale:" $(if ($fetchUpscaleEnabled) { "Yes ($fetchUpscaleEngine x$fetchUpscaleFactor)" } else { "No" })
    }
    Write-KV "Flavor text:"  $(if ($fetchIncludeFlavor) { "Yes" } else { "No" })
    if ($fetchDryRun)    { Write-Host "    *** FETCH DRY RUN (config) ***" -ForegroundColor Yellow }
}

if ($doGenerate) {
    Write-Host ""
    Write-Host "  Render" -ForegroundColor White
    Write-KV "Input dir:"  $genInputDir
    Write-KV "Output dir:" $genOutputDir
    if ($genArtDir)     { Write-KV "Art dir:"  $genArtDir }
    Write-KV "URL:"         $genBaseUrl
    Write-KV "Headless:"    $genHeadless
    Write-KV "Launcher:"    $genLauncher
    Write-KV "Overwrite:"   $genOverwrite
    Write-KV "Limit:"       $(if ($genLimit -gt 0) { $genLimit } else { "all" })
    Write-KV "Render upscale:" $(if ($genUpscaleEnabled) { "Yes ($genUpscaleEngine x$genUpscaleFactor)" } else { "No" })
    if ($useChunked) { Write-KV "Chunk size:" "$chunkSize cards/chunk ($([Math]::Ceiling($cardNames.Count / $chunkSize)) chunks)" }
    if ($genDryRun)     { Write-Host "    *** RENDER DRY RUN (config) ***" -ForegroundColor Yellow }
}

Write-Host ""
if (-not $Yes) {
    $confirm = Ask-Bool "Proceed?" $true
    if (-not $confirm) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "  Proceeding (auto)." -ForegroundColor DarkGray
}

# ── Save config ────────────────────────────────────────────────────────────────

if ($doFetch) {
    $cfg.fetch.cardsDir       = Get-RelativePath $root $fetchOutDir
    $cfg.fetch.preferSet      = $fetchSet
    $cfg.fetch.overwrite      = $fetchOverwrite
    $cfg.fetch.downloadArt    = $fetchArt
    $cfg.fetch.artMode        = [int]$fetchArtMode
    $cfg.fetch.artVersion     = $fetchArtVersion
    $cfg.fetch.upscaleEnabled  = $fetchUpscaleEnabled
    $cfg.fetch.upscaleEngine   = $fetchUpscaleEngine
    $cfg.fetch.upscaleFactor   = $fetchUpscaleFactor
    $cfg.fetch.includeFlavor   = $fetchIncludeFlavor
}
if ($doGenerate) {
    $cfg.generate.outputSubDir   = Get-RelativePath $genInputDir $genOutputDir
    $cfg.generate.overwrite      = $genOverwrite
    $cfg.generate.limit          = $genLimit
    $cfg.generate.upscaleEnabled = $genUpscaleEnabled
    $cfg.generate.upscaleEngine  = $genUpscaleEngine
    $cfg.generate.upscaleFactor  = $genUpscaleFactor
}
$cfg | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigFile -Encoding utf8
Write-Host "  Config saved." -ForegroundColor DarkGray

# ── Run fetch + generate ───────────────────────────────────────────────────────

# Shared helper: build the static part of the generate args
function Build-GenArgs {
    param($genInputDir, $genOutputDir, $genArtDir, $genBaseUrl, $genHeadless, $genLauncher, $genOverwrite, $genLimit, $genDryRun)
    $a  = @()
    $a += "--input",          "`"$genInputDir`""
    $a += "--output",         "`"$genOutputDir`""
    if ($genArtDir)   { $a += "--art-dir", "`"$genArtDir`"" }
    $a += "--base-url",       "`"$genBaseUrl`""
    $a += "--headless",       ($genHeadless.ToString().ToLower())
    $a += "--start-launcher", ($genLauncher.ToString().ToLower())
    $a += "--overwrite",      ($genOverwrite.ToString().ToLower())
    if ($genLimit -gt 0) { $a += "--limit", $genLimit }
    if ($genDryRun)      { $a += "--dry-run" }
    return $a
}

if ($useChunked) {
    # ── Chunked pipeline: fetch N → render N → repeat ──────────────────────────

    if (-not $fetchDryRun) {
        New-Item -ItemType Directory -Force -Path $fetchOutDir | Out-Null
        if ($fetchArt) { New-Item -ItemType Directory -Force -Path $fetchArtDir | Out-Null }
    }
    if (-not $genDryRun) {
        New-Item -ItemType Directory -Force -Path $genOutputDir | Out-Null
    }

    # Build chunks
    $chunks = @()
    for ($ci = 0; $ci -lt $cardNames.Count; $ci += $chunkSize) {
        $end = [Math]::Min($ci + $chunkSize - 1, $cardNames.Count - 1)
        $chunks += ,@($cardNames[$ci..$end])
    }
    $totalChunks = $chunks.Count

    for ($ci = 0; $ci -lt $totalChunks; $ci++) {
        $chunk = $chunks[$ci]
        Write-Section "Chunk $($ci + 1) of $totalChunks  ($($chunk.Count) cards)"

        # Fetch this chunk
        $beforeFetchUtc = [System.DateTime]::UtcNow
        $beforeFetch = $beforeFetchUtc.ToString("o")

        $fetchArgs  = @()
        $fetchArgs += $chunk | ForEach-Object { "`"$_`"" }
        $fetchArgs += "--output", "`"$fetchOutDir`""
        if ($fetchArt)        { $fetchArgs += "--art-output", "`"$fetchArtDir`""; $fetchArgs += "--art-version", "`"$fetchArtVersion`"" }
        if ($fetchSet)        { $fetchArgs += "--set", "`"$fetchSet`"" }
        if ($fetchOverwrite)        { $fetchArgs += "--overwrite" }
        if (-not $fetchArt)           { $fetchArgs += "--no-art" }
        if (-not $fetchIncludeFlavor) { $fetchArgs += "--no-flavor" }
        if ($fetchDryRun)             { $fetchArgs += "--dry-run" }

        $fetchCmd = "node `"$fetchScript`" $($fetchArgs -join ' ')"
        Write-Host "  > $fetchCmd" -ForegroundColor DarkGray
        Write-Host ""

        Invoke-Expression $fetchCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Fetch failed on chunk $($ci + 1) (exit $LASTEXITCODE). Stopping." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        if ($fetchArt -and $fetchArtMode -eq "2" -and -not $fetchDryRun) {
            Convert-PngArtToJpegCrop -ArtDir $fetchArtDir -SinceUtc $beforeFetchUtc -JpegQuality $fetchPngCropJpegQuality -Overwrite $fetchOverwrite
        }
        if ($fetchArt -and $fetchUpscaleEnabled -and -not $fetchDryRun) {
            $upscaleExts = if ($fetchArtMode -eq "2") { @('.jpg', '.jpeg') } else { @('.jpg', '.jpeg', '.png') }
            Invoke-ArtUpscale -ArtDir $fetchArtDir -SinceUtc $beforeFetchUtc -Engine $fetchUpscaleEngine -Factor $fetchUpscaleFactor -Overwrite $fetchOverwrite -Extensions $upscaleExts
        }

        # Render this chunk (only .txt files newer than $beforeFetch)
        Write-Host ""

        $genArgs  = Build-GenArgs $genInputDir $genOutputDir $genArtDir $genBaseUrl $genHeadless $genLauncher $genOverwrite 0 $genDryRun
        $genArgs += "--newer-than", "`"$beforeFetch`""

        $genCmd = "node `"$generateScript`" $($genArgs -join ' ')"
        Write-Host "  > $genCmd" -ForegroundColor DarkGray
        Write-Host ""

        $beforeRenderUtc = [System.DateTime]::UtcNow
        Invoke-Expression $genCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Render failed on chunk $($ci + 1) (exit $LASTEXITCODE). Stopping." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        if ($genUpscaleEnabled -and -not $genDryRun) {
            Invoke-ArtUpscale -ArtDir $genOutputDir -SinceUtc $beforeRenderUtc -Engine $genUpscaleEngine -Factor $genUpscaleFactor -Overwrite $true -Extensions @('.png', '.jpg', '.jpeg')
        }
    }

} else {
    # ── Normal: fetch all, then render all ─────────────────────────────────────

    if ($doFetch) {
        Write-Section "Running Scryfall Fetch"
        $beforeFetchUtc = [System.DateTime]::UtcNow
        $beforeFetchIso = $beforeFetchUtc.ToString("o")

        if (-not $fetchDryRun) {
            New-Item -ItemType Directory -Force -Path $fetchOutDir | Out-Null
            if ($fetchArt) { New-Item -ItemType Directory -Force -Path $fetchArtDir | Out-Null }
        }

        $fetchArgs  = @()
        $fetchArgs += $cardNames | ForEach-Object { "`"$_`"" }
        $fetchArgs += "--output", "`"$fetchOutDir`""
        if ($fetchArt)        { $fetchArgs += "--art-output", "`"$fetchArtDir`""; $fetchArgs += "--art-version", "`"$fetchArtVersion`"" }
        if ($fetchSet)        { $fetchArgs += "--set", "`"$fetchSet`"" }
        if ($fetchOverwrite)        { $fetchArgs += "--overwrite" }
        if (-not $fetchArt)           { $fetchArgs += "--no-art" }
        if (-not $fetchIncludeFlavor) { $fetchArgs += "--no-flavor" }
        if ($fetchDryRun)             { $fetchArgs += "--dry-run" }

        $fetchCmd = "node `"$fetchScript`" $($fetchArgs -join ' ')"
        Write-Host "  > $fetchCmd" -ForegroundColor DarkGray
        Write-Host ""

        Invoke-Expression $fetchCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Fetch failed (exit $LASTEXITCODE)." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        if ($fetchArt -and $fetchArtMode -eq "2" -and -not $fetchDryRun) {
            Convert-PngArtToJpegCrop -ArtDir $fetchArtDir -SinceUtc $beforeFetchUtc -JpegQuality $fetchPngCropJpegQuality -Overwrite $fetchOverwrite
        }
        if ($fetchArt -and $fetchUpscaleEnabled -and -not $fetchDryRun) {
            $upscaleExts = if ($fetchArtMode -eq "2") { @('.jpg', '.jpeg') } else { @('.jpg', '.jpeg', '.png') }
            Invoke-ArtUpscale -ArtDir $fetchArtDir -SinceUtc $beforeFetchUtc -Engine $fetchUpscaleEngine -Factor $fetchUpscaleFactor -Overwrite $fetchOverwrite -Extensions $upscaleExts
        }
    }

    if ($doGenerate) {
        Write-Section "Running Card Renderer"

        if (-not $genDryRun) {
            New-Item -ItemType Directory -Force -Path $genOutputDir | Out-Null
        }

        $genArgs  = Build-GenArgs $genInputDir $genOutputDir $genArtDir $genBaseUrl $genHeadless $genLauncher $genOverwrite $genLimit $genDryRun
        if ($doFetch) {
            # In fetch+render mode, only render .txt files created/updated in this run.
            $genArgs += "--newer-than", "`"$beforeFetchIso`""
        }

        $genCmd = "node `"$generateScript`" $($genArgs -join ' ')"
        Write-Host "  > $genCmd" -ForegroundColor DarkGray
        Write-Host ""

        $beforeRenderUtc = [System.DateTime]::UtcNow
        Invoke-Expression $genCmd
        if ($LASTEXITCODE -ne 0) {
            $firstRenderExit = $LASTEXITCODE
            if ($genLauncher) {
                Write-Host ""
                Write-Host "  Render failed (exit $firstRenderExit). Retrying once with launcher disabled..." -ForegroundColor Yellow

                $retryGenArgs = Build-GenArgs $genInputDir $genOutputDir $genArtDir $genBaseUrl $genHeadless $false $genOverwrite $genLimit $genDryRun
                if ($doFetch) {
                    $retryGenArgs += "--newer-than", "`"$beforeFetchIso`""
                }

                $retryGenCmd = "node `"$generateScript`" $($retryGenArgs -join ' ')"
                Write-Host "  > $retryGenCmd" -ForegroundColor DarkGray
                Write-Host ""

                Invoke-Expression $retryGenCmd
                if ($LASTEXITCODE -ne 0) {
                    Write-Host ""
                    Write-Host "  Render failed (exit $LASTEXITCODE)." -ForegroundColor Red
                    exit $LASTEXITCODE
                }
            } else {
                Write-Host ""
                Write-Host "  Render failed (exit $firstRenderExit)." -ForegroundColor Red
                exit $firstRenderExit
            }
        }

        if ($genUpscaleEnabled -and -not $genDryRun) {
            Invoke-ArtUpscale -ArtDir $genOutputDir -SinceUtc $beforeRenderUtc -Engine $genUpscaleEngine -Factor $genUpscaleFactor -Overwrite $true -Extensions @('.png', '.jpg', '.jpeg')
        }
    }
}

Write-Host ""
Write-Host "  Done." -ForegroundColor Green
