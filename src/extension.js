'use strict';
// JR Copilot Code (jrcopilotcode)
// Copyright 2026 Jose Rodriguez Arroyo
// Developer: Jose Rodriguez Arroyo <jrpcone@gmail.com>
// Website: https://microrepair.net | GitHub: https://github.com/jorodriguezpr
// Project: https://github.com/jorodriguezpr/jrcopilotcode
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// SPDX-License-Identifier: Apache-2.0
const vscode = require('vscode');
const cp = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const lib = require('./lib');

let output;
let busy = false;
let lastAnswer = null; // { text, blocks }

function cfg() { return vscode.workspace.getConfiguration('jrcopilotcode'); }

/** Run the PowerShell bridge. Resolves with the result object; rejects with Error(code). */
function runBridge(context, action, extraArgs, onProgress, token) {
  const script = path.join(context.extensionPath, 'bridge', 'copilot-bridge.ps1');
  const args = ['-NoProfile', '-NonInteractive', '-STA', '-ExecutionPolicy', 'Bypass', '-File', script,
    '-Action', action, '-CopilotExe', cfg().get('copilotExe'), ...extraArgs];
  return new Promise((resolve, reject) => {
    const child = cp.spawn('powershell.exe', args, { windowsHide: true });
    let stdout = '', stderr = '', buf = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', d => {
      stdout += d; buf += d;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i); buf = buf.slice(i + 1);
        const { progress } = lib.parseBridgeOutput(line);
        progress.forEach(m => { output.appendLine(`  ${m}`); onProgress && onProgress(m); });
      }
    });
    child.stderr.on('data', d => { stderr += d; });
    const sub = token && token.onCancellationRequested(() => { try { child.kill(); } catch { /* ignore */ } });
    child.on('error', e => { sub && sub.dispose(); reject(e); });
    child.on('close', () => {
      sub && sub.dispose();
      if (token && token.isCancellationRequested) return reject(Object.assign(new Error('Cancelled.'), { code: 'CANCELLED' }));
      const { result } = lib.parseBridgeOutput(stdout);
      if (!result) {
        if (stderr.trim()) output.appendLine(stderr.trim());
        return reject(Object.assign(new Error('The bridge returned no result (see the "Copilot App" output).'), { code: 'NO_RESULT' }));
      }
      if (!result.ok) return reject(Object.assign(new Error(result.error || 'Failed.'), { code: result.code }));
      resolve(result);
    });
  });
}

/** Make sure the Copilot app is running with accessibility; offers to restart it. */
async function ensureReady(context) {
  const st = await runBridge(context, 'status', []);
  if (st.running && st.accessible) return true;
  const mode = cfg().get('autoRestartCopilot');
  if (mode === 'never') {
    throw Object.assign(new Error(st.running
      ? 'The Copilot app is running without accessibility. Run "Copilot App: Restart the Copilot app with accessibility on".'
      : 'The Copilot app is not running.'), { code: 'NOT_READY' });
  }
  if (mode === 'ask') {
    const msg = st.running
      ? 'The Copilot app is running, but its chat cannot be read until it is restarted with accessibility on. Restart it now? (Your chats are kept.)'
      : 'The Copilot app is not running. Start it with accessibility on?';
    const pick = await vscode.window.showWarningMessage(msg, { modal: true }, st.running ? 'Restart Copilot' : 'Start Copilot');
    if (!pick) throw Object.assign(new Error('Cancelled.'), { code: 'CANCELLED' });
  }
  await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: 'Copilot App' },
    p => runBridge(context, 'launch', [], m => p.report({ message: m })));
  return true;
}

