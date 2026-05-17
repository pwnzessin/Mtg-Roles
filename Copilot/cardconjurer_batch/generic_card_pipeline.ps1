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
    [string]$ConfigFile = "$PSScriptRoot\generic_card_config.json"
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
        fetch    = [pscustomobject]@{ cardsDir="Cards\Generic"; preferSet=""; overwrite=$false; downloadArt=$true }
        generate = [pscustomobject]@{ outputSubDir="output"; baseUrl="http://localhost:8080"; headless=$true; startLauncher=$true; overwrite=$false; limit=0 }
    }
}

# ── Prompt helpers ─────────────────────────────────────────────────────────────

function Ask-String {
    param([string]$Label, [string]$Default)
    $hint = if ($Default) { " [$Default]" } else { "" }
    $val  = Read-Host "  $Label$hint"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim()
}

function Ask-Bool {
    param([string]$Label, [bool]$Default)
    $defLabel = if ($Default) { "Y" } else { "N" }
    $val  = Read-Host "  $Label [Y/N, default $defLabel]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim() -imatch '^(y|yes|true|1)$'
}

function Ask-Int {
    param([string]$Label, [int]$Default)
    $val = Read-Host "  $Label [$Default]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    $n = 0
    if ([int]::TryParse($val, [ref]$n)) { return $n }
    return $Default
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
Write-Host "    1  Fetch from Scryfall + render cards"
Write-Host "    2  Render existing .txt files"
Write-Host "    3  Fetch from Scryfall only (no render)"
Write-Host "    4  Load card list file + fetch + render"
Write-Host "    5  Clear output / downloaded art folders"
Write-Host ""

$mode = Ask-String "Mode" "1"

$doFetch    = $mode -in @("1","3","4")
$doGenerate = $mode -in @("1","2","4")

if (-not $doFetch -and -not $doGenerate -and $mode -ne "5") {
    Write-Host "  Invalid mode '$mode'. Choose 1-5." -ForegroundColor Red
    exit 1
}

# ── Clear folders (mode 5) ────────────────────────────────────────────────────

if ($mode -eq "5") {
    $outputDir    = Join-Path $root (Join-Path $cfg.fetch.cardsDir $cfg.generate.outputSubDir)
    $downloadedDir = Join-Path $root $cfg.fetch.artDir

    Write-Section "Clear Folders"
    Write-Host "    Output folder:    $outputDir" -ForegroundColor DarkGray
    Write-Host "    Downloaded art:   $downloadedDir" -ForegroundColor DarkGray
    Write-Host ""

    $clearOutput     = Ask-Bool "Clear rendered PNGs in output folder"      $true
    $clearTxt        = Ask-Bool "Clear .txt card files in output folder"   $false
    $clearDownloaded = Ask-Bool "Clear downloaded artwork (jpg/png)"       $true
    Write-Host ""

    $confirm = Ask-Bool "Proceed?" $true
    if (-not $confirm) {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        exit 0
    }

    if ($clearOutput) {
        if (Test-Path $outputDir) {
            $pngs = @(Get-ChildItem $outputDir -Filter "*.png" -File)
            $pngs | ForEach-Object { Remove-Item $_.FullName -Force }
            Write-Host "  Removed $($pngs.Count) PNG(s) from $outputDir" -ForegroundColor Green
        } else {
            Write-Host "  Output folder not found, nothing to clear." -ForegroundColor Yellow
        }
    }

    if ($clearTxt) {
        if (Test-Path $outputDir) {
            $txts = @(Get-ChildItem $outputDir -Filter "*.txt" -File)
            $txts | ForEach-Object { Remove-Item $_.FullName -Force }
            Write-Host "  Removed $($txts.Count) .txt file(s) from $outputDir" -ForegroundColor Green
        } else {
            Write-Host "  Output folder not found, nothing to clear." -ForegroundColor Yellow
        }
    }

    if ($clearDownloaded) {
        if (Test-Path $downloadedDir) {
            $imgs = @(Get-ChildItem $downloadedDir -File | Where-Object { $_.Extension -in @('.jpg','.png') })
            $imgs | ForEach-Object { Remove-Item $_.FullName -Force }
            Write-Host "  Removed $($imgs.Count) image(s) from $downloadedDir" -ForegroundColor Green
        } else {
            Write-Host "  Downloaded art folder not found, nothing to clear." -ForegroundColor Yellow
        }
    }

    exit 0
}

# ── Card list file picker (mode 4) ───────────────────────────────────────────────

$preloadedCardNames = $null

if ($mode -eq "4") {
    Write-Section "Select Card List"

    $cardlistsDir = Join-Path $root $cfg.fetch.cardlistsDir
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
    $preloadedCardNames = @(
        Get-Content $selectedFile | ForEach-Object {
            ($_ -replace '^\s*\d+x?\s+', '').Trim()
        } | Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }
    )
    Write-Host "    Loaded $($preloadedCardNames.Count) card(s) from $($txtFiles[$idx-1].Name)" -ForegroundColor DarkGray
}

