'use strict';
const test = require('node:test');
const assert = require('node:assert');
const lib = require('../src/lib');

test('buildPrompt: question only', () => {
  assert.strictEqual(lib.buildPrompt({ question: '  write x  ' }), 'write x');
});

test('buildPrompt: with selection and instruction', () => {
  const p = lib.buildPrompt({ question: 'fix it', selection: 'a = 1\n\n', fileName: 'x.py', languageId: 'python', instruction: 'One block.' });
  assert.strictEqual(p, 'fix it\n\nHere is the code (file: x.py, language: python):\n```python\na = 1\n```\n\nOne block.');
});

test('buildPrompt: selection that contains ``` uses ~~~~ fence', () => {
  const p = lib.buildPrompt({ question: 'q', selection: '```js\nx\n```', languageId: 'markdown' });
  assert.match(p, /~~~~markdown\n```js\nx\n```\n~~~~/);
});

test('parseBridgeOutput: progress, result, junk', () => {
  const out = 'WARNING: x\n{"type":"progress","message":"a"}\r\n{"type":"result","ok":true,"text":"t"}\n';
  const r = lib.parseBridgeOutput(out);
  assert.deepStrictEqual(r.progress, ['a']);
  assert.strictEqual(r.result.text, 't');
});

test('normaliseBlocks: object, null, empty code', () => {
  assert.deepStrictEqual(lib.normaliseBlocks(null), []);
  assert.deepStrictEqual(lib.normaliseBlocks({ language: 'PHP', code: 'x\r\ny' }), [{ language: 'PHP', code: 'x\ny' }]);
  assert.deepStrictEqual(lib.normaliseBlocks([{ language: 'a', code: '  ' }]), []);
});

test('extractFencedBlocks', () => {
  const t = 'Intro\n```php\n<?php echo 1;\n```\nmore\n~~~\nplain\n~~~';
  assert.deepStrictEqual(lib.extractFencedBlocks(t), [
    { language: 'php', code: '<?php echo 1;' },
    { language: '', code: 'plain' }
  ]);
});

test('reindent keeps first line and blank lines', () => {
  assert.strictEqual(lib.reindent('a\nb\n\nc', '    '), 'a\n    b\n\n    c');
  assert.strictEqual(lib.reindent('a\nb', ''), 'a\nb');
});

test('toLanguageId', () => {
  assert.strictEqual(lib.toLanguageId('JavaScript'), 'javascript');
  assert.strictEqual(lib.toLanguageId('C#'), 'csharp');
  assert.strictEqual(lib.toLanguageId('PowerShell'), 'powershell');
  assert.strictEqual(lib.toLanguageId(''), 'plaintext');
});