async function askCopilot(context, prompt) {
  if (busy) { vscode.window.showInformationMessage('Copilot App: a question is already running.'); return null; }
  busy = true;
  const promptFile = path.join(os.tmpdir(), `jrcopilotcode-${process.pid}-${Date.now()}.txt`);
  try {
    await ensureReady(context);
    fs.writeFileSync(promptFile, prompt, 'utf8');
    output.appendLine(`\n=== ${new Date().toLocaleTimeString()} question ===\n${prompt}`);
    const args = ['-PromptFile', promptFile, '-TimeoutSec', String(cfg().get('timeoutSeconds'))];
    if (cfg().get('newChatEachQuestion')) args.push('-NewChat');
    const res = await vscode.window.withProgress(
      { location: vscode.ProgressLocation.Notification, title: 'Copilot App', cancellable: true },
      (p, token) => runBridge(context, 'ask', args, m => p.report({ message: m }), token));
    let blocks = lib.normaliseBlocks(res.blocks);
    if (!blocks.length) blocks = lib.extractFencedBlocks(res.text);
    lastAnswer = { text: res.text || '', blocks };
    output.appendLine(`=== answer (${(res.elapsedMs / 1000).toFixed(1)} s, ${blocks.length} code block(s)) ===\n${lastAnswer.text}`);
    return lastAnswer;
  } catch (e) {
    if (e.code !== 'CANCELLED') {
      output.appendLine(`ERROR ${e.code || ''}: ${e.message}`);
      const pick = await vscode.window.showErrorMessage(`Copilot App: ${e.message}`, 'Show log');
      if (pick) output.show(true);
    }
    return null;
  } finally {
    busy = false;
    try { fs.unlinkSync(promptFile); } catch { /* ignore */ }
  }
}

async function chooseCode(answer) {
  const { blocks } = answer;
  if (!blocks.length) {
    const pick = await vscode.window.showWarningMessage('Copilot App: the answer has no code block.', 'Insert whole answer', 'Show answer');
    if (pick === 'Insert whole answer') return { code: answer.text, language: '' };
    if (pick === 'Show answer') await showAnswer(answer);
    return null;
  }
  if (blocks.length === 1) return blocks[0];
  const mode = cfg().get('multipleBlocks');
  if (mode === 'first') return blocks[0];
  if (mode === 'all') return { code: blocks.map(b => b.code).join('\n\n'), language: blocks[0].language };
  const items = blocks.map((b, i) => ({
    label: `${i + 1}. ${b.language || 'code'}`,
    description: `${b.code.split('\n').length} lines`,
    detail: b.code.split('\n').find(l => l.trim()) || '',
    block: b
  }));
  items.push({ label: 'All blocks', description: `${blocks.length} blocks joined`, block: { code: blocks.map(b => b.code).join('\n\n'), language: blocks[0].language } });
  const sel = await vscode.window.showQuickPick(items, { placeHolder: 'Copilot returned several code blocks - which one to insert?' });
  return sel ? sel.block : null;
}

async function insertCode(target, block) {
  const mode = cfg().get('insertMode');
  if (mode === 'clipboard' || (!target && mode === 'auto')) {
    await vscode.env.clipboard.writeText(block.code);
    vscode.window.showInformationMessage('Copilot App: code copied to the clipboard.');
    return;
  }
  if (mode === 'newDocument') {
    const doc = await vscode.workspace.openTextDocument({ content: block.code, language: lib.toLanguageId(block.language) });
    await vscode.window.showTextDocument(doc, vscode.ViewColumn.Beside);
    return;
  }
  // auto: replace the original selection / insert at the original cursor, in the original document
  const editor = await vscode.window.showTextDocument(target.document, { preserveFocus: false });
  const sel = target.selection;
  const lineText = target.document.lineAt(sel.start.line).text;
  const lead = (lineText.match(/^\s*/) || [''])[0];
  let code = block.code;
  if (sel.start.character > 0) code = lib.reindent(code, lead.slice(0, sel.start.character));
  else if (!sel.isEmpty && lead) code = lib.reindent(lead + code, lead);
  const ok = await editor.edit(eb => sel.isEmpty ? eb.insert(sel.start, code) : eb.replace(sel, code));
  if (!ok) { await vscode.env.clipboard.writeText(block.code); vscode.window.showWarningMessage('Copilot App: could not edit the file; the code is on the clipboard.'); return; }
  const lines = code.split('\n');
  const end = new vscode.Position(sel.start.line + lines.length - 1, (lines.length === 1 ? sel.start.character : 0) + lines[lines.length - 1].length);
  editor.selection = new vscode.Selection(sel.start, end);
  editor.revealRange(new vscode.Range(sel.start, end));
}

