$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$projectRoot = Join-Path $root 'Mtg-Rolecards'
if (Test-Path (Join-Path $PSScriptRoot 'Role Card Proxies__.md')) {
  $projectRoot = Split-Path -Parent $PSScriptRoot
}

$mdPath = Join-Path $projectRoot 'Cards\Role Card Proxies__.md'
$artRoot = Join-Path $projectRoot 'Artworks'
$cardsRoot = Join-Path $projectRoot 'Cards'
$reportPath = Join-Path $cardsRoot '_mapping_report.txt'

function Normalize-Key {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
  $s = $Text.ToLowerInvariant()
  $s = $s -replace '[^a-z0-9]+', ' '
  $s = ($s -replace '\s+', ' ').Trim()
  return $s
}

function Next-NonEmptyIndex {
  param(
    [string[]]$Lines,
    [int]$Start
  )
  $i = $Start
  while ($i -lt $Lines.Count) {
    if (-not [string]::IsNullOrWhiteSpace($Lines[$i])) { return $i }
    $i++
  }
  return -1
}

function Is-NonEntry-Line {
  param([string]$Line)
  if ([string]::IsNullOrWhiteSpace($Line)) { return $true }
  $t = $Line.Trim()
  return ($t -match '^#' -or $t -match '^\[' -or $t -match '^\*\*' -or $t -match '^Regeln:' -or $t -match '^Win Cons:' -or $t -match '^Idee:' -or $t -match '^Updates:')
}

function Is-BulletOrRuleLine {
  param([string]$Line)
  if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
  $t = $Line.Trim()
  return ($t -match '^-|^\*|^\+' -or $t -match '^Unveil' -or $t -match '^At the beginning' -or $t -match '^Whenever' -or $t -match '^If ' -or $t -match '^Then ')
}

$lines = Get-Content -Path $mdPath
$entries = @()

for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i].Trim()

  if (Is-NonEntry-Line $line) { continue }
  if ($line -match '^\\\*') { continue }
  if ($line -match '^\.|^\(|^\{|^\d') { continue }

  $next = Next-NonEmptyIndex -Lines $lines -Start ($i + 1)
  if ($next -lt 0) { continue }

  if (-not (Is-BulletOrRuleLine $lines[$next])) { continue }

  $title = $line.TrimEnd(':')

  $body = @($lines[$i])
  $j = $i + 1
  while ($j -lt $lines.Count) {
    $cur = $lines[$j].Trim()
    if ($cur -match '^#') { break }

    $candidateIdx = Next-NonEmptyIndex -Lines $lines -Start $j
    if ($candidateIdx -ge 0) {
      $candidate = $lines[$candidateIdx].Trim()
      $candidateNext = Next-NonEmptyIndex -Lines $lines -Start ($candidateIdx + 1)
      if ($candidateNext -ge 0) {
        if (-not (Is-NonEntry-Line $candidate) -and (Is-BulletOrRuleLine $lines[$candidateNext])) {
          break
        }
      }
    }

    $body += $lines[$j]
    $j++
  }

  $key = Normalize-Key $title
  if ([string]::IsNullOrWhiteSpace($key)) { continue }

  $entries += [PSCustomObject]@{
    Title = $title
    Key = $key
    Text = ($body -join "`r`n").Trim()
  }
}

# Include escaped-star legacy entries too
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i].Trim()
  if ($line -notmatch '^\\\*(.+)$') { continue }

  $title = $matches[1].Trim().TrimEnd(':')
  $body = @($lines[$i])
  $j = $i + 1
  while ($j -lt $lines.Count) {
    $cur = $lines[$j].Trim()
    if ($cur -match '^\\\*' -or $cur -match '^#') { break }
    $body += $lines[$j]
    $j++
  }

  $key = Normalize-Key $title
  if ([string]::IsNullOrWhiteSpace($key)) { continue }

  $entries += [PSCustomObject]@{
    Title = $title
    Key = $key
    Text = ($body -join "`r`n").Trim()
  }
}

$entryMap = @{}
foreach ($e in $entries) {
  if (-not $entryMap.ContainsKey($e.Key)) {
    $entryMap[$e.Key] = $e.Text
  }
}

