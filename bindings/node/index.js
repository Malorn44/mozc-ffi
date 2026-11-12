'use strict';
// Node.js bindings for mozc-ffi: Mozc's kana-kanji converter, in process, over koffi.
//
//   const { Mozc } = require('mozc-ffi');
//   const mozc = new Mozc('/path/to/profile');
//   mozc.convert('ここではきものをぬぐ', [3, 5, 2]);  // fixed segment lengths, in characters
//   mozc.predict('ありがと');                       // ['ありがとうございます', ...]
//   mozc.learn('かんじ', [3], ['感じ']);             // 感じ ranks first next time
//   mozc.close();
//
// The native library is found from MOZC_FFI_LIBRARY, the @mozc-ffi/<platform>-<arch> package,
// or the system's library path. Mozc keeps the profile directory per process.

const koffi = require('koffi');
const path = require('node:path');

const ABI_VERSION = 2;
const INCOGNITO = 1;

function libraryPath() {
  if (process.env.MOZC_FFI_LIBRARY) return process.env.MOZC_FFI_LIBRARY;
  const name = { win32: 'mozc_ffi.dll', darwin: 'libmozc_ffi.dylib' }[process.platform] || 'libmozc_ffi.so';
  try {
    const pkg = require.resolve(`@mozc-ffi/${process.platform}-${process.arch}/package.json`);
    return path.join(path.dirname(pkg), name);
  } catch {
    return name;
  }
}

let api = null;

// Loaded once and never unloaded: Mozc keeps global state that doesn't survive unloading.
function load() {
  if (api) return api;
  const lib = koffi.load(libraryPath());
  const found = lib.func('int32_t mozc_ffi_abi_version()')();
  if (found !== ABI_VERSION) throw new Error(`mozc_ffi has ABI ${found}, these bindings need ${ABI_VERSION}`);
  koffi.opaque('mozc_ffi');
  koffi.opaque('mozc_ffi_result');
  const f = (signature) => lib.func(signature);
  api = {
    mozcVersion: f('const char *mozc_ffi_mozc_version()'),
    lastError: f('const char *mozc_ffi_last_error()'),
    open: f('mozc_ffi *mozc_ffi_open(const char *profile_dir, int32_t flags)'),
    close: f('void mozc_ffi_close(mozc_ffi *mozc)'),
    convert: f('mozc_ffi_result *mozc_ffi_convert(mozc_ffi *mozc, const char *reading, const int32_t *lengths, int32_t n, const char *context)'),
    predict: f('mozc_ffi_result *mozc_ffi_predict(mozc_ffi *mozc, const char *reading, const char *context)'),
    segmentCount: f('int32_t mozc_ffi_segment_count(const mozc_ffi_result *result)'),
    segmentReading: f('const char *mozc_ffi_segment_reading(const mozc_ffi_result *result, int32_t segment)'),
    candidateCount: f('int32_t mozc_ffi_candidate_count(const mozc_ffi_result *result, int32_t segment)'),
    candidate: f('const char *mozc_ffi_candidate(const mozc_ffi_result *result, int32_t segment, int32_t index)'),
    description: f('const char *mozc_ffi_candidate_description(const mozc_ffi_result *result, int32_t segment, int32_t index)'),
    resultFree: f('void mozc_ffi_result_free(mozc_ffi_result *result)'),
    learn: f('int32_t mozc_ffi_learn(mozc_ffi *mozc, const char *reading, const int32_t *lengths, const char **texts, int32_t n, const char *context)'),
    clearLearning: f('int32_t mozc_ffi_clear_learning(mozc_ffi *mozc)'),
    flush: f('int32_t mozc_ffi_flush(mozc_ffi *mozc)'),
  };
  return api;
}

function lengthsArray(lengths) {
  if (!lengths || lengths.length === 0) return null;
  if (!lengths.every((n) => Number.isInteger(n) && n > 0 && n <= 0x7fffffff)) return undefined;
  return Int32Array.from(lengths);
}

/** One Mozc engine. Call close() (or use `using`) to save what was learned and free it. */
class Mozc {
  /**
   * @param {string|null} [profileDir] where Mozc keeps what it learns; null for Mozc's default
   * @param {{incognito?: boolean}} [options] incognito learns nothing and leaves the profile untouched
   */
  constructor(profileDir = null, { incognito = false } = {}) {
    this._api = load();
    this._error = '';
    this._handle = this._api.open(profileDir, incognito ? INCOGNITO : 0);
    if (!this._handle) throw new Error(`mozc_ffi_open failed: ${this._api.lastError()}`);
  }

  /** Mozc's version, such as "3.35.6354.102". */
  static get mozcVersion() {
    return load().mozcVersion();
  }

  /** Why the last convert, predict, learn, clearLearning or flush failed; '' if it succeeded. */
  get lastError() {
    return this._error;
  }

  /** Segments of the reading, best candidate first; [] if it can't be converted as asked. */
  convert(reading, lengths = null, context = '') {
    const sizes = lengthsArray(lengths);
    if (sizes === undefined) return this._fail('a segment length is not a positive integer', []);
    const result = this._api.convert(this._open(), reading, sizes, sizes ? sizes.length : 0, context);
    this._error = this._api.lastError();
    return this._read(result);
  }

  /** Completions of the reading typed so far. */
  predict(reading, context = '') {
    const result = this._api.predict(this._open(), reading, context);
    this._error = this._api.lastError();
    const segments = this._read(result);
    return segments.length > 0 ? segments[0].candidates : [];
  }

  /** Learns the picked texts, one per segment of lengths; false (nothing learned) on a mismatch. */
  learn(reading, lengths, texts, context = '') {
    const sizes = lengthsArray(lengths);
    if (!sizes) return this._fail('lengths must be positive integers, one per segment', false);
    if (!Array.isArray(texts) || texts.length !== sizes.length) {
      return this._fail('lengths and texts differ in length', false);
    }
    return this._ok(this._api.learn(this._open(), reading, sizes, texts, texts.length, context));
  }

  /** Forgets everything learned. */
  clearLearning() {
    return this._ok(this._api.clearLearning(this._open()));
  }

  /** Writes what was learned to the profile. */
  flush() {
    return this._ok(this._api.flush(this._open()));
  }

  /** Saves what was learned and frees the engine. Safe to call twice. */
  close() {
    if (this._handle) {
      this._api.close(this._handle);
      this._handle = null;
    }
  }

  [Symbol.dispose]() {
    this.close();
  }

  _open() {
    if (!this._handle) throw new Error('Mozc is closed');
    return this._handle;
  }

  _fail(why, value) {
    this._error = why;
    return value;
  }

  _ok(status) {
    this._error = this._api.lastError();
    return status === 1;
  }

  _read(result) {
    if (!result) return [];
    const a = this._api;
    try {
      const segments = [];
      for (let s = 0; s < a.segmentCount(result); s++) {
        const candidates = [];
        const descriptions = [];
        for (let c = 0; c < a.candidateCount(result, s); c++) {
          candidates.push(a.candidate(result, s, c));
          descriptions.push(a.description(result, s, c));
        }
        segments.push({ reading: a.segmentReading(result, s), candidates, descriptions });
      }
      return segments;
    } finally {
      a.resultFree(result);
    }
  }
}

module.exports = { Mozc, ABI_VERSION };
