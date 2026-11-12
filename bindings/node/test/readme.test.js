'use strict';
// Runs the examples in README.md and README.ja.md against the library in build/ (or MOZC_FFI_LIBRARY).
// Each ```js block runs in its own process, because Mozc keeps one profile per process, with
// '/path/to/profile' replaced by a new directory and require('mozc-ffi') by these bindings.
// A console.log() with a comment after it must print exactly that comment.

const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

const here = path.resolve(__dirname, '..');
const root = path.resolve(here, '..', '..');
const library = path.join(root, 'build', process.platform === 'win32' ? 'mozc_ffi.dll' : 'libmozc_ffi.so');

for (const readme of ['README.md', 'README.ja.md']) {
  test(`${readme} examples`, () => {
    const blocks = [...fs.readFileSync(path.join(here, readme), 'utf8').matchAll(/^```js\n(.*?)^```/gms)].map((m) => m[1]);
    assert.ok(blocks.length > 0, `${readme} has no js example`);
    for (const code of blocks) {
      const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mozc-ffi-readme-'));
      try {
        const script = code
          .replaceAll("'/path/to/profile'", JSON.stringify(profile))
          .replaceAll("require('mozc-ffi')", `require(${JSON.stringify(here)})`);
        const output = execFileSync(process.execPath, ['-e', script], {
          env: { ...process.env, MOZC_FFI_LIBRARY: process.env.MOZC_FFI_LIBRARY || library },
          encoding: 'utf8',
        });
        const expected = code.split('\n').map((line) => line.match(/^\s*console\.log\(.*\);\s*\/\/ (.*)$/)).filter(Boolean).map((m) => m[1]);
        assert.deepEqual(output.split('\n').filter(Boolean), expected);
      } finally {
        fs.rmSync(profile, { recursive: true, force: true });
      }
    }
  });
}
