<#
.SYNOPSIS
    Art generation pipeline: reads a card list or card names and generates
    artwork via Pollinations.ai (free, no API key required).

.DESCRIPTION
    Defaults are loaded from art_gen_config.json in the same folder.
    Edit that file to change your personal defaults.

.PARAMETER ConfigFile
    Path to the JSON config file. Defaults to art_gen_config.json
    in the same directory as this script.

.PARAMETER RunMode
    1 = enter card names manually (comma-separated)
    2 = load a card list .txt file
    0 = ask interactively (default)

.PARAMETER CardListFile
    Path to a .txt card list file (one card name per line). Used when RunMode=2.

.PARAMETER CardNames
    Comma-separated card names. Used when RunMode=1.

.PARAMETER Yes
    Skip all confirmation prompts and accept config defaults.
#>
param(
    [string]$ConfigFile   = "$PSScriptRoot\art_gen_config.json",
    [int]   $RunMode      = 0,
    [string]$CardListFile = "",
    [string]$CardNames    = "",
    [switch]$Yes
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Config loading ─────────────────────────────────────────────────────────────

function Read-Config {
    param([string]$Path)
    if (Test-Path $Path) {
        return Get-Content $Path -Raw | ConvertFrom-Json
    }
    Write-Host "  [warn] Config not found at '$Path' - using built-in defaults." -ForegroundColor Yellow
    $wsRoot = $null
    try { $wsRoot = (Resolve-Path "$PSScriptRoot\..\.." -ErrorAction Stop).Path } catch { $wsRoot = $PSScriptRoot }
    return [pscustomobject]@{
        workspaceRoot = $wsRoot
        cardlistsDir  = "Copilot\cardconjurer_batch\Cardlists"
        outputDir     = "Artworks\Generated"
        style         = "fantasy card art, digital painting, highly detailed, no text, no borders"
        prefix        = ""
        overwrite     = $false
        concurrency   = 1
        width         = 626
        height        = 457
        seed          = $null
        dryRun        = $false
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
    $val = Read-Host "  $Label [Y/N, default $defLabel]"
    if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
    return $val.Trim() -imatch '^(y|yes|true|1)$'
}

function Resolve-ConfigPath([string]$Base, [string]$Value) {
    if ([System.IO.Path]::IsPathRooted($Value)) { $Value } else { Join-Path $Base $Value }
}

# ── Main ───────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=== Art Generation Pipeline ===" -ForegroundColor Cyan

$cfg    = Read-Config $ConfigFile
$wsRoot = if ($cfg.workspaceRoot) { [string]$cfg.workspaceRoot } else {
    (Resolve-Path "$PSScriptRoot\..\.." -ErrorAction Stop).Path
}

$outDir = Resolve-ConfigPath $wsRoot ([string]$cfg.outputDir)

# ── Mode selection ─────────────────────────────────────────────────────────────

if ($RunMode -eq 0 -and -not $Yes) {
    Write-Host ""
    Write-Host "  Select mode:"
    Write-Host "    1 - Enter card names manually"
    Write-Host "    2 - Load card list file"
    $raw = Read-Host "  Choice [1]"
    if ([string]::IsNullOrWhiteSpace($raw)) { $RunMode = 1 } else { $RunMode = [int]$raw }
}
if ($RunMode -eq 0) { $RunMode = 1 }

# ── Card input ─────────────────────────────────────────────────────────────────

$nodeInput = @()

if ($RunMode -eq 1) {
    if ([string]::IsNullOrWhiteSpace($CardNames)) {
        $CardNames = Ask-String "Card names (comma-separated)" ""
    } else {
        Write-Host "  Card names: $CardNames" -ForegroundColor DarkGray
    }
    if ([string]::IsNullOrWhiteSpace($CardNames)) {
        Write-Error "No card names provided. Aborting."
        exit 1
    }
    $nodeInput += @("--names", $CardNames)

} elseif ($RunMode -eq 2) {
    if ([string]::IsNullOrWhiteSpace($CardListFile)) {
        $CardListFile = Ask-String "Card list file" ""
    } else {
        Write-Host "  Card list: $CardListFile" -ForegroundColor DarkGray
    }
    if ([string]::IsNullOrWhiteSpace($CardListFile) -or -not (Test-Path $CardListFile)) {
        Write-Error "Card list file not found: '$CardListFile'. Aborting."
        exit 1
    }
    $nodeInput += @("--cardlist", $CardListFile)
}

# ── Build node args from config ────────────────────────────────────────────────

$style  = [string]$cfg.style
$prefix = [string]$cfg.prefix
$conc   = [int]$cfg.concurrency
$w      = [int]$cfg.width
$h      = [int]$cfg.height
$ow     = [bool]$cfg.overwrite
$dry    = [bool]$cfg.dryRun
$seed   = $cfg.seed
$token          = if ($cfg.PSObject.Properties['apiToken']) { [string]$cfg.apiToken } else { "" }
$model          = if ($cfg.PSObject.Properties['model'] -and [string]$cfg.model) { [string]$cfg.model } else { "black-forest-labs/FLUX.1-schnell" }
$provider       = if ($model -eq "midjourney") { "midjourney" } else { "huggingface" }
$discordToken   = if ($cfg.PSObject.Properties['discordToken'])     { [string]$cfg.discordToken }     else { "" }
$discordChannel = if ($cfg.PSObject.Properties['discordChannelId']) { [string]$cfg.discordChannelId } else { "" }
$discordGuild   = if ($cfg.PSObject.Properties['discordGuildId'])   { [string]$cfg.discordGuildId }   else { "" }

if ($provider -eq "huggingface") {
    if ([string]::IsNullOrWhiteSpace($token)) { $token = $env:HF_TOKEN }
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Error "apiToken is not set in config and HF_TOKEN env var is empty.`nGet a free token at https://huggingface.co/settings/tokens"
        exit 1
    }
} elseif ($provider -eq "midjourney") {
    if ([string]::IsNullOrWhiteSpace($discordToken)) { $discordToken = $env:DISCORD_TOKEN }
    if ([string]::IsNullOrWhiteSpace($discordToken)) {
        Write-Error "discordToken is not set in config and DISCORD_TOKEN env var is empty."
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($discordChannel)) {
        Write-Error "discordChannelId is not set in art_gen_config.json."
        exit 1
    }
    if ([string]::IsNullOrWhiteSpace($discordGuild)) {
        Write-Error "discordGuildId is not set in art_gen_config.json."
        exit 1
    }
} else {
    Write-Error "Unknown provider '$provider'. Valid values: huggingface, midjourney"
    exit 1
}

if (-not $Yes) {
    Write-Host ""
    Write-Host "  Provider: $provider"
    Write-Host "  Output  : $outDir"
    Write-Host "  Style   : $style"
    if ($provider -eq "midjourney") {
        Write-Host "  Channel : $discordChannel"
        Write-Host "  Guild   : $discordGuild"
    }
    $confirm = Read-Host "  Proceed? [Y/n]"
    if ($confirm -imatch '^(n|no)$') { Write-Host "Aborted."; exit 0 }
}

$nodeArgs = $nodeInput + @("--output", $outDir, "--model", $model, "--style", $style, "--concurrency", $conc)
if ($provider -eq "huggingface") {
    $nodeArgs += @("--token", $token, "--width", $w, "--height", $h)
} elseif ($provider -eq "midjourney") {
    $nodeArgs += @("--discord-token", $discordToken, "--discord-channel", $discordChannel, "--discord-guild", $discordGuild)
}
if ($prefix)                               { $nodeArgs += @("--prefix",  $prefix) }
if ($ow)                                   { $nodeArgs += "--overwrite" }
if ($dry)                                  { $nodeArgs += "--dry-run" }
if ($null -ne $seed -and "$seed" -ne "")   { $nodeArgs += @("--seed", "$seed") }

# ── Run ────────────────────────────────────────────────────────────────────────

Write-Host ""
& node "$PSScriptRoot\generate_art.mjs" @nodeArgs
exit $LASTEXITCODE
