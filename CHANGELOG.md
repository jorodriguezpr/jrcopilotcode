<!--
  JR Copilot Code (jrcopilotcode) - Copyright 2026 Jose Rodriguez Arroyo
  Developer: Jose Rodriguez Arroyo <jrpcone@gmail.com> - https://microrepair.net
  Licensed under the Apache License, Version 2.0. SPDX-License-Identifier: Apache-2.0
-->

# Changelog

## 0.1.2 - 2026-11-23

Fix: HTML answers still ended with "Copilot is answering..." until the timeout.

- Copilot shows HTML (and similar) code blocks as a live **preview** of the page, with no code editor, so the bridge waited for code that never appeared. It now clicks Copilot's **Code** button to switch the block to the code view, then reads it.
- Safety net: if a code block still can't be read once the answer has been finished and unchanged for 15 s, the bridge returns the answer anyway instead of waiting until the timeout.

## 0.1.1 - 2026-11-23

Fix: the extension kept showing "Copilot is answering..." until the timeout, and the code was never inserted.

- The Copilot app pauses its answer while its window is completely covered, for example by a maximized VS Code. While it answers, Copilot's window now stays visible on top without the keyboard focus, and goes back behind VS Code afterwards. Chromium's `--disable-backgrounding-*` switches were tried and don't help.
- The answer is found again on every check instead of reusing an element that may have been replaced.
- The bridge waits for the lazily loaded code previews (placeholder bars → code editor) before reading. Before, an answer could come back with no code blocks.
- The focus goes back to VS Code reliably: ALT unlock, then attaching to the foreground window's input thread, then a final fallback. It's restored again after reading.
- Copilot's "Unable to load the content" page: the extension clicks Refresh by itself before asking, and if it appears during an answer you get a clear `COPILOT_ERROR` instead of a timeout.
- `JRCOPILOT_DEBUG=1` adds debug lines to the bridge output.

## 0.1.0 - 2026-11-23

First release.

- **Ask and insert code** (`Ctrl+Alt+Shift+C`): sends the question, plus the selected code with its file name and language, to the Microsoft Copilot Windows app, then inserts the returned code. It replaces the selection or goes in at the cursor, re-indented. If the answer has several code blocks, you choose one.
- **Ask and show the answer** (`Ctrl+Alt+Shift+E`), **Insert last answer's code again**, **Start a new chat**, **Restart the Copilot app with accessibility on**, **Check connection**.
- UI Automation bridge (`bridge/copilot-bridge.ps1`): types only when the keyboard focus is confirmed to be in Copilot's chat box, gives the focus back to VS Code, restores the clipboard, and reads code blocks with their language.
- Installers: `setup.exe` (IExpress), an installer zip with `install.cmd` and `uninstall.cmd`, and the `.vsix`.
- Apache License 2.0.
