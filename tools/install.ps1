param(
  [Parameter(Mandatory = $true)]
  [string]$GuerillaRoot,

  [Parameter(Mandatory = $false)]
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$overlayRoot = Join-Path $repoRoot "overlay"
$GuerillaRoot = (Resolve-Path $GuerillaRoot).Path
$targetApp = Join-Path $GuerillaRoot "app"

if (-not (Test-Path -LiteralPath $overlayRoot)) {
  throw "Missing overlay folder: $overlayRoot"
}

if (-not (Test-Path -LiteralPath $targetApp)) {
  throw "GuerillaRoot must contain an app folder: $GuerillaRoot"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $GuerillaRoot ".rebellion-backups\$stamp"
$files = Get-ChildItem -LiteralPath $overlayRoot -Recurse -File

foreach ($file in $files) {
  $relativePath = $file.FullName.Substring($overlayRoot.Length + 1)
  $destination = Join-Path $GuerillaRoot $relativePath

  if ($WhatIf) {
    Write-Output "would install $relativePath"
    continue
  }

  if (Test-Path -LiteralPath $destination) {
    $backup = Join-Path $backupRoot $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    Copy-Item -LiteralPath $destination -Destination $backup -Force
  }

  New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
  Write-Output "installed $relativePath"
}

if (-not $WhatIf) {
  Write-Output "Installed $($files.Count) file(s). Backup: $backupRoot"
}
