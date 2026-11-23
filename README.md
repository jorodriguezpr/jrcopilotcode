# JR Copilot Code

A VSCode extension that sends your question (and the selected code) to the **Microsoft Copilot Windows app**, waits for the answer, and inserts the returned code into the editor.

The Copilot app has no API. The extension drives the app's own window through Windows UI Automation (`bridge/copilot-bridge.ps1`), so it uses your normal signed-in Copilot account and chat history.

## How it works

1. **Copilot App: Ask and insert code** (`Ctrl+Alt+Shift+C`, or right-click in the editor).
2. Type a question. If code is selected, it is sent along with the file name and language.
3. The bridge pastes the question into Copilot's chat box, presses Enter, and puts the focus back on VSCode.
4. It waits until the answer is finished, then reads every code block (with its language) and the full answer text.
5. The code replaces the selection, or goes in at the cursor, re-indented to match the line. If the answer has several blocks, you choose which one to insert.

**Copilot App: Ask and show the answer** (`Ctrl+Alt+Shift+E`) opens the whole answer as markdown beside the editor instead of inserting it.
The **Copilot App** output channel logs every question and answer.

## Accessibility mode (one-time per Copilot start)

Copilot's chat page is visible to UI Automation only when the app runs with `--force-renderer-accessibility`. If the app is closed, or running without that flag, the extension offers to (re)start it that way. Your chats are kept, because they're stored in your Microsoft account. You can also run **Copilot App: Restart the Copilot app with accessibility on** yourself.

## Settings

| Setting | Default | |
|---|---|---|
| `jrcopilotcode.insertMode` | `auto` | `auto` (replace selection / insert at cursor), `newDocument`, `clipboard` |
| `jrcopilotcode.multipleBlocks` | `pick` | `pick`, `all`, `first` |
| `jrcopilotcode.newChatEachQuestion` | `false` | `true` = every question starts a fresh chat |
| `jrcopilotcode.includeSelection` | `true` | send the selected code with the question |
| `jrcopilotcode.codeInstruction` | "Answer with the complete code in a single fenced code block." | added to *Ask and insert code* questions |
| `jrcopilotcode.timeoutSeconds` | `180` | |
| `jrcopilotcode.autoRestartCopilot` | `ask` | `ask`, `always`, `never` |
| `jrcopilotcode.copilotExe` | `C:\Program Files (x86)\Microsoft\Copilot\Application\copilotapp.exe` | |

## Safety notes

- The bridge types only after it confirms that the keyboard focus is in Copilot's chat box. Otherwise it stops with `FOCUS_FAILED` and types nothing, so keystrokes never land in VSCode or another app.
- The clipboard is used to paste the question and is restored afterwards (text only).
- Copilot's window briefly comes to the front while the question is sent.

## Bridge on its own (for testing)

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File bridge\copilot-bridge.ps1 -Action status
powershell -STA -NoProfile -ExecutionPolicy Bypass -File bridge\copilot-bridge.ps1 -Action ask -PromptFile q.txt [-NewChat] [-TimeoutSec 120]
```

The bridge prints JSON lines: `{"type":"progress",...}` and a final `{"type":"result","ok":true,"text":...,"blocks":[{"language","code"}]}`.

## Development

```powershell
npm test            # unit tests (node --test)
npm run package     # build jrcopilotcode-<version>.vsix
code --install-extension jrcopilotcode-0.1.0.vsix
```

## Limits

- Windows only, and only the new Copilot app (Chromium/Edge based, `copilotapp.exe`).
- It depends on the Copilot page's accessibility tree (`m365-chat-editor-target-element`, `fai-CopilotMessage`, `scriptor-component-code-block`). A Copilot update can change these. `bridge\copilot-bridge.ps1` is the one file to adjust when that happens.
