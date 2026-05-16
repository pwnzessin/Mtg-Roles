<#
.SYNOPSIS
    Generates an MPC Autofill XML order file from a folder of card images.
.DESCRIPTION
    Scans a folder for PNG/JPG images and produces an XML file compatible with
    the MPC Autofill desktop tool (https://github.com/chilli-axe/mpc-autofill).
    Each image is assigned one slot. Supports an optional cardback image.
.EXAMPLE
    .\Generate-MpcFillXml.ps1
    # Interactive mode - prompts for all settings.
.EXAMPLE
    .\Generate-MpcFillXml.ps1 -InputFolder "..\..\Cards\templates\Assassins" -CardbackPath "..\..\Cards\templates\Artwork.png" -OutputXml ".\Assassins_order.xml"
#>
param(
    [string]$InputFolder  = "",
    [string]$CardbackPath = "",
    [string]$OutputXml    = "",
    [string]$Stock        = "",
    [string]$Foil         = ""
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Prompt-Choice {
    param([string]$Prompt, [string[]]$Options, [int]$Default = 0)
    Write-Host ""
    Write-Host $Prompt
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { "[default]" } else { "" }
        Write-Host ("  {0}. {1} {2}" -f ($i + 1), $Options[$i], $marker)
    }
    $raw = Read-Host "Choice (default $($Default + 1))"
    if ([string]::IsNullOrWhiteSpace($raw)) { return $Options[$Default] }
    $idx = [int]$raw - 1
    if ($idx -ge 0 -and $idx -lt $Options.Count) { return $Options[$idx] }
    Write-Warning "Invalid choice, using default."
    return $Options[$Default]
}

function Escape-Xml([string]$s) {
    $s = $s -replace '&',  '&amp;'
    $s = $s -replace '<',  '&lt;'
    $s = $s -replace '>',  '&gt;'
    $s = $s -replace '"',  '&quot;'
    $s = $s -replace "'",  '&apos;'
    return $s
}

# ---------------------------------------------------------------------------
# Collect inputs
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== MPC Autofill XML Generator ===" -ForegroundColor Cyan

# Input folder
if ([string]::IsNullOrWhiteSpace($InputFolder)) {
    Write-Host ""
    Write-Host "Enter the folder containing card images (PNG/JPG)."
    Write-Host "Example: ..\..\Cards\templates\Assassins"
    $InputFolder = Read-Host "Input folder"
}
$InputFolder = (Resolve-Path $InputFolder).Path
if (-not (Test-Path $InputFolder -PathType Container)) {
    Write-Error "Folder not found: $InputFolder"; exit 1
}

# Recursive?
$recurse = $false
$recurseAnswer = Read-Host "Include sub-folders? (Y/N, default N)"
if ($recurseAnswer -match "^[Yy]$") { $recurse = $true }

# Collect images
$imageExts = @("*.png", "*.jpg", "*.jpeg")
$images = @()
foreach ($ext in $imageExts) {
    if ($recurse) {
        $images += Get-ChildItem -Path $InputFolder -Filter $ext -Recurse -File
    } else {
        $images += Get-ChildItem -Path $InputFolder -Filter $ext -File
    }
}
$images = $images | Sort-Object FullName

if ($images.Count -eq 0) {
    Write-Error "No PNG/JPG images found in: $InputFolder"; exit 1
}
Write-Host ("Found {0} image(s)." -f $images.Count) -ForegroundColor Green

# Cardback
if ([string]::IsNullOrWhiteSpace($CardbackPath)) {
    $scriptRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
    $cardbacksDir  = Join-Path $scriptRoot "..\..\Cards\Cardbacks"
    $cardbackFiles = @()
    if (Test-Path $cardbacksDir -PathType Container) {
        $cardbackFiles = @(Get-ChildItem -Path (Join-Path $cardbacksDir "*") -Include "*.png","*.jpg","*.jpeg" -File |
            Sort-Object Name)
    }

    Write-Host ""
    if ($cardbackFiles.Count -gt 0) {
        Write-Host "Select a cardback image:"
        for ($ci = 0; $ci -lt $cardbackFiles.Count; $ci++) {
            Write-Host ("  {0}. {1}" -f ($ci + 1), $cardbackFiles[$ci].Name)
        }
        Write-Host ("  {0}. Skip (no cardback)" -f ($cardbackFiles.Count + 1))
        Write-Host ("  {0}. Enter path manually" -f ($cardbackFiles.Count + 2))
        $cbRaw = Read-Host "Choice (default 1)"
        if ([string]::IsNullOrWhiteSpace($cbRaw)) { $cbRaw = "1" }
        $cbIdx = [int]$cbRaw - 1
        if ($cbIdx -ge 0 -and $cbIdx -lt $cardbackFiles.Count) {
            $CardbackPath = $cardbackFiles[$cbIdx].FullName
        } elseif ($cbIdx -eq $cardbackFiles.Count) {
            $CardbackPath = ""
        } else {
            Write-Host "Enter path to the cardback image (leave blank to skip)."
            $CardbackPath = Read-Host "Cardback image"
        }
    } else {
        Write-Host "Enter path to the cardback image (leave blank to skip)."
        $CardbackPath = Read-Host "Cardback image"
    }
}
if (-not [string]::IsNullOrWhiteSpace($CardbackPath)) {
    $resolved = Resolve-Path $CardbackPath -ErrorAction SilentlyContinue
    $CardbackPath = if ($resolved) { $resolved.Path } else { "" }
    if ([string]::IsNullOrWhiteSpace($CardbackPath) -or -not (Test-Path $CardbackPath)) {
        Write-Warning "Cardback path not found - will be omitted from XML."
        $CardbackPath = ""
    }
}

# Cardstock
$stockOptions = @(
    "(S30) Standard Smooth",
    "(S33) Superior Smooth",
    "(M31) Linen",
    "(P10) Plastic"
)
if ([string]::IsNullOrWhiteSpace($Stock)) {
    $Stock = Prompt-Choice "Select cardstock:" $stockOptions 0
}

# Foil
if ([string]::IsNullOrWhiteSpace($Foil)) {
    $foilAnswer = Read-Host "Foil fronts? (Y/N, default N)"
    $Foil = if ($foilAnswer -match "^[Yy]$") { "true" } else { "false" }
}
$Foil = $Foil.ToLowerInvariant()
if ($Foil -notin @("true","false")) { $Foil = "false" }

# Output path
if ([string]::IsNullOrWhiteSpace($OutputXml)) {
    $autofillDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\Autofill"))
    $defaultXml  = Join-Path $autofillDir "order.xml"
    Write-Host ""
    Write-Host "Output XML path (default: $defaultXml)"
    $OutputXml = Read-Host "Output XML"
    if ([string]::IsNullOrWhiteSpace($OutputXml)) { $OutputXml = $defaultXml }
}

# ---------------------------------------------------------------------------
# Build XML
# ---------------------------------------------------------------------------
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
[void]$sb.AppendLine('<order>')
[void]$sb.AppendLine('    <details>')
[void]$sb.AppendLine("        <quantity>$($images.Count)</quantity>")
[void]$sb.AppendLine("        <stock>$(Escape-Xml $Stock)</stock>")
[void]$sb.AppendLine("        <foil>$Foil</foil>")
[void]$sb.AppendLine('    </details>')
[void]$sb.AppendLine('    <fronts>')

for ($i = 0; $i -lt $images.Count; $i++) {
    $img  = $images[$i]
    $id   = Escape-Xml $img.FullName
    $name = Escape-Xml $img.Name
    [void]$sb.AppendLine('        <card>')
    [void]$sb.AppendLine("            <id>$id</id>")
    [void]$sb.AppendLine('            <sourceType>Local File</sourceType>')
    [void]$sb.AppendLine("            <slots>$i</slots>")
    [void]$sb.AppendLine("            <name>$name</name>")
    [void]$sb.AppendLine('        </card>')
}

[void]$sb.AppendLine('    </fronts>')

if (-not [string]::IsNullOrWhiteSpace($CardbackPath)) {
    [void]$sb.AppendLine("    <cardback>$(Escape-Xml $CardbackPath)</cardback>")
}

[void]$sb.AppendLine('</order>')

# ---------------------------------------------------------------------------
# Write file
# ---------------------------------------------------------------------------
$xmlDir = Split-Path $OutputXml -Parent
if ($xmlDir -and -not (Test-Path $xmlDir)) {
    New-Item -ItemType Directory -Path $xmlDir -Force | Out-Null
}

[System.IO.File]::WriteAllText($OutputXml, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "XML written: $OutputXml" -ForegroundColor Green
Write-Host ("Cards: {0}  |  Stock: {1}  |  Foil: {2}" -f $images.Count, $Stock, $Foil) -ForegroundColor Cyan
if (-not [string]::IsNullOrWhiteSpace($CardbackPath)) {
    Write-Host "Cardback: $CardbackPath" -ForegroundColor Cyan
} else {
    Write-Host "Cardback: (none specified)" -ForegroundColor Yellow
}
