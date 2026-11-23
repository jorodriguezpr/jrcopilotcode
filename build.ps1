# JR Copilot Code (jrcopilotcode) - build script
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
  Builds everything into dist\:
    jrcopilotcode-<ver>.vsix              the VS Code extension
    jrcopilotcode-<ver>-installer.zip     .vsix + install.cmd / uninstall.cmd (unzip, double-click install.cmd)
    jrcopilotcode-<ver>-setup.exe         one-file installer (Windows IExpress): extracts and runs install.cmd

    powershell -ExecutionPolicy Bypass -File build.ps1 [-NoExe] [-NoTests]
#>
param([switch]$NoExe, [switch]$NoTests)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$ver = (Get-Content package.json -Raw | ConvertFrom-Json).version
$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
Get-ChildItem $dist -Filter "jrcopilotcode-$ver*" | Remove-Item -Force

if (-not $NoTests) {
  Write-Host '== unit tests' -ForegroundColor Cyan
  node --test test/lib.test.js
  if ($LASTEXITCODE) { throw 'unit tests failed' }
}

Write-Host '== package .vsix' -ForegroundColor Cyan
$vsix = Join-Path $dist "jrcopilotcode-$ver.vsix"
npx --yes @vscode/vsce@3 package --out $vsix
if ($LASTEXITCODE -or -not (Test-Path $vsix)) { throw 'vsce package failed' }

Write-Host '== installer zip' -ForegroundColor Cyan
$stage = Join-Path $env:TEMP "jrcopilotcode-stage-$ver"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory $stage | Out-Null
Copy-Item $vsix, installer\install.cmd, installer\install.ps1, installer\uninstall.cmd, LICENSE, NOTICE $stage
Copy-Item README.md (Join-Path $stage 'README.md')
$zip = Join-Path $dist "jrcopilotcode-$ver-installer.zip"
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force

if (-not $NoExe) {
  Write-Host '== setup.exe (IExpress)' -ForegroundColor Cyan
  $exe = Join-Path $dist "jrcopilotcode-$ver-setup.exe"
  $files = @(Get-ChildItem $stage -File | Where-Object { $_.Name -ne 'README.md' })
  $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$exe
FriendlyName=JR Copilot Code $ver
AppLaunched=cmd.exe /c install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
$(($files | ForEach-Object -Begin { $i = 0 } -Process { "FILE$i=`"$($_.Name)`""; $i++ }) -join "`r`n")
[SourceFiles]
SourceFiles0=$stage\
[SourceFiles0]
$(($files | ForEach-Object -Begin { $i = 0 } -Process { "%FILE$i%="; $i++ }) -join "`r`n")
"@
  $sedFile = Join-Path $env:TEMP "jrcopilotcode-$ver.sed"
  [IO.File]::WriteAllText($sedFile, $sed, [Text.Encoding]::ASCII)
  Start-Process -FilePath "$env:WINDIR\System32\iexpress.exe" -ArgumentList '/N', '/Q', $sedFile -Wait -WindowStyle Hidden
  if (-not (Test-Path $exe)) { throw 'IExpress did not create the setup.exe' }
  Remove-Item $sedFile -Force
}
Remove-Item -Recurse -Force $stage

Write-Host ''
Get-ChildItem $dist -Filter "jrcopilotcode-$ver*" | ForEach-Object { '{0,-45} {1,8:N0} KB' -f $_.Name, ($_.Length / 1KB) }
