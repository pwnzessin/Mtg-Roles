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
    [string]$Foil         = "",
    [string]$Mode         = "",   # "Manual" or "RoleCard"; empty = interactive
    [string]$Roles        = "",   # "A" or comma-separated names e.g. "Assassins,Kings"; empty = interactive
    [string]$TemplatesRoot = "",  # root folder containing per-role sub-folders; empty = auto-detect
    [string]$CardbacksDir  = "",  # folder scanned for cardback images; empty = auto-detect
    [string]$AutofillDir   = "",  # default output folder for the XML file; empty = auto-detect
    [string]$Recurse       = ""   # "true" / "false"; empty = interactive prompt in Manual mode
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

function Resolve-RelPath([string]$Base, [string]$Value) {
    # Returns $Value unchanged when empty or already absolute;
    # otherwise resolves it relative to $Base.
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if ([System.IO.Path]::IsPathRooted($Value)) { return $Value }
    return [System.IO.Path]::GetFullPath((Join-Path $Base $Value))
}

# ---------------------------------------------------------------------------
# Collect inputs
# ---------------------------------------------------------------------------
$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))

# Resolve any relative path parameters against the workspace root.
$TemplatesRoot = Resolve-RelPath $workspaceRoot $TemplatesRoot
$CardbackPath  = Resolve-RelPath $workspaceRoot $CardbackPath
$CardbacksDir  = Resolve-RelPath $workspaceRoot $CardbacksDir
$AutofillDir   = Resolve-RelPath $workspaceRoot $AutofillDir
$OutputXml     = Resolve-RelPath $workspaceRoot $OutputXml

Write-Host ""
Write-Host "=== MPC Autofill XML Generator ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Mode selection
# ---------------------------------------------------------------------------
$modeOptions = @(
    "Manual   - specify a folder",
    "RoleCard - pick one or more roles, combine into one XML"
)
if (-not [string]::IsNullOrWhiteSpace($Mode)) {
    $modeAnswer = if ($Mode -eq "RoleCard") { "RoleCard" } else { "Manual" }
} else {
    $modeAnswer = Prompt-Choice "Select mode:" $modeOptions 0
}
$roleCardMode  = ($modeAnswer -like "RoleCard*")
$defaultXmlName = "order.xml"

# ---------------------------------------------------------------------------
# Collect images
# ---------------------------------------------------------------------------
$imageExts = @("*.png", "*.jpg", "*.jpeg")
$images    = @()

if ($roleCardMode) {
    # Discover role folders that actually exist
    if ([string]::IsNullOrWhiteSpace($TemplatesRoot)) {
        $TemplatesRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\Cards\templates"))
    }
    $knownRoles    = @("Assassins", "Bandits", "Guardians", "Kings", "Renegades")
    $availableRoles = $knownRoles | Where-Object { Test-Path (Join-Path $TemplatesRoot $_) -PathType Container }

    if ($availableRoles.Count -eq 0) {
        Write-Error "No role folders found under: $TemplatesRoot"; exit 1
    }

    Write-Host ""
    Write-Host "Available roles:"
    for ($r = 0; $r -lt $availableRoles.Count; $r++) {
        Write-Host ("  {0}. {1}" -f ($r + 1), $availableRoles[$r])
    }
    Write-Host ("  A. All roles")
    if (-not [string]::IsNullOrWhiteSpace($Roles)) {
        $roleRaw = $Roles
    } else {
        $roleRaw = Read-Host "Select roles (comma-separated numbers, e.g. 1,3 -- or A for all)"
    }

    $selectedRoles = @()
    if ($roleRaw -match "^[Aa]$") {
        $selectedRoles = $availableRoles
    } else {
        foreach ($tok in ($roleRaw -split ',')) {
            $tok = $tok.Trim()
            # Accept role name directly (from GUI) or numeric index (interactive)
            if ($availableRoles -contains $tok) {
                $selectedRoles += $tok
            } else {
                $rIdx = [int]$tok - 1
                if ($rIdx -ge 0 -and $rIdx -lt $availableRoles.Count) {
                    $selectedRoles += $availableRoles[$rIdx]
                } else {
                    Write-Warning "Ignored invalid selection: '$tok'"
                }
            }
        }
    }

    if ($selectedRoles.Count -eq 0) {
        Write-Error "No valid roles selected."; exit 1
    }
    Write-Host ("Selected roles: {0}" -f ($selectedRoles -join ", ")) -ForegroundColor Green

    foreach ($role in $selectedRoles) {
        $roleFolder = Join-Path $TemplatesRoot $role
        foreach ($ext in $imageExts) {
            $images += Get-ChildItem -Path $roleFolder -Filter $ext -File -ErrorAction SilentlyContinue
        }
    }
    $images = $images | Sort-Object FullName

    if ($images.Count -eq 0) {
        Write-Error "No PNG/JPG images found in the selected role folders."; exit 1
    }
    Write-Host ("Found {0} image(s) across {1} role(s)." -f $images.Count, $selectedRoles.Count) -ForegroundColor Green
    $defaultXmlName = ("RoleCards_{0}.xml" -f ($selectedRoles -join "_"))

} else {
    # --- Manual mode ---
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
    $doRecurse = $false
    if (-not [string]::IsNullOrWhiteSpace($Recurse)) {
        $doRecurse = ($Recurse.ToLowerInvariant() -eq "true")
    } else {
        $recurseAnswer = Read-Host "Include sub-folders? (Y/N, default N)"
        if ($recurseAnswer -match "^[Yy]$") { $doRecurse = $true }
    }

    foreach ($ext in $imageExts) {
        if ($doRecurse) {
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
}

# Cardback
if ([string]::IsNullOrWhiteSpace($CardbackPath)) {
    $scriptRoot    = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ([string]::IsNullOrWhiteSpace($CardbacksDir)) {
        $CardbacksDir = Join-Path $scriptRoot "..\..\Cards\Cardbacks"
    }
    $cardbackFiles = @()
    if (Test-Path $CardbacksDir -PathType Container) {
        $cardbackFiles = @(Get-ChildItem -Path (Join-Path $CardbacksDir "*") -Include "*.png","*.jpg","*.jpeg" -File |
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
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($AutofillDir)) {
    $AutofillDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\Autofill"))
}
if ([string]::IsNullOrWhiteSpace($OutputXml)) {
    $defaultXml = Join-Path $AutofillDir $defaultXmlName
    Write-Host ""
    Write-Host "Output XML path (default: $defaultXml)"
    $OutputXml = Read-Host "Output XML"
    if ([string]::IsNullOrWhiteSpace($OutputXml)) { $OutputXml = $defaultXml }
}
# Ensure .xml extension
if ([System.IO.Path]::GetExtension($OutputXml) -eq "") {
    $OutputXml = $OutputXml + ".xml"
}
# If no directory specified, place in AutofillDir folder
if ([System.IO.Path]::GetDirectoryName($OutputXml) -eq "") {
    $OutputXml = Join-Path $AutofillDir $OutputXml
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
