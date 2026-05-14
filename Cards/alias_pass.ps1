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

# Manual aliases for known typos
$aliases = @{
  'Assassins\el tonkodot.txt' = 'El Ttonkodod';
  'Assassins\Giantt.txt' = 'The Giant';
  'Assassins\The Abysal Prawler.txt' = 'The Abyssal Prowler';
  'Assassins\the priestess.txt' = 'The Priestess';
  'Bandits\commader supp.txt' = 'The Commander Support';
  'Bandits\the better in my deck.txt' = "The It's-better-in-my-deck guy";
  'Bandits\The judge''s nightmare .txt' = 'The Judge''s Nightmare';
  'Bandits\The judge''s reoccuring nightmare.txt' = 'The Judge''s recurring Nightmare';
  'Guardians\The king''s Ducklganger.txt' = 'The King''s Ducklganger';
  'Kings\Seedborne Highness.txt' = 'Her Seedborn Highness';
  'Kings\The Joinker.txt' = 'The Yoinker';
  'Kings\The Twin Pricess.txt' = 'The Twin Princesses';
  'Kings\Thee Taxer.txt' = 'The Taxer';
}

$updated = 0
$failed = @()

foreach ($rel in $aliases.Keys) {
  $path = Join-Path $cardsRoot $rel
  $title = $aliases[$rel]
  
  if (Test-Path $path) {
    if ($entryMap.ContainsKey($title)) {
      Set-Content -Path $path -Value $entryMap[$title] -Encoding UTF8
      $updated++
      Write-Output "Updated: $rel -> $title"
    } else {
      $failed += "$rel -> $title (entry not in markdown)"
    }
  } else {
    $failed += "$rel (file not found)"
  }
}

Write-Output ""
Write-Output "AliasesUpdated=$updated"
if ($failed.Count -gt 0) {
  Write-Output "Failed=$($failed.Count)"
  Write-Output "Details:"
  $failed | ForEach-Object { Write-Output "  $_" }
}