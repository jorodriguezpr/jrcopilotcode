<!--
  JR Copilot Code (jrcopilotcode) - Copyright 2026 Jose Rodriguez Arroyo
  Developer: Jose Rodriguez Arroyo <jrpcone@gmail.com> - https://microrepair.net
  Licensed under the Apache License, Version 2.0. SPDX-License-Identifier: Apache-2.0
-->

# Changelog

## 0.1.0 - 2026-11-23

First release.

- **Ask and insert code** (`Ctrl+Alt+Shift+C`): sends the question, plus the selected code with its file name and language, to the Microsoft Copilot Windows app, then inserts the returned code. It replaces the selection or goes in at the cursor, re-indented. If the answer has several code blocks, you choose one.
- **Ask and show the answer** (`Ctrl+Alt+Shift+E`), **Insert last answer's code again**, **Start a new chat**, **Restart the Copilot app with accessibility on**, **Check connection**.
- UI Automation bridge (`bridge/copilot-bridge.ps1`): types only when the keyboard focus is confirmed to be in Copilot's chat box, gives the focus back to VS Code, restores the clipboard, and reads code blocks with their language.
- Installers: `setup.exe` (IExpress), an installer zip with `install.cmd` and `uninstall.cmd`, and the `.vsix`.
- Apache License 2.0.