function Build-CandidateKeys {
  param([string]$BaseName)
  $noUuid = $BaseName -replace '_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$', ''
  $noPrefix = $noUuid -replace '^oreeeobot_', ''
  @(
    (Normalize-Key $BaseName),
    (Normalize-Key $noUuid),
    (Normalize-Key $noPrefix)
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
}

function Get-LevenshteinDistance {
  param(
    [string]$A,
    [string]$B
  )

  if ($A -eq $B) { return 0 }
  if ([string]::IsNullOrEmpty($A)) { return $B.Length }
  if ([string]::IsNullOrEmpty($B)) { return $A.Length }

  $n = $A.Length
  $m = $B.Length
  $d = New-Object 'int[,]' ($n + 1), ($m + 1)

  for ($i = 0; $i -le $n; $i++) { $d[$i, 0] = $i }
  for ($j = 0; $j -le $m; $j++) { $d[0, $j] = $j }

  for ($i = 1; $i -le $n; $i++) {
    for ($j = 1; $j -le $m; $j++) {
      $cost = 1
      if ($A[$i - 1] -eq $B[$j - 1]) { $cost = 0 }

      $delete = $d[($i - 1), $j] + 1
      $insert = $d[$i, ($j - 1)] + 1
      $sub = $d[($i - 1), ($j - 1)] + $cost

      $min = [Math]::Min($delete, $insert)
      $min = [Math]::Min($min, $sub)
      $d[$i, $j] = $min
    }
  }

  return $d[$n, $m]
}

function Get-TokenOverlap {
  param(
    [string]$A,
    [string]$B
  )

  $aTokens = $A.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_.Length -ge 3 }
  $bTokens = $B.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_.Length -ge 3 }

  if ($aTokens.Count -eq 0 -or $bTokens.Count -eq 0) { return 0 }

  $setA = [System.Collections.Generic.HashSet[string]]::new([string[]]$aTokens)
  $setB = [System.Collections.Generic.HashSet[string]]::new([string[]]$bTokens)

  $intersection = 0
  foreach ($t in $setA) {
    if ($setB.Contains($t)) { $intersection++ }
  }

  $denom = [Math]::Max($setA.Count, $setB.Count)
  if ($denom -eq 0) { return 0 }
  return ($intersection / $denom)
}

$imgExt = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.tif', '.tiff', '.svg')
$images = Get-ChildItem -Path $artRoot -Recurse -File | Where-Object { $imgExt -contains $_.Extension.ToLowerInvariant() }

$matched = 0
$unmatched = 0
$unmatchedFiles = @()

foreach ($img in $images) {
  $relativeDir = $img.DirectoryName.Substring($artRoot.Length).TrimStart('\\')
  $txtDir = Join-Path $cardsRoot $relativeDir
  $txtName = [System.IO.Path]::GetFileNameWithoutExtension($img.Name) + '.txt'
  $txtPath = Join-Path $txtDir $txtName

  if (-not (Test-Path $txtPath)) { continue }

  $base = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
  $cand = Build-CandidateKeys -BaseName $base

  $entry = $null

  foreach ($k in $cand) {
    if ($entryMap.ContainsKey($k)) {
      $entry = $entryMap[$k]
      break
    }
  }

  if (-not $entry) {
    foreach ($k in $entryMap.Keys) {
      foreach ($c in $cand) {
        if ($k.Contains($c) -or $c.Contains($k)) {
          $entry = $entryMap[$k]
          break
        }
      }
      if ($entry) { break }
    }
  }

  if (-not $entry) {
    $bestKey = $null
    $bestDistance = 9999
    $bestOverlap = 0.0

    foreach ($k in $entryMap.Keys) {
      foreach ($c in $cand) {
        $overlap = Get-TokenOverlap -A $k -B $c
        if ($overlap -lt 0.4) { continue }

        $dist = Get-LevenshteinDistance -A $k -B $c

        if ($dist -lt $bestDistance -or ($dist -eq $bestDistance -and $overlap -gt $bestOverlap)) {
          $bestDistance = $dist
          $bestOverlap = $overlap
          $bestKey = $k
        }
      }
    }

    if ($bestKey) {
      if ($bestDistance -le 3 -or ($bestDistance -le 5 -and $bestOverlap -ge 0.75)) {
        $entry = $entryMap[$bestKey]
      }
    }
  }

  if ($entry) {
    Set-Content -Path $txtPath -Value $entry -Encoding UTF8
    $matched++
  }
  else {
    $unmatched++
    $unmatchedFiles += $txtPath
  }
}

$reportLines = @(
  "EntriesParsed=$($entryMap.Count)",
  "Images=$($images.Count)",
  "MatchedTxt=$matched",
  "UnmatchedTxt=$unmatched",
  '',
  'Unmatched:'
) + $unmatchedFiles
Set-Content -Path $reportPath -Value $reportLines -Encoding UTF8

Write-Output "EntriesParsed=$($entryMap.Count)"
Write-Output "Images=$($images.Count)"
Write-Output "MatchedTxt=$matched"
Write-Output "UnmatchedTxt=$unmatched"
Write-Output "Report=$reportPath"