$root = Join-Path (Get-Location) 'Mtg-Rolecards'
$cardsRoot = Join-Path $root 'Cards'
$reportPath = Join-Path $cardsRoot '_mapping_report.txt'

$categories = @('Assassins', 'Bandits', 'Guardians', 'Kings', 'Renegades')
$reportLines = @()

$reportLines += '=== ROLE CARD MATCHING VERIFICATION - FINAL REPORT ==='
$reportLines += ''
$reportLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += ''
$reportLines += '=== SUMMARY BY CATEGORY (Role Cards Only) ==='
$reportLines += ''

$totalMatched = 0
$totalCards = 0

foreach ($cat in $categories) {
  $catPath = Join-Path $cardsRoot $cat
  if (!(Test-Path $catPath)) {
    continue
  }

  $files = @(Get-ChildItem -Path $catPath -Filter '*.txt' -File | Where-Object { $_.Name -ne '_mapping_report.txt' })
  $matched = 0
  $unmatched = @()

  foreach ($f in $files) {
    $content = Get-Content -Path $f.FullName -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($content) -or $content.Trim() -eq $f.BaseName) {
      $unmatched += $f.Name
    } else {
      $matched++
    }
  }

  $total = $files.Count
  $pct = if ($total -gt 0) { [Math]::Round(($matched / $total) * 100, 1) } else { 0 }
  
  $reportLines += "$cat`: $matched / $total matched ($pct%)"
  $totalMatched += $matched
  $totalCards += $total
}

$reportLines += ''
if ($totalCards -gt 0) {
  $overallPct = [Math]::Round(($totalMatched / $totalCards) * 100, 1)
  $reportLines += "ROLE CARDS TOTAL: $totalMatched / $totalCards ($overallPct%)"
} else {
  $reportLines += 'ROLE CARDS TOTAL: 0 / 0'
}

$reportLines += ''
$reportLines += '=== MATCHING STATUS ==='
$reportLines += ''
if ($totalMatched -eq $totalCards) {
  $reportLines += '✓ ALL ROLE CARDS HAVE BEEN MATCHED AND POPULATED'
} else {
  $reportLines += "⚠ $($totalCards - $totalMatched) role cards remain unmatched"
}

Set-Content -Path $reportPath -Value $reportLines -Encoding UTF8

$reportLines
