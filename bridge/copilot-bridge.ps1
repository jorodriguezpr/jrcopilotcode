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
  copilot-bridge.ps1 - drive the Microsoft Copilot Windows app through UI Automation.

  The Copilot app (copilotapp.exe) is Chromium based and has no API. Its web content
  is only visible to UI Automation when the app runs with --force-renderer-accessibility,
  so "launch" (re)starts it that way.

  Actions (one per run, output = JSON lines on stdout):
    status   -> {type:"result", ok, running, accessible}
    launch   -> restart the Copilot app with accessibility on, wait until the chat box is ready
    newchat  -> click "New chat"
    ask      -> paste the prompt from -PromptFile, press Enter, wait for the answer, and return
                {text, blocks:[{language, code}]}

  Progress lines: {type:"progress", message}
  Errors:         {type:"result", ok:false, code, error}
#>
param(
  [ValidateSet('status', 'launch', 'newchat', 'ask')][string]$Action = 'status',
  [string]$PromptFile,
  [int]$TimeoutSec = 180,
  [switch]$NewChat,
  [switch]$NoRestoreFocus,
  [string]$CopilotExe = 'C:\Program Files (x86)\Microsoft\Copilot\Application\copilotapp.exe'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms

Add-Type -Namespace JrCopilot -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);
'@

$AE = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$CT = [System.Windows.Automation.ControlType]
$EDITOR_ID = 'm365-chat-editor-target-element'
$MSGLIST_ID = 'llm-web-ui-messageList-scrollable-container'

function Out-Json($obj) { [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 6)); [Console]::Out.Flush() }
function Say($msg) { Out-Json @{ type = 'progress'; message = $msg } }
function Fail($code, $msg) { Out-Json @{ type = 'result'; ok = $false; code = $code; error = $msg }; exit 1 }

function Cond($prop, $value) { New-Object System.Windows.Automation.PropertyCondition($prop, $value) }

function Get-CopilotWindow {
  $p = Get-Process copilotapp -ErrorAction SilentlyContinue |
       Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
  if (-not $p) { return $null }
  return $AE::FromHandle($p.MainWindowHandle)
}

function Find-Editor($root) {
  if (-not $root) { return $null }
  return $root.FindFirst($Scope::Descendants, (Cond $AE::AutomationIdProperty $EDITOR_ID))
}

function Find-ByName($root, $name, $type) {
  $c = Cond $AE::NameProperty $name
  if ($type) { $c = New-Object System.Windows.Automation.AndCondition($c, (Cond $AE::ControlTypeProperty $type)) }
  return $root.FindFirst($Scope::Descendants, $c)
}

function Invoke-Element($el) {
  $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

# Message title elements look like: Text id="copilot-message-_r_1ht_-title"; the parent is the message group.
function Get-CopilotTitles($root) {
  $list = $root.FindFirst($Scope::Descendants, (Cond $AE::AutomationIdProperty $MSGLIST_ID))
  if (-not $list) { return @() }
  $texts = $list.FindAll($Scope::Descendants, (Cond $AE::ControlTypeProperty $CT::Text))
  return @($texts | Where-Object { $_.Current.AutomationId -like 'copilot-message-*-title' })
}

function Get-Clip {
  try { if ([System.Windows.Forms.Clipboard]::ContainsText()) { return [System.Windows.Forms.Clipboard]::GetText() } } catch {}
  return $null
}
function Set-Clip($text) {
  for ($i = 0; $i -lt 5; $i++) {
    try { if ($null -eq $text -or $text -eq '') { [System.Windows.Forms.Clipboard]::Clear() } else { [System.Windows.Forms.Clipboard]::SetText($text) }; return } catch { Start-Sleep -Milliseconds 100 }
  }
}

function Bring-ToFront($hwnd) {
  if ([JrCopilot.Win32]::IsIconic($hwnd)) { [JrCopilot.Win32]::ShowWindow($hwnd, 9) | Out-Null }  # SW_RESTORE
  if (-not [JrCopilot.Win32]::SetForegroundWindow($hwnd)) {
    # Windows refuses focus changes unless the caller "owns" input; a synthetic ALT press unlocks it.
    [JrCopilot.Win32]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero)
    [JrCopilot.Win32]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
    [JrCopilot.Win32]::SetForegroundWindow($hwnd) | Out-Null
  }
}

