@echo off
rem JR Copilot Code (jrcopilotcode) - remove the extension from VS Code
rem Copyright 2026 Jose Rodriguez Arroyo
rem Developer: Jose Rodriguez Arroyo <jrpcone@gmail.com>
rem Website: https://microrepair.net | GitHub: https://github.com/jorodriguezpr
rem Project: https://github.com/jorodriguezpr/jrcopilotcode
rem Licensed under the Apache License, Version 2.0 - http://www.apache.org/licenses/LICENSE-2.0
rem SPDX-License-Identifier: Apache-2.0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall %*
exit /b %ERRORLEVEL%
