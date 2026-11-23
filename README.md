<!--
  JR Copilot Code (jrcopilotcode)
  Copyright 2026 Jose Rodriguez Arroyo
  Developer: Jose Rodriguez Arroyo <jrpcone@gmail.com>
  Website: https://microrepair.net | GitHub: https://github.com/jorodriguezpr
  Project: https://github.com/jorodriguezpr/jrcopilotcode

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

  SPDX-License-Identifier: Apache-2.0
-->

# JR Copilot Code

**Ask the Microsoft Copilot Windows app for code and insert the answer straight into VS Code.**

Select some code (or just put the cursor where you want new code), press **Ctrl+Alt+Shift+C**, and type a question. The extension sends it to the **Microsoft Copilot** app on your PC, waits for the answer, and puts the returned code into the editor. It replaces your selection or goes in at the cursor, matching the indentation.

- Works with the **Copilot app you already use**: your account, your plan and your chat history. There are no API keys and no extra subscription.
- **Windows only.** The Copilot app has no public API, so the extension drives the app's window through **Windows UI Automation**.
- No dependencies, no telemetry, no network calls of its own. Everything stays between VS Code and the Copilot app on your PC.

---

## Requirements

- Windows 10 or 11
- Visual Studio Code 1.85 or newer
- The **Microsoft Copilot** app (`copilotapp.exe`, from the Microsoft Store), installed and signed in

## Install