# ── Fetch options ──────────────────────────────────────────────────────────────

if ($doFetch) {
    Write-Section "Scryfall Fetch"

    if ($preloadedCardNames) {
        $cardNames = $preloadedCardNames
    } else {
        Write-Host "    Enter card names (comma-separated) or a path to a .txt file (one name per line)." -ForegroundColor DarkGray
        $rawInput = Ask-String "Card names or file path" ""

        # Detect file path: ends in .txt and the file exists
        if ($rawInput -match '\.txt$' -and (Test-Path $rawInput)) {
            $cardNames = @(Get-Content $rawInput | ForEach-Object {
                # Strip leading deck-list count, e.g. "1 Lightning Bolt" or "4x Sol Ring"
                $_ -replace '^\s*\d+x?\s+', '' | ForEach-Object { $_.Trim() }
        } | Where-Object { $_ -ne "" -and -not $_.StartsWith("#") })
        Write-Host "    Loaded $($cardNames.Count) card(s) from $rawInput" -ForegroundColor DarkGray
    } else {
        $cardNames = @($rawInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    }
    } # end: not pre-loaded

    if ($cardNames.Count -eq 0) {
        Write-Host "  No card names entered. Exiting." -ForegroundColor Yellow
        exit 0
    }

    $defaultFetchOut = Join-Path $root $cfg.fetch.cardsDir
    $fetchOutDir     = Ask-String "Output directory (.txt files)" $defaultFetchOut
    $fetchArtDir     = Join-Path $root $cfg.fetch.artDir
    Write-Host "    Art output: $fetchArtDir" -ForegroundColor DarkGray
    $fetchSet        = Ask-String "Prefer set code (blank = any printing)" $cfg.fetch.preferSet
    $fetchOverwrite  = Ask-Bool   "Overwrite existing files" ([bool]$cfg.fetch.overwrite)
    $fetchArt        = Ask-Bool   "Download artwork" ([bool]$cfg.fetch.downloadArt)
    $fetchDryRun     = [bool]$cfg.fetch.dryRun
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
        $genInputDir = Ask-String "Input directory (.txt files)" (Join-Path $root $cfg.fetch.cardsDir)
        $defaultArtDir = Join-Path $root $cfg.fetch.artDir
        $artDirRaw   = Ask-String "Art directory (blank = same as input)" $defaultArtDir
        $genArtDir   = if ($artDirRaw -and $artDirRaw -ne $genInputDir) { $artDirRaw } else { $null }
    }

    $defaultOutput = Join-Path $genInputDir $cfg.generate.outputSubDir
    $genOutputDir  = Ask-String "Output directory (PNG files)" $defaultOutput
    $genOverwrite  = Ask-Bool   "Overwrite existing PNGs" ([bool]$cfg.generate.overwrite)
    $genLimit      = Ask-Int    "Card limit (0 = all)" ([int]$cfg.generate.limit)
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
    if ($useChunked) { Write-KV "Chunk size:" "$chunkSize cards/chunk ($([Math]::Ceiling($cardNames.Count / $chunkSize)) chunks)" }
    if ($genDryRun)     { Write-Host "    *** RENDER DRY RUN (config) ***" -ForegroundColor Yellow }
}

