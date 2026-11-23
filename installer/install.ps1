# JR Copilot Code (jrcopilotcode)
# Copyright 2026 Jose Rodriguez Arroyo
# Developer: Jose Rodriguez Arroyo <jrpcone@gmail.com>
# Website: https://microrepair.net | GitHub: https://github.com/jorodriguezpr
# Project: https://github.com/jorodriguezpr/jrcopilotcode
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0

<#
  Installs (or removes) the JR Copilot Code extension in Visual Studio Code.

    install.cmd                      install the .vsix that sits next to this script
    install.cmd -Uninstall           remove the extension
    install.ps1 -Vsix <file.vsix>    install a specific .vsix

  Finds every VS Code on this PC (user install, system install, Insiders, PATH) and
  installs into each one. Nothing is downloaded.
#>
param(
  [string]$Vsix,
  [switch]$Uninstall,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ExtId = 'jorodriguezpr.jrcopilotcode'
$CopilotExe = 'C:\Program Files (x86)\Microsoft\Copilot\Application\copilotapp.exe'

function Write-Step($m) { Write-Host "  $m" }
function Write-Ok($m) { Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Bad($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }

Write-Host ''
Write-Host 'JR Copilot Code - VS Code extension installer' -ForegroundColor Cyan
Write-Host 'Developer: Jose Rodriguez Arroyo - https://microrepair.net' -ForegroundColor DarkGray
Write-Host ''

# --- find VS Code command-line launchers --------------------------------------------------
$cands = @(
  "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
  "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
  "${env:ProgramFiles(x86)}\Microsoft VS Code\bin\code.cmd",
  "$env:LOCALAPPDATA\Programs\Microsoft VS Code Insiders\bin\code-insiders.cmd",
  "$env:ProgramFiles\Microsoft VS Code Insiders\bin\code-insiders.cmd"
)
foreach ($n in 'code', 'code-insiders') {
  $c = Get-Command "$n.cmd" -ErrorAction SilentlyContinue
  if ($c) { $cands += $c.Source }
}
$codes = @($cands | Where-Object { $_ -and (Test-Path $_) } | ForEach-Object { (Resolve-Path $_).Path } | Select-Object -Unique)
if (-not $codes.Count) {
  Write-Bad 'Visual Studio Code was not found. Install it from https://code.visualstudio.com and run this again.'
  if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
  exit 1
}

# Run code.cmd through cmd.exe so its stderr (Node deprecation warnings) is plain text, not a PowerShell error.
function Invoke-Code($code, $argline) {
  $out = cmd.exe /d /c "`"$code`" $argline 2>&1"
  $rc = $LASTEXITCODE
  $out | Where-Object { $_ -and $_ -notmatch 'DeprecationWarning|trace-deprecation' } | ForEach-Object { Write-Host "    $_" }
  return $rc
}

$failed = 0
if ($Uninstall) {
  foreach ($code in $codes) {
    Write-Step "Removing from $code"
    Invoke-Code $code "--uninstall-extension $ExtId" | Out-Null
  }
  Write-Ok 'Removed. Reload or restart VS Code.'
} else {
  if (-not $Vsix) {
    $Vsix = Get-ChildItem -Path $PSScriptRoot -Filter 'jrcopilotcode-*.vsix' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $Vsix -or -not (Test-Path $Vsix)) {
    Write-Bad "No jrcopilotcode-*.vsix found next to this script ($PSScriptRoot)."
    if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
    exit 1
  }
  Write-Step "Extension package: $(Split-Path $Vsix -Leaf)"
  foreach ($code in $codes) {
    Write-Step "Installing into $code"
    $rc = Invoke-Code $code "--install-extension `"$Vsix`" --force"
    if ($rc -ne 0) { $failed++ ; Write-Bad 'install failed' }
  }
  if ($failed -eq 0) { Write-Ok 'Installed.' }

  if (Test-Path $CopilotExe) { Write-Ok 'Microsoft Copilot app found.' }
  else { Write-Bad 'Microsoft Copilot app not found. Install "Microsoft Copilot" from the Microsoft Store and sign in.' }

  Write-Host ''
  Write-Host '  Next:' -ForegroundColor Cyan
  Write-Host '   1. In VS Code: Ctrl+Shift+P > "Developer: Reload Window".'
  Write-Host '   2. Ctrl+Shift+P > "Copilot App: Check connection" (it offers to restart Copilot with accessibility on).'
  Write-Host '   3. Ctrl+Alt+Shift+C = ask and insert code;  Ctrl+Alt+Shift+E = ask and show the answer.'
}
Write-Host ''
if (-not $NoPause) { Read-Host 'Press Enter to close' | Out-Null }
exit $failed
