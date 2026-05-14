$root = Join-Path (Get-Location) 'Mtg-Rolecards'
$cardsRoot = Join-Path $root 'Cards'
$reportPath = Join-Path $cardsRoot '_mapping_report.txt'

$categories = @('Assassins', 'Bandits', 'Guardians', 'Kings', 'Renegades')
$reportLines = @()

$reportLines += '=== ROLE CARD MATCHING VERIFICATION REPORT ==='
$reportLines += ''
$reportLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += ''
$reportLines += '=== SUMMARY BY CATEGORY ==='
$reportLines += ''

$totalMatched = 0
$totalCards = 0
$allUnmatched = @()

foreach ($cat in $categories) {
  $catPath = Join-Path $cardsRoot $cat
  if (!(Test-Path $catPath)) {
    $reportLines += "$cat`: [FOLDER NOT FOUND]"
    continue
  }

  $files = @(Get-ChildItem -Path $catPath -Filter '*.txt' -File | Where-Object { $_.Name -ne '_mapping_report.txt' })
  $matched = 0
  $unmatched = @()

  foreach ($f in $files) {
    $content = (Get-Content -Path $f.FullName -Raw).Trim()
    # If content is non-empty and different from just the filename, it's matched
    if ($content -and $content -ne $f.BaseName) {
      $matched++
    } else {
      $unmatched += $f.Name
    }
  }

  $total = $files.Count
  $pct = if ($total -gt 0) { [Math]::Round(($matched / $total) * 100, 1) } else { 0 }
  
  $reportLines += "$cat`: $matched / $total ($pct%)"
  $totalMatched += $matched
  $totalCards += $total

  if ($unmatched.Count -gt 0) {
    $allUnmatched += @{ Category = $cat; Files = $unmatched }
  }
}

$reportLines += ''
$reportLines += "TOTAL: $totalMatched / $totalCards ($([Math]::Round(($totalMatched / $totalCards) * 100, 1))%)"
$reportLines += ''
$reportLines += '=== UNMATCHED CARDS BY CATEGORY ==='
$reportLines += ''

if ($allUnmatched.Count -eq 0) {
  $reportLines += 'All role cards have been successfully matched!'
} else {
  foreach ($item in $allUnmatched) {
    $reportLines += "$($item.Category): ($($item.Files.Count) unmatched)"
    $item.Files | Sort-Object | ForEach-Object { $reportLines += "  - $_" }
    $reportLines += ''
  }
}

Set-Content -Path $reportPath -Value $reportLines -Encoding UTF8

# Display report
$reportLines | ForEach-Object { Write-Output $_ }
