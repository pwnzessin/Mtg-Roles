$dir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Cards\Renegades'
$enc1252 = [System.Text.Encoding]::GetEncoding(1252)
$encUtf8 = [System.Text.Encoding]::UTF8

function Repair-Mojibake([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return $s }
  if ($s -notmatch '[Ãâ]') { return $s }
  try {
    return $encUtf8.GetString($enc1252.GetBytes($s))
  } catch {
    return $s
  }
}

function Normalize-Punctuation([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return $s }
  $s = $s.Replace([string][char]0x2018, "'")
  $s = $s.Replace([string][char]0x2019, "'")
  $s = $s.Replace([string][char]0x201C, '"')
  $s = $s.Replace([string][char]0x201D, '"')
  $s = $s.Replace([string][char]0x2013, '-')
  $s = $s.Replace([string][char]0x2014, '-')
  return $s
}

# Fix filenames first
Get-ChildItem -Path $dir -Filter '*.txt' -File | ForEach-Object {
  $fixedName = Normalize-Punctuation (Repair-Mojibake $_.Name)
  if ($fixedName -ne $_.Name) {
    Move-Item -Path $_.FullName -Destination (Join-Path $dir $fixedName) -Force
    Write-Output ("Renamed: " + $_.Name + " -> " + $fixedName)
  }
}

# Fix file contents
Get-ChildItem -Path $dir -Filter '*.txt' -File | ForEach-Object {
  $raw = Get-Content -Path $_.FullName -Raw
  $fixed = Normalize-Punctuation (Repair-Mojibake $raw)
  if ($fixed -ne $raw) {
    Set-Content -Path $_.FullName -Value $fixed -Encoding UTF8
    Write-Output ("Cleaned: " + $_.Name)
  }
}

Write-Output '--- Remaining filename artifacts ---'
Get-ChildItem -Path $dir -Filter '*.txt' -File |
  Where-Object { $_.Name -match 'Ã|â|�' } |
  Select-Object -ExpandProperty Name

Write-Output '--- Remaining content artifacts ---'
Select-String -Path (Join-Path $dir '*.txt') -Pattern 'Ã|â|�' -SimpleMatch:$false |
  Select-Object Path, LineNumber, Line
