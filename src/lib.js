'use strict';
// Pure helpers (no vscode import) so they can be unit tested with node --test.

/** Build the text sent to Copilot. */
function buildPrompt({ question, selection, fileName, languageId, instruction }) {
  const parts = [question.trim()];
  if (selection && selection.trim()) {
    const where = [fileName && `file: ${fileName}`, languageId && `language: ${languageId}`].filter(Boolean).join(', ');
    const fence = selection.includes('```') ? '~~~~' : '```';
    parts.push(`Here is the code${where ? ` (${where})` : ''}:\n${fence}${languageId || ''}\n${selection.replace(/\s+$/, '')}\n${fence}`);
  }
  if (instruction && instruction.trim()) parts.push(instruction.trim());
  return parts.join('\n\n');
}

/**
 * Parse the bridge's stdout (JSON lines). Returns { result, progress[] }.
 * Non-JSON lines are ignored (PowerShell can print warnings).
 */
function parseBridgeOutput(stdout) {
  const progress = [];
  let result = null;
  for (const line of String(stdout).split(/\r?\n/)) {
    const t = line.trim();
    if (!t.startsWith('{')) continue;
    let obj;
    try { obj = JSON.parse(t); } catch { continue; }
    if (obj.type === 'progress') progress.push(obj.message);
    else if (obj.type === 'result') result = obj;
  }
  return { result, progress };
}

/** Normalise the blocks array (PowerShell turns 1-element arrays into objects, 0 into null). */
function normaliseBlocks(blocks) {
  if (!blocks) return [];
  const arr = Array.isArray(blocks) ? blocks : [blocks];
  return arr
    .filter(b => b && typeof b.code === 'string' && b.code.trim() !== '')
    .map(b => ({ language: String(b.language || ''), code: b.code.replace(/\r\n/g, '\n') }));
}

/** Fallback: pull fenced blocks out of plain/markdown text. */
function extractFencedBlocks(text) {
  const out = [];
  const re = /(^|\n)(```|~~~)([^\n]*)\n([\s\S]*?)\n\2[ \t]*(?=\n|$)/g;
  let m;
  while ((m = re.exec(String(text || ''))) !== null) out.push({ language: m[3].trim(), code: m[4] });
  return out;
}

/** Match the editor's indentation: indent every line after the first with the cursor line's indent. */
function reindent(code, indent) {
  if (!indent) return code;
  return code.split('\n').map((l, i) => (i === 0 || l === '' ? l : indent + l)).join('\n');
}

/** Copilot language label ("JavaScript", "PHP") -> VS Code languageId. */
function toLanguageId(label) {
  const l = String(label || '').toLowerCase().trim();
  const map = {
    'c#': 'csharp', 'c++': 'cpp', 'f#': 'fsharp', 'objective-c': 'objective-c', 'shell': 'shellscript',
    'bash': 'shellscript', 'sh': 'shellscript', 'zsh': 'shellscript', 'powershell': 'powershell', 'js': 'javascript',
    'ts': 'typescript', 'py': 'python', 'yml': 'yaml', 'plain text': 'plaintext', 'text': 'plaintext', 'html': 'html',
    'vue': 'vue', 'blade': 'blade', 'dockerfile': 'dockerfile', 'jsx': 'javascriptreact', 'tsx': 'typescriptreact'
  };
  return map[l] || l.replace(/\s+/g, '') || 'plaintext';
}

module.exports = { buildPrompt, parseBridgeOutput, normaliseBlocks, extractFencedBlocks, reindent, toLanguageId };