# All Text names under an element, in document order, via the RAW view
# (Chromium marks code lines offscreen and the control view drops them).
$RAW = [System.Windows.Automation.TreeWalker]::RawViewWalker
function Get-RawText($el, $acc) {
  $ch = $RAW.GetFirstChild($el)
  while ($ch) {
    if ($ch.Current.ControlType -eq $CT::Text) { $acc.Add($ch.Current.Name) } else { Get-RawText $ch $acc }
    $ch = $RAW.GetNextSibling($ch)
  }
}

# Code text from the UIA tree: the "Code editor" Edit alternates [line-number group][line-content group].
function Get-CodeFromTree($block) {
  $ed = $block.FindFirst($Scope::Descendants, (Cond $AE::NameProperty 'Code editor'))
  if (-not $ed) { return $null }
  $rows = @(); $ch = $RAW.GetFirstChild($ed)
  while ($ch) { $rows += $ch; $ch = $RAW.GetNextSibling($ch) }
  $lines = New-Object System.Collections.Generic.List[string]
  for ($i = 1; $i -lt $rows.Count; $i += 2) {
    $parts = New-Object System.Collections.Generic.List[string]
    Get-RawText $rows[$i] $parts
    $lines.Add(((($parts) -join '') -replace '\s+$', ''))
  }
  return ($lines -join "`n")
}

function Get-Blocks($msg) {
  $blocks = @()
  $groups = $msg.FindAll($Scope::Descendants, (Cond $AE::ControlTypeProperty $CT::Group)) |
            Where-Object { $_.Current.ClassName -like 'scriptor-component-code-block*' }
  foreach ($g in $groups) {
    $lang = ''
    $t = $g.FindFirst($Scope::Children, (Cond $AE::ControlTypeProperty $CT::Text))
    if ($t) { $lang = $t.Current.Name }
    $code = Get-CodeFromTree $g
    $copy = $null
    if ($null -eq $code) { $copy = $g.FindFirst($Scope::Descendants, (Cond $AE::AutomationIdProperty 'copy-button')) }
    if ($copy) {
      $sentinel = '__jrcopilotcode_' + [guid]::NewGuid().ToString('N')
      Set-Clip $sentinel
      try {
        Invoke-Element $copy
        for ($i = 0; $i -lt 15; $i++) { Start-Sleep -Milliseconds 100; $c = Get-Clip; if ($c -and $c -ne $sentinel) { $code = $c; break } }
      } catch {}
    }
    if ($null -ne $code) { $blocks += @{ language = $lang; code = ($code -replace "`r`n", "`n") } }
  }
  return , $blocks
}

function Get-ResponseText($msg) {
  $btn = Find-ByName $msg 'Copy Response' $CT::Button
  if ($btn) {
    $sentinel = '__jrcopilotcode_' + [guid]::NewGuid().ToString('N')
    Set-Clip $sentinel
    try {
      Invoke-Element $btn
      for ($i = 0; $i -lt 15; $i++) { Start-Sleep -Milliseconds 100; $c = Get-Clip; if ($c -and $c -ne $sentinel) { return ($c -replace "`r`n", "`n") } }
    } catch {}
  }
  $parts = $msg.FindAll($Scope::Descendants, (Cond $AE::ControlTypeProperty $CT::Text)) | ForEach-Object { $_.Current.Name }
  return ($parts -join "`n")
}

function Start-Accessible {
  Say 'Restarting the Copilot app with accessibility enabled...'
  Get-Process copilotapp, copilotapphost -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
  Start-Sleep -Seconds 2
  if (-not (Test-Path $CopilotExe)) { Fail 'NOT_INSTALLED' "Copilot app not found at $CopilotExe" }
  Start-Process -FilePath $CopilotExe -ArgumentList '--force-renderer-accessibility'
  $deadline = (Get-Date).AddSeconds(60)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 1000
    try { $w = Get-CopilotWindow; if ($w -and (Find-Editor $w)) { return $w } } catch {}
  }
  Fail 'LAUNCH_TIMEOUT' 'The Copilot app started but its chat box did not appear within 60 s (is it signed in?).'
}

function Require-Ready {
  $w = Get-CopilotWindow
  if (-not $w) { Fail 'NOT_RUNNING' 'The Copilot app is not running.' }
  $ed = Find-Editor $w
  if (-not $ed) { Fail 'NOT_ACCESSIBLE' 'The Copilot app is running without accessibility, so its chat cannot be read. Restart it with accessibility enabled.' }
  return $w
}

