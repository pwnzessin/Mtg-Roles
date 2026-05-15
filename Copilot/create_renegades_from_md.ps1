$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$cards = Join-Path $root 'Cards'
$renList = Join-Path $cards 'renegades_to_create.md'
$md = Join-Path $cards 'Role Card Proxies__.md'
$renDir = Join-Path $cards 'Renegades'

if (-not (Test-Path $renDir)) {
  New-Item -ItemType Directory -Path $renDir | Out-Null
}

$targets = Get-Content -Path $renList -Encoding Default | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$lines = Get-Content -Path $md -Encoding Default

function Normalize-Key([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  $x = $s.ToLowerInvariant()
  $x = $x -replace '[’‘`''"]', ''
  $x = $x -replace '[^a-z0-9]+', ' '
  $x = ($x -replace '\s+', ' ').Trim()
  return $x
}

$targetNormSet = @{}
foreach ($t in $targets) {
  $targetNormSet[(Normalize-Key $t)] = $true
}

$startIndexByNorm = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i].Trim().TrimEnd(':')
  if ($line -eq '' -or $line -match '^#') { continue }

  $nline = Normalize-Key $line
  if ($targetNormSet.ContainsKey($nline) -and -not $startIndexByNorm.ContainsKey($nline)) {
    $startIndexByNorm[$nline] = $i
  }
}

$allStarts = $startIndexByNorm.Values | Sort-Object

function Get-EntryContentByStart([int]$start, [int[]]$starts, [string[]]$srcLines) {
  $end = $srcLines.Count - 1
  foreach ($s in $starts) {
    if ($s -gt $start) {
      $end = $s - 1
      break
    }
  }

  $slice = @()
  for ($j = $start; $j -le $end; $j++) {
    if ($srcLines[$j].Trim() -match '^#') { break }
    $slice += $srcLines[$j]
  }

  while ($slice.Count -gt 0 -and $slice[$slice.Count - 1].Trim() -eq '') {
    $slice = $slice[0..($slice.Count - 2)]
  }

  return (($slice -join "`n").Trim())
}

$matched = 0
$unmatched = @()

foreach ($name in $targets) {
  $filePath = Join-Path $renDir ($name + '.txt')
  $content = $null

  $k = Normalize-Key $name
  if ($startIndexByNorm.ContainsKey($k)) {
    $start = [int]$startIndexByNorm[$k]
    $content = Get-EntryContentByStart -start $start -starts $allStarts -srcLines $lines
  } else {
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $raw = $lines[$i].Trim().TrimEnd(':')
      if ($raw -eq '' -or $raw -match '^#') { continue }
      $nraw = Normalize-Key $raw

      $next = $i + 1
      while ($next -lt $lines.Count -and $lines[$next].Trim() -eq '') { $next++ }
      if ($next -ge $lines.Count -or $lines[$next].Trim() -notmatch '^[-•]') { continue }

      if ($nraw -like ("*" + $k + "*") -or $k -like ("*" + $nraw + "*")) {
        $content = Get-EntryContentByStart -start $i -starts ($allStarts + @($i) | Sort-Object -Unique) -srcLines $lines
        break
      }
    }
  }

  if ($content) {
    Set-Content -Path $filePath -Value $content -Encoding UTF8
    $matched++
    Write-Output ("Matched: " + $name)
  }
  else {
    Set-Content -Path $filePath -Value $name -Encoding UTF8
    $unmatched += $name
    Write-Output ("Unmatched: " + $name)
  }
}

Write-Output ''
Write-Output ("Created files: " + $targets.Count)
Write-Output ("Matched content: " + $matched)
Write-Output ("Unmatched: " + $unmatched.Count)
if ($unmatched.Count -gt 0) {
  Write-Output 'Missing entries:'
  $unmatched | ForEach-Object { Write-Output (" - " + $_) }
}
