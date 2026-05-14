$root = Join-Path (Get-Location) 'Mtg-Rolecards'
$cardsRoot = Join-Path $root 'Cards'
$reportPath = Join-Path $cardsRoot '_mapping_report.txt'

$categories = @('Assassins', 'Bandits', 'Guardians', 'Kings', 'Renegades')
$reportLines = @()

$reportLines += '╔════════════════════════════════════════════════════════════╗'
$reportLines += '║   ROLE CARD MATCHING VERIFICATION - COMPREHENSIVE REPORT  ║'
$reportLines += '╚════════════════════════════════════════════════════════════╝'
$reportLines += ''
$reportLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += ''

$totalMatched = 0
$totalCards = 0
$allMatched = @()

foreach ($cat in $categories) {
  $catPath = Join-Path $cardsRoot $cat
  if (!(Test-Path $catPath)) {
    continue
  }

  $files = @(Get-ChildItem -Path $catPath -Filter '*.txt' -File | Where-Object { $_.Name -ne '_mapping_report.txt' })
  $matched = 0
  $matchedFiles = @()

  foreach ($f in $files) {
    $content = Get-Content -Path $f.FullName -ErrorAction SilentlyContinue
    if (![string]::IsNullOrEmpty($content) -and $content.Trim() -ne $f.BaseName) {
      $matched++
      $matchedFiles += $f.Name
    }
  }

  $total = $files.Count
  $pct = if ($total -gt 0) { [Math]::Round(($matched / $total) * 100, 1) } else { 0 }
  
  $reportLines += "═ $cat ════════════════════════════════════════════════════════"
  $reportLines += "Matched: $matched / $total ($pct%)"
  if ($matchedFiles.Count -gt 0) {
    $matchedFiles | Sort-Object | ForEach-Object { 
      $reportLines += "  ✓ $_"
      $allMatched += "$cat\$_"
    }
  }
  $reportLines += ''
  
  $totalMatched += $matched
  $totalCards += $total
}

$reportLines += ''
$reportLines += '═════════════════════════════════════════════════════════════'
if ($totalCards -gt 0) {
  $overallPct = [Math]::Round(($totalMatched / $totalCards) * 100, 1)
  $reportLines += "TOTAL ROLE CARDS MATCHED: $totalMatched / $totalCards ($overallPct%)"
} else {
  $reportLines += 'TOTAL ROLE CARDS MATCHED: 0 / 0'
}
$reportLines += ''

if ($totalMatched -eq $totalCards -and $totalCards -gt 0) {
  $reportLines += '✓✓✓ SUCCESS: ALL ROLE CARDS HAVE BEEN MATCHED ✓✓✓'
} else {
  $reportLines += "⚠  STATUS: $($totalCards - $totalMatched) role cards remain unmatched"
}

Set-Content -Path $reportPath -Value $reportLines -Encoding UTF8

$reportLines