try {
  switch ($Action) {
    'status' {
      $w = Get-CopilotWindow
      $acc = $false; if ($w) { $acc = [bool](Find-Editor $w) }
      Out-Json @{ type = 'result'; ok = $true; running = [bool]$w; accessible = $acc }
    }
    'launch' {
      $w = Start-Accessible
      Out-Json @{ type = 'result'; ok = $true; running = $true; accessible = $true }
    }
    'newchat' {
      $w = Require-Ready
      $nc = Find-ByName $w 'New chat' $null
      if (-not $nc) { Fail 'NO_NEW_CHAT' '"New chat" link not found.' }
      Invoke-Element $nc
      Out-Json @{ type = 'result'; ok = $true }
    }
    'ask' {
      if (-not $PromptFile -or -not (Test-Path $PromptFile)) { Fail 'BAD_ARGS' 'Missing -PromptFile.' }
      $prompt = [System.IO.File]::ReadAllText($PromptFile, [System.Text.Encoding]::UTF8)
      if (-not $prompt.Trim()) { Fail 'BAD_ARGS' 'Empty prompt.' }

      $w = Require-Ready
      if ($NewChat) {
        $nc = Find-ByName $w 'New chat' $null
        if ($nc) { Say 'Starting a new chat...'; Invoke-Element $nc; Start-Sleep -Milliseconds 1500 }
      }
      $before = @{}
      foreach ($t in (Get-CopilotTitles $w)) { $before[$t.Current.AutomationId] = $true }

      $hwnd = New-Object IntPtr ($w.Current.NativeWindowHandle)
      $prevFg = [JrCopilot.Win32]::GetForegroundWindow()
      $savedClip = Get-Clip
      $started = Get-Date
      try {
        Say 'Sending the question to the Copilot app...'
        Set-Clip $prompt
        Bring-ToFront $hwnd
        $ed = Find-Editor $w
        $ed.SetFocus()
        Start-Sleep -Milliseconds 300
        # Safety: only type if the keyboard focus really is the Copilot chat box.
        $f = $AE::FocusedElement
        if (-not $f -or $f.Current.AutomationId -ne $EDITOR_ID) {
          Fail 'FOCUS_FAILED' 'Could not put the keyboard focus in the Copilot chat box; nothing was typed.'
        }
        [System.Windows.Forms.SendKeys]::SendWait('^a')
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 400
        $f = $AE::FocusedElement
        if (-not $f -or $f.Current.AutomationId -ne $EDITOR_ID) {
          Fail 'FOCUS_FAILED' 'Focus left the Copilot chat box before sending; the question was not sent.'
        }
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Start-Sleep -Milliseconds 300
        if (-not $NoRestoreFocus -and $prevFg -ne [IntPtr]::Zero) { [JrCopilot.Win32]::SetForegroundWindow($prevFg) | Out-Null }

        Say 'Waiting for the answer...'
        $deadline = $started.AddSeconds($TimeoutSec)
        $msg = $null; $lastSig = ''; $stable = 0
        while ((Get-Date) -lt $deadline) {
          Start-Sleep -Milliseconds 800
          if (-not $msg) {
            $new = @(Get-CopilotTitles $w | Where-Object { -not $before.ContainsKey($_.Current.AutomationId) })
            if ($new.Count -gt 0) {
              $msg = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($new[-1])
              Say 'Copilot is answering...'
            }
            continue
          }
          $done = [bool](Find-ByName $msg 'Copy Response' $CT::Button)
          if (-not $done) { $stable = 0; continue }
          $texts = $msg.FindAll($Scope::Descendants, (Cond $AE::ControlTypeProperty $CT::Text))
          $sig = "$($texts.Count):" + (($texts | ForEach-Object { $_.Current.Name.Length }) | Measure-Object -Sum).Sum
          if ($sig -eq $lastSig) { $stable++ } else { $stable = 0; $lastSig = $sig }
          if ($stable -ge 2) { break }
        }
        if (-not $msg) { Fail 'NO_ANSWER' "No answer appeared within $TimeoutSec s." }
        if ($stable -lt 2) { Fail 'TIMEOUT' "The answer did not finish within $TimeoutSec s." }

        Say 'Reading the answer...'
        $blocks = Get-Blocks $msg
        $text = Get-ResponseText $msg
        Out-Json @{ type = 'result'; ok = $true; text = $text; blocks = $blocks; elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds }
      } finally {
        Set-Clip $savedClip
      }
    }
  }
} catch {
  Fail 'ERROR' ($_.Exception.Message)
}
