'use strict';
// Tests against the library in build/ (or MOZC_FFI_LIBRARY): npm test

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test, after } = require('node:test');

const root = path.resolve(__dirname, '..', '..', '..');
process.env.MOZC_FFI_LIBRARY ||= path.join(root, 'build', process.platform === 'win32' ? 'mozc_ffi.dll' : 'libmozc_ffi.so');
const { Mozc, ABI_VERSION } = require('..');

// Mozc keeps one profile per process.
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'mozc-ffi-node-'));
after(() => fs.rmSync(profile, { recursive: true, force: true }));

const first = (segments) => segments.map((s) => s.candidates[0]).join('');

function reachable(target, segments) {
  let ends = new Set([0]);
  for (const s of segments) {
    const next = new Set();
    for (const e of ends) for (const c of s.candidates) if (target.startsWith(c, e)) next.add(e + c.length);
    ends = next;
  }
  return ends.has(target.length);
}

test('converts and predicts', () => {
  const mozc = new Mozc(profile, { incognito: true });
  try {
    assert.equal(ABI_VERSION, 2);
    assert.match(Mozc.mozcVersion, /^\d+\.\d+\.\d+\.\d+$/);

    let segments = mozc.convert('きょうはさむいですね');
    assert.equal(segments.map((s) => s.reading).join(''), 'きょうはさむいですね');
    assert.equal(first(segments), '今日は寒いですね');

    segments = mozc.convert('ここではきものをぬぐ', [3, 5, 2]);
    assert.deepEqual(segments.map((s) => s.reading), ['ここで', 'はきものを', 'ぬぐ']);
    assert.ok(segments[1].candidates.includes('履物を'));

    assert.deepEqual(mozc.convert('ここではきものをぬぐ', [3, 3]), []);
    assert.match(mozc.lastError, /do not add up/);
    assert.deepEqual(mozc.convert('ここではきものをぬぐ', [3, -1, 8]), []);
    assert.match(mozc.lastError, /positive integer/);
    assert.deepEqual(mozc.convert(''), []);
    assert.match(mozc.lastError, /empty/);
    assert.equal(mozc.learn('かんじ', [3], ['not a candidate']), false);
    assert.match(mozc.lastError, /not a candidate/);
    assert.ok(mozc.convert('かんじ').length > 0);
    assert.equal(mozc.lastError, '');

    const candidates = mozc.convert('かんじ', [3])[0].candidates;
    assert.equal(new Set(candidates).size, candidates.length);

    assert.ok(mozc.predict('ありがと').some((p) => p.startsWith('ありがとう')));
    assert.equal(first(mozc.convert('さむいですね', null, '今日は')), '寒いですね');
  } finally {
    mozc.close();
  }
});

test('chat quality', () => {
  const mozc = new Mozc(profile, { incognito: true });
  try {
    const cases = fs.readFileSync(path.join(root, 'tests', 'chat.tsv'), 'utf8').split('\n')
      .filter((l) => l && !l.startsWith('#'))
      .map((l) => { const [reading, answers] = l.split('\t'); return [reading, answers.split('|')]; });
    let top1 = 0, picks = 0;
    for (const [reading, answers] of cases) {
      const segments = mozc.convert(reading);
      if (answers.includes(first(segments))) top1++;
      if (answers.some((a) => reachable(a, segments))) picks++;
    }
    console.log(`chat.tsv: top-1 ${top1}/${cases.length}, reachable by picks ${picks}/${cases.length}`);
    assert.ok(top1 >= cases.length * 0.8);
    assert.ok(picks >= cases.length * 0.95);
  } finally {
    mozc.close();
  }
});

test('learns, persists and clears', () => {
  let mozc = new Mozc(profile);
  const before = mozc.convert('かんじ', [3])[0].candidates;
  const pick = before[1];
  assert.notEqual(pick, before[0]);
  assert.ok(mozc.learn('かんじ', [3], [pick]));
  assert.equal(mozc.convert('かんじ', [3])[0].candidates[0], pick);
  assert.equal(mozc.learn('かんじ', [3], ['not a candidate']), false);
  assert.equal(mozc.learn('かんじ', [2, 1], ['かん']), false);
  assert.ok(mozc.flush());
  mozc.close();
  mozc.close(); // twice is fine
  assert.throws(() => mozc.convert('かんじ'), /closed/);

  mozc = new Mozc(profile);
  assert.equal(mozc.convert('かんじ', [3])[0].candidates[0], pick);
  assert.ok(mozc.clearLearning());
  assert.equal(mozc.convert('かんじ', [3])[0].candidates[0], before[0]);
  mozc.close();

  mozc = new Mozc(profile, { incognito: true });
  const hashi = mozc.convert('はし', [2])[0].candidates;
  mozc.learn('はし', [2], [hashi[1]]);
  assert.equal(mozc.convert('はし', [2])[0].candidates[0], hashi[0]);
  mozc.close();
});
