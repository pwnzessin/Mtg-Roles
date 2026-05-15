$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Cards\Renegades'

# Filename normalization (prefer ASCII apostrophe)
Get-ChildItem -Path $dir -Filter '*.txt' -File | ForEach-Object {
  $newName = $_.Name
  $newName = $newName.Replace('â€™', "'")
  $newName = $newName.Replace('’', "'")

  if ($newName -ne $_.Name) {
    Move-Item -Path $_.FullName -Destination (Join-Path $dir $newName) -Force
    Write-Output ("Renamed: " + $_.Name + " -> " + $newName)
  }
}

# Content normalization
$replacements = [ordered]@{
  'â€™' = "'"
  'â€œ' = '"'
  'â€' = '"'
  'â€“' = '-'
  'â€”' = '-'
  'â€¢' = '-'
  'Ã¼' = 'ü'
  'Ã¤' = 'ä'
  'Ã¶' = 'ö'
  'Ã„' = 'Ä'
  'Ã–' = 'Ö'
  'Ãœ' = 'Ü'
  'ÃŸ' = 'ß'
  '’' = "'"
  '“' = '"'
  '”' = '"'
  '–' = '-'
  '—' = '-'
}

Get-ChildItem -Path $dir -Filter '*.txt' -File | ForEach-Object {
  $raw = Get-Content -Path $_.FullName -Raw
  $new = $raw

  foreach ($k in $replacements.Keys) {
    $new = $new.Replace($k, $replacements[$k])
  }

  if ($new -ne $raw) {
    Set-Content -Path $_.FullName -Value $new -Encoding UTF8
    Write-Output ("Cleaned: " + $_.Name)
  }
}

Write-Output '--- Remaining filename artifacts ---'
Get-ChildItem -Path $dir -Filter '*.txt' -File |
  Where-Object { $_.Name -match 'â|Ã|€™|€œ|�|’' } |
  Select-Object -ExpandProperty Name

Write-Output '--- Remaining content artifacts ---'
Select-String -Path (Join-Path $dir '*.txt') -Pattern 'â€™|â€œ|â€|â€“|â€”|â€¢|Ã|�' -SimpleMatch:$false |
  Select-Object Path, LineNumber, Line