Write-Host ""
$confirm = Ask-Bool "Proceed?" $true
if (-not $confirm) {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

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
        $beforeFetch = [System.DateTime]::UtcNow.ToString("o")

        $fetchArgs  = @()
        $fetchArgs += $chunk | ForEach-Object { "`"$_`"" }
        $fetchArgs += "--output", "`"$fetchOutDir`""
        if ($fetchArt)        { $fetchArgs += "--art-output", "`"$fetchArtDir`"" }
        if ($fetchSet)        { $fetchArgs += "--set", "`"$fetchSet`"" }
        if ($fetchOverwrite)  { $fetchArgs += "--overwrite" }
        if (-not $fetchArt)   { $fetchArgs += "--no-art" }
        if ($fetchDryRun)     { $fetchArgs += "--dry-run" }

        $fetchCmd = "node `"$fetchScript`" $($fetchArgs -join ' ')"
        Write-Host "  > $fetchCmd" -ForegroundColor DarkGray
        Write-Host ""

        Invoke-Expression $fetchCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Fetch failed on chunk $($ci + 1) (exit $LASTEXITCODE). Stopping." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        # Render this chunk (only .txt files newer than $beforeFetch)
        Write-Host ""

        $genArgs  = Build-GenArgs $genInputDir $genOutputDir $genArtDir $genBaseUrl $genHeadless $genLauncher $genOverwrite 0 $genDryRun
        $genArgs += "--newer-than", "`"$beforeFetch`""

        $genCmd = "node `"$generateScript`" $($genArgs -join ' ')"
        Write-Host "  > $genCmd" -ForegroundColor DarkGray
        Write-Host ""

        Invoke-Expression $genCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Render failed on chunk $($ci + 1) (exit $LASTEXITCODE). Stopping." -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }

} else {
    # ── Normal: fetch all, then render all ─────────────────────────────────────

    if ($doFetch) {
        Write-Section "Running Scryfall Fetch"

        if (-not $fetchDryRun) {
            New-Item -ItemType Directory -Force -Path $fetchOutDir | Out-Null
            if ($fetchArt) { New-Item -ItemType Directory -Force -Path $fetchArtDir | Out-Null }
        }

        $fetchArgs  = @()
        $fetchArgs += $cardNames | ForEach-Object { "`"$_`"" }
        $fetchArgs += "--output", "`"$fetchOutDir`""
        if ($fetchArt)        { $fetchArgs += "--art-output", "`"$fetchArtDir`"" }
        if ($fetchSet)        { $fetchArgs += "--set", "`"$fetchSet`"" }
        if ($fetchOverwrite)  { $fetchArgs += "--overwrite" }
        if (-not $fetchArt)   { $fetchArgs += "--no-art" }
        if ($fetchDryRun)     { $fetchArgs += "--dry-run" }

        $fetchCmd = "node `"$fetchScript`" $($fetchArgs -join ' ')"
        Write-Host "  > $fetchCmd" -ForegroundColor DarkGray
        Write-Host ""

        Invoke-Expression $fetchCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Fetch failed (exit $LASTEXITCODE)." -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }

    if ($doGenerate) {
        Write-Section "Running Card Renderer"

        if (-not $genDryRun) {
            New-Item -ItemType Directory -Force -Path $genOutputDir | Out-Null
        }

        $genArgs  = Build-GenArgs $genInputDir $genOutputDir $genArtDir $genBaseUrl $genHeadless $genLauncher $genOverwrite $genLimit $genDryRun

        $genCmd = "node `"$generateScript`" $($genArgs -join ' ')"
        Write-Host "  > $genCmd" -ForegroundColor DarkGray
        Write-Host ""

        Invoke-Expression $genCmd
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "  Render failed (exit $LASTEXITCODE)." -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }
}

Write-Host ""
Write-Host "  Done." -ForegroundColor Green
