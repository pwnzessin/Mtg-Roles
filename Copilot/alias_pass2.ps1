$root = Join-Path (Get-Location) 'Mtg-Rolecards'
$mdPath = Join-Path $root 'Cards\Role Card Proxies__.md'
$cardsRoot = Join-Path $root 'Cards'

$lines = Get-Content -Path $mdPath
$entryMap = @{}

# Parse all entries from markdown
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i].Trim()
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  if ($line -match '^#|^\[|^\*\*') { continue }

  $next = $i + 1
  while ($next -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$next].Trim())) { $next++ }
  if ($next -ge $lines.Count -or $lines[$next].Trim() -notmatch '^-|^\*') { continue }

  $title = $line.TrimEnd(':')
  $body = @($lines[$i])
  $j = $i + 1
  while ($j -lt $lines.Count) {
    $cur = $lines[$j].Trim()
    if ($cur -match '^#') { break }

    $k = $j
    while ($k -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$k].Trim())) { $k++ }
    if ($k -lt $lines.Count) {
      $cand = $lines[$k].Trim()
      $after = $k + 1
      while ($after -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$after].Trim())) { $after++ }
      if ($cand -and $cand -notmatch '^#|^\*|^-|^\[|^\*\*' -and $after -lt $lines.Count -and $lines[$after].Trim() -match '^-|^\*') {
        break
      }
    }
    $body += $lines[$j]
    $j++
  }

  if (-not $entryMap.ContainsKey($title)) {
    $entryMap[$title] = ($body -join "`r`n").Trim()
  }
}

# Manual mapping: for each unmatched file, what markdown title should be used?
$mapping = @(
  @{ File = "Assassins\el tonkodot.txt"; Title = "El Ttonkodod" },
  @{ File = "Assassins\Giantt.txt"; Title = "The Giant" },
  @{ File = "Assassins\The Abysal Prawler.txt"; Title = "The Abyssal Prowler" },
  @{ File = "Assassins\the priestess.txt"; Title = "The Priestess" },
  @{ File = "Bandits\commader supp.txt"; Title = "The Commander Support" },
  @{ File = "Bandits\the better in my deck.txt"; Title = "The It's-better-in-my-deck guy" },
  @{ File = "Bandits\The judge's nightmare .txt"; Title = "The Judge's Nightmare" },
  @{ File = "Bandits\The judge's reoccuring nightmare.txt"; Title = "The Judge's recurring Nightmare" },
  @{ File = "Bandits\The TThrash Panda.txt"; Title = "The Trash Panda" },
  @{ File = "Bandits\timebender.txt"; Title = "The Time Bender" },
  @{ File = "Guardians\duckleganger.txt"; Title = "The King's Ducklganger" },
  @{ File = "Guardians\The king's Ducklganger.txt"; Title = "The King's Ducklganger" },
  @{ File = "Kings\Seedborne Highness.txt"; Title = "Her Seedborn Highness" },
  @{ File = "Kings\The Joinker.txt"; Title = "The Yoinker" },
  @{ File = "Kings\The Twin Pricess.txt"; Title = "The Twin Princesses" },
  @{ File = "Kings\Thee Taxer.txt"; Title = "The Taxer" }
)

$updated = 0
$failed = @()

foreach ($m in $mapping) {
  $relPath = $m.File
  $title = $m.Title
  $fullPath = Join-Path $cardsRoot $relPath
  
  if (Test-Path $fullPath) {
    if ($entryMap.ContainsKey($title)) {
      Set-Content -Path $fullPath -Value $entryMap[$title] -Encoding UTF8
      $updated++
      Write-Output "Updated: $relPath -> $title"
    } else {
      $failed += "$relPath -> $title (entry not in markdown)"
    }
  } else {
    $failed += "$relPath (file not found: $fullPath)"
  }
}

Write-Output ""
Write-Output "=== Summary ==="
Write-Output "Total Updated: $updated"
Write-Output "Total Failed: $($failed.Count)"
if ($failed.Count -gt 0) {
  Write-Output ""
  Write-Output "Failed entries:"
  $failed | ForEach-Object { Write-Output "  $_" }
}