#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

param(
  [string]$CodexHome = $env:CODEX_HOME
)

function Convert-ToTomlString {
  param([Parameter(Mandatory = $true)][string]$Value)
  $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
  return '"' + $escaped + '"'
}

function Resolve-BashPath {
  $fromPath = Get-Command bash -ErrorAction SilentlyContinue
  if ($fromPath -and $fromPath.Source) {
    return $fromPath.Source
  }

  $candidates = New-Object "System.Collections.Generic.List[string]"
  $baseDirs = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
  foreach ($baseDir in $baseDirs) {
    if ([string]::IsNullOrWhiteSpace($baseDir)) {
      continue
    }
    $candidates.Add((Join-Path $baseDir "Git\bin\bash.exe"))
    $candidates.Add((Join-Path $baseDir "Git\usr\bin\bash.exe"))
  }

  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  return $null
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$notifyScript = Join-Path $scriptDir "notify/codex-slack-notify.sh"

if (-not (Test-Path -LiteralPath $notifyScript -PathType Leaf)) {
  Write-Error "[ERROR] notify script not found: $notifyScript"
  exit 1
}

$bashPath = Resolve-BashPath
if ([string]::IsNullOrWhiteSpace($bashPath)) {
  Write-Error "[ERROR] bash.exe not found. Install Git for Windows and make bash available in PATH, then rerun setup.ps1."
  exit 1
}

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
  $homeDir = $env:USERPROFILE
  if ([string]::IsNullOrWhiteSpace($homeDir)) {
    $homeDir = $HOME
  }
  $CodexHome = Join-Path $homeDir ".codex"
}

$configPath = Join-Path $CodexHome "config.toml"
New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null

if (Test-Path -LiteralPath $configPath -PathType Leaf) {
  $backupPath = "$configPath.bak.$(Get-Date -Format "yyyyMMddHHmmss")"
  Copy-Item -LiteralPath $configPath -Destination $backupPath
  Write-Host "Backed up existing config: $backupPath"
}

$notifyLine = "notify = [{0}, {1}]" -f (Convert-ToTomlString $bashPath), (Convert-ToTomlString $notifyScript)

$inputLines = @()
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
  $inputLines = Get-Content -LiteralPath $configPath
}

$outputLines = New-Object "System.Collections.Generic.List[string]"
$inserted = $false
$skipMultiline = $false

foreach ($line in $inputLines) {
  if ($skipMultiline) {
    if ($line -match '\][ \t]*(#.*)?$') {
      $skipMultiline = $false
    }
    continue
  }

  if ($line -match '^[ \t]*notify[ \t]*=') {
    if ($line -match '\[' -and $line -notmatch '\][ \t]*(#.*)?$') {
      $skipMultiline = $true
    }
    continue
  }

  if (-not $inserted -and $line -match '^[ \t]*\[') {
    $outputLines.Add($notifyLine)
    $outputLines.Add("")
    $inserted = $true
  }

  $outputLines.Add($line)
}

if (-not $inserted) {
  if ($outputLines.Count -gt 0) {
    $outputLines.Add("")
  }
  $outputLines.Add($notifyLine)
}

$configText = [string]::Join([Environment]::NewLine, $outputLines)
if ($outputLines.Count -gt 0) {
  $configText += [Environment]::NewLine
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, $configText, $utf8NoBom)

Write-Host "Installed Codex notify command in: $configPath"
Write-Host $notifyLine