Download one of these from the [latest release](https://github.com/jorodriguezpr/jrcopilotcode/releases/latest):

| File | How |
|---|---|
| `jrcopilotcode-<version>-setup.exe` | Double-click it. It installs the extension into every VS Code found on the PC (user install, system install, Insiders). |
| `jrcopilotcode-<version>-installer.zip` | Unzip it and double-click `install.cmd`. Run `uninstall.cmd` to remove the extension. |
| `jrcopilotcode-<version>.vsix` | In VS Code: Extensions, then **...**, then **Install from VSIX...**, or run `code --install-extension jrcopilotcode-<version>.vsix` |

Then, in VS Code, run **Ctrl+Shift+P → Developer: Reload Window**.

## First use

1. **Ctrl+Shift+P → Copilot App: Check connection.**
2. The first time, the extension asks to **restart the Copilot app with accessibility on** (`--force-renderer-accessibility`). Copilot's chat page can't be read by UI Automation without it. Your chats are kept, because they're stored in your Microsoft account. You need to do this again after a reboot, or whenever Copilot was started the normal way.
3. Ask a question with **Ctrl+Alt+Shift+C**.

## Commands

| Command | Keys | What it does |
|---|---|---|
| Copilot App: **Ask and insert code** | `Ctrl+Alt+Shift+C` | Asks Copilot and inserts the code: it replaces the selection, or goes in at the cursor |
| Copilot App: **Ask and show the answer** | `Ctrl+Alt+Shift+E` | Opens Copilot's whole answer as markdown beside the editor |
| Copilot App: Insert last answer's code again | | Inserts the code from the previous answer again, for example in another file |
| Copilot App: Start a new chat | | Starts a new chat in the Copilot app |
| Copilot App: Restart the Copilot app with accessibility on | | Restarts Copilot so its chat can be read |
| Copilot App: Check connection | | Shows whether Copilot is running and readable |

Both *Ask* commands are also in the editor's right-click menu. The **Copilot App** output panel (View → Output) logs every question and answer.

**What gets sent:** your question, plus the selected code with its file name and language (you can turn this off). *Ask and insert code* also adds "Answer with the complete code in a single fenced code block." (you can change this). If the answer has several code blocks, you choose one of them, or all of them.

## Settings

| Setting | Default | |
|---|---|---|
| `jrcopilotcode.insertMode` | `auto` | `auto` (replace selection / insert at cursor), `newDocument`, `clipboard` |
| `jrcopilotcode.multipleBlocks` | `pick` | `pick`, `all`, `first` |
| `jrcopilotcode.newChatEachQuestion` | `false` | `true` = every question starts a new Copilot chat |
| `jrcopilotcode.includeSelection` | `true` | Send the selected code with the question |
| `jrcopilotcode.codeInstruction` | *Answer with the complete code in a single fenced code block.* | Added to *Ask and insert code* questions |
| `jrcopilotcode.timeoutSeconds` | `180` | How long to wait for an answer |
| `jrcopilotcode.autoRestartCopilot` | `ask` | `ask`, `always`, `never` |
| `jrcopilotcode.copilotExe` | `C:\Program Files (x86)\Microsoft\Copilot\Application\copilotapp.exe` | |

## How it works

```
VS Code extension (src/extension.js)
   │  question + selection  →  temp file
   ▼
bridge/copilot-bridge.ps1  (PowerShell, Windows UI Automation)
   │  1. finds Copilot's chat box  (m365-chat-editor-target-element)
   │  2. checks the keyboard focus is really in it, pastes the question, presses Enter
   │  3. gives the focus back to VS Code
   │  4. waits for the new answer to finish ("Copy Response" shown, text stable)
   │  5. reads each code block (language + lines) and the whole answer
   ▼
JSON lines  →  extension  →  inserts the code
```

## Safety

- The bridge types only after it confirms that the keyboard focus is in Copilot's chat box. Otherwise it stops with `FOCUS_FAILED` and types nothing, so keystrokes never land in VS Code or another window.
- The clipboard is used to paste the question and is restored afterwards (text only).
- The Copilot window comes to the front for a moment while the question is sent. It then **stays visible on top, without the keyboard focus**, until the answer is read, because the Copilot app pauses its answer while its window is completely covered. You keep typing in VS Code, and Copilot goes back behind VS Code at the end.
- Your code goes only to Microsoft Copilot, under your own account and its terms.

## Troubleshooting

| Message / code | Fix |
|---|---|
| `NOT_ACCESSIBLE` / `NOT_RUNNING` | Run *Copilot App: Restart the Copilot app with accessibility on* |
| `FOCUS_FAILED` | Windows didn't let the Copilot window take the focus. Nothing was typed. Ask again, and don't click elsewhere for about 1 s. |
| `COPILOT_ERROR` | Copilot shows "Unable to load the content". The extension clicks Refresh by itself before asking. If it happens during an answer, click Refresh in Copilot and ask again. If it keeps happening, wait a few minutes, because Copilot may be limiting requests. |
| `TIMEOUT` / `NO_ANSWER` | Look at the Copilot window. It may want you to sign in, have hit a usage limit, or still be answering. Raise `timeoutSeconds` if needed. |
| Stopped working after a Copilot update | The Copilot page changed. The names the bridge depends on are all in `bridge/copilot-bridge.ps1`. Please open an issue. |

To test the bridge without VS Code:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File bridge\copilot-bridge.ps1 -Action status
"write hello world in python" | Out-File -Encoding utf8 $env:TEMP\q.txt
powershell -STA -NoProfile -ExecutionPolicy Bypass -File bridge\copilot-bridge.ps1 -Action ask -PromptFile $env:TEMP\q.txt
```

## Build from source

```powershell
git clone https://github.com/jorodriguezpr/jrcopilotcode
cd jrcopilotcode
npm test                                              # unit tests (Node 18+)
powershell -ExecutionPolicy Bypass -File build.ps1    # dist\: .vsix, installer .zip, setup.exe
```

`build.ps1` runs the tests, packages the extension with `@vscode/vsce`, and makes the installer zip and a one-file `setup.exe` with Windows' built-in IExpress.

Project layout:

```
src/extension.js            VS Code commands, prompt, insertion
src/lib.js                  pure helpers (unit tested)
bridge/copilot-bridge.ps1   UI Automation bridge to the Copilot app
installer/                  install.cmd / install.ps1 / uninstall.cmd
test/lib.test.js            unit tests
build.ps1                   build + installers
```

## Developer

**Jose Rodriguez Arroyo**: [jrpcone@gmail.com](mailto:jrpcone@gmail.com) · [microrepair.net](https://microrepair.net) · [github.com/jorodriguezpr](https://github.com/jorodriguezpr)

## License

Copyright 2026 Jose Rodriguez Arroyo.

Licensed under the **Apache License, Version 2.0**. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
You may not use this project except in compliance with the License. Unless required by
applicable law or agreed to in writing, software distributed under the License is distributed
on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

Microsoft, Copilot, Windows and Visual Studio Code are trademarks of the Microsoft group of
companies. This project is not affiliated with or endorsed by Microsoft. It automates the
Copilot app's user interface on your own PC; use it in line with the Copilot terms of use.
