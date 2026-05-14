param(
  [Parameter(Mandatory = $false)]
  [string]$ExperimentalRoot,

  [Parameter(Mandatory = $false)]
  [string]$PublicRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"

function Resolve-RepoPath([string]$root, [string]$relativePath) {
  $normalized = $relativePath -replace "/", [System.IO.Path]::DirectorySeparatorChar
  return Join-Path $root $normalized
}

$PublicRoot = (Resolve-Path $PublicRoot).Path
if (-not $ExperimentalRoot) {
  $ExperimentalRoot = Join-Path (Split-Path -Parent $PublicRoot) "Rebellion_Experimental"
}
$ExperimentalRoot = (Resolve-Path $ExperimentalRoot).Path
$allowlistPath = Join-Path $PublicRoot "tools\promote-allowlist.txt"

if (-not (Test-Path -LiteralPath $allowlistPath)) {
  throw "Missing allowlist: $allowlistPath"
}

$paths = Get-Content -LiteralPath $allowlistPath |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }

foreach ($relativePath in $paths) {
  if ($relativePath.Contains("..")) {
    throw "Refusing unsafe relative path: $relativePath"
  }

  $source = Resolve-RepoPath $ExperimentalRoot $relativePath
  $destination = Resolve-RepoPath $PublicRoot $relativePath

  if (-not (Test-Path -LiteralPath $source)) {
    throw "Missing source path: $source"
  }

  New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination -Force
  Write-Output "promoted $relativePath"
}

Write-Output "Promotion complete: $($paths.Count) file(s)."
