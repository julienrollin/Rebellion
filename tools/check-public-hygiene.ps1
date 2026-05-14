$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$forbiddenDirs = @(
  ".agent-backups",
  "agent",
  "artifacts",
  "plans",
  "research",
  "share",
  "src",
  "tests"
)
$forbiddenPatterns = @(
  ("S:" + "/softwares"),
  ("S:" + "\softwares"),
  "Agent_dev",
  ("Awesome" + "_Guerilla"),
  "guerilla_DEV",
  "decomp",
  "ghidra",
  "cdb_",
  "memory_cli"
)

$errors = New-Object System.Collections.Generic.List[string]

foreach ($dir in $forbiddenDirs) {
  $path = Join-Path $repoRoot $dir
  if (Test-Path -LiteralPath $path) {
    $errors.Add("forbidden directory exists: $dir")
  }
}

$files = Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force |
  Where-Object { $_.FullName -notmatch "\\.git\\" }

foreach ($file in $files) {
  $relativeName = $file.FullName.Substring($repoRoot.Length + 1)
  if ($relativeName -eq "tools\check-public-hygiene.ps1") {
    continue
  }

  if ($file.Length -gt 10MB) {
    $errors.Add("large file over 10MB: $relativeName")
  }

  $ext = [System.IO.Path]::GetExtension($file.Name).ToLowerInvariant()
  if ($ext -in @(".lua", ".ps1", ".md", ".txt", ".json")) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in $forbiddenPatterns) {
      if ($text.Contains($pattern)) {
        $errors.Add("forbidden text '$pattern' in $relativeName")
      }
    }
  }
}

if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_ }
  throw "Public hygiene check failed with $($errors.Count) issue(s)."
}

Write-Output "public_hygiene_ok"