async function showAnswer(answer) {
  const doc = await vscode.workspace.openTextDocument({ content: answer.text, language: 'markdown' });
  await vscode.window.showTextDocument(doc, { viewColumn: vscode.ViewColumn.Beside, preview: true });
}

function editorContext() {
  const ed = vscode.window.activeTextEditor;
  if (!ed) return { target: null, selection: '', fileName: '', languageId: '' };
  return {
    target: { document: ed.document, selection: ed.selection },
    selection: ed.selection.isEmpty ? '' : ed.document.getText(ed.selection),
    fileName: path.basename(ed.document.fileName),
    languageId: ed.document.languageId
  };
}

async function cmdAsk(context, withCode) {
  const ctx = editorContext();
  const hasSel = !!ctx.selection && cfg().get('includeSelection');
  const question = await vscode.window.showInputBox({
    title: withCode ? 'Ask the Copilot app for code' : 'Ask the Copilot app',
    prompt: hasSel ? `The selected code (${ctx.selection.split('\n').length} lines) will be sent too.` : (withCode ? 'The code goes in at the cursor.' : 'The answer opens beside the editor.'),
    placeHolder: withCode ? 'e.g. write a function that validates a Puerto Rico phone number' : 'e.g. explain what this code does',
    ignoreFocusOut: true
  });
  if (!question || !question.trim()) return;
  const prompt = lib.buildPrompt({
    question,
    selection: hasSel ? ctx.selection : '',
    fileName: ctx.fileName,
    languageId: ctx.languageId,
    instruction: withCode ? cfg().get('codeInstruction') : ''
  });
  const answer = await askCopilot(context, prompt);
  if (!answer) return;
  if (!withCode) { await showAnswer(answer); return; }
  const block = await chooseCode(answer);
  if (block) await insertCode(ctx.target, block);
}

function activate(context) {
  output = vscode.window.createOutputChannel('Copilot App');
  context.subscriptions.push(
    output,
    vscode.commands.registerCommand('jrcopilotcode.ask', () => cmdAsk(context, true)),
    vscode.commands.registerCommand('jrcopilotcode.explain', () => cmdAsk(context, false)),
    vscode.commands.registerCommand('jrcopilotcode.insertLast', async () => {
      if (!lastAnswer) { vscode.window.showInformationMessage('Copilot App: no answer yet.'); return; }
      const block = await chooseCode(lastAnswer);
      if (block) await insertCode(editorContext().target, block);
    }),
    vscode.commands.registerCommand('jrcopilotcode.newChat', async () => {
      try { await ensureReady(context); await runBridge(context, 'newchat', []); vscode.window.showInformationMessage('Copilot App: new chat started.'); }
      catch (e) { if (e.code !== 'CANCELLED') vscode.window.showErrorMessage(`Copilot App: ${e.message}`); }
    }),
    vscode.commands.registerCommand('jrcopilotcode.launch', async () => {
      try {
        await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title: 'Copilot App' },
          p => runBridge(context, 'launch', [], m => p.report({ message: m })));
        vscode.window.showInformationMessage('Copilot App: ready.');
      } catch (e) { vscode.window.showErrorMessage(`Copilot App: ${e.message}`); }
    }),
    vscode.commands.registerCommand('jrcopilotcode.status', async () => {
      try {
        const st = await runBridge(context, 'status', []);
        vscode.window.showInformationMessage(`Copilot App: ${!st.running ? 'not running' : st.accessible ? 'running and readable - ready' : 'running WITHOUT accessibility (restart needed)'}.`);
      } catch (e) { vscode.window.showErrorMessage(`Copilot App: ${e.message}`); }
    })
  );
}

function deactivate() { }

module.exports = { activate, deactivate };
