//! Rust bindings for mozc-ffi: Mozc's kana-kanji converter, in process.
//!
//! ```no_run
//! let mozc = mozc_ffi::Mozc::open(Some(std::path::Path::new("/path/to/profile")), false)?;
//! let segments = mozc.convert("きょうはさむいですね", &[], ""); // 今日は / 寒いですね
//! let segments = mozc.convert("ここではきものをぬぐ", &[3, 5, 2], ""); // ここで / はきものを / ぬぐ
//! mozc.learn("ここではきものをぬぐ", &[3, 5, 2], &["ここで", "履物を", "脱ぐ"], ""); // ranks first next time
//! let completions = mozc.predict("ありがと", ""); // ありがとうございます, ありがとう, …
//! # Ok::<(), mozc_ffi::Error>(())
//! ```
//!
//! The native library (`mozc_ffi.dll`, `libmozc_ffi.so`) is loaded when a `Mozc` opens: from the
//! `MOZC_FFI_LIBRARY` environment variable, next to the executable, where the `download` feature
//! put it ([`DOWNLOADED_LIBRARY`]), or the system's library path.
//!
//! The crate holds no native library. Either enable the `download` feature, which fetches this
//! version's library from its GitHub release when building and checks its SHA-256, or download
//! the release archive yourself. Every call is self-contained. Mozc keeps the profile directory
//! per process, so open one profile per process.
//!
//! The [guide](https://mozc-ffi.readthedocs.io/stable/rust/) covers installing, the calls,
//! profiles and errors.

use std::ffi::{c_char, c_void, CStr, CString};
use std::fmt;
use std::mem::ManuallyDrop;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::Mutex;

use libloading::Library;

/// The C API version these bindings speak.
pub const ABI_VERSION: i32 = 2;
const INCOGNITO: i32 = 1;
const BAD_ARGUMENT: &str = "a string contains NUL, or a length is too large";

/// Where the `download` feature put the native library when this crate was built; `None`
/// without the feature.
pub const DOWNLOADED_LIBRARY: Option<&str> = option_env!("MOZC_FFI_DOWNLOADED");

/// A segment of the reading and its candidates, best first.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment {
    pub reading: String,
    pub candidates: Vec<String>,
    /// Mozc's note on each candidate (its script, an emoji's name), in Japanese; "" if none.
    pub descriptions: Vec<String>,
}

#[derive(Debug)]
pub enum Error {
    /// The native library could not be loaded.
    Load(libloading::Error),
    /// The native library speaks another version of the C API.
    Abi { found: i32 },
    /// The profile path is not valid UTF-8 or contains NUL.
    Path,
    /// Mozc could not start, and why.
    Open(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Load(error) => write!(f, "could not load mozc_ffi: {error}"),
            Error::Abi { found } => write!(
                f,
                "mozc_ffi has ABI {found}, these bindings need {ABI_VERSION}"
            ),
            Error::Path => write!(f, "the profile path must be UTF-8 without NUL"),
            Error::Open(why) => write!(f, "mozc_ffi_open failed: {why}"),
        }
    }
}

impl std::error::Error for Error {}

type Handle = *mut c_void;
type Result = *mut c_void;

/// The C functions, kept with the library that holds them.
struct Api {
    mozc_version: unsafe extern "C" fn() -> *const c_char,
    last_error: unsafe extern "C" fn() -> *const c_char,
    open: unsafe extern "C" fn(*const c_char, i32) -> Handle,
    close: unsafe extern "C" fn(Handle),
    convert: unsafe extern "C" fn(Handle, *const c_char, *const i32, i32, *const c_char) -> Result,
    predict: unsafe extern "C" fn(Handle, *const c_char, *const c_char) -> Result,
    segment_count: unsafe extern "C" fn(Result) -> i32,
    segment_reading: unsafe extern "C" fn(Result, i32) -> *const c_char,
    candidate_count: unsafe extern "C" fn(Result, i32) -> i32,
    candidate: unsafe extern "C" fn(Result, i32, i32) -> *const c_char,
    candidate_description: unsafe extern "C" fn(Result, i32, i32) -> *const c_char,
    result_free: unsafe extern "C" fn(Result),
    learn: unsafe extern "C" fn(
        Handle,
        *const c_char,
        *const i32,
        *const *const c_char,
        i32,
        *const c_char,
    ) -> i32,
    clear_learning: unsafe extern "C" fn(Handle) -> i32,
    flush: unsafe extern "C" fn(Handle) -> i32,
    // Never unloaded: Mozc keeps global state and background threads that don't survive
    // unloading, as other languages' loaders (ctypes, P/Invoke, koffi) never unload it either.
    _library: ManuallyDrop<Library>,
}

impl Api {
    fn load(path: &Path) -> std::result::Result<Api, Error> {
        // SAFETY: loading runs the library's initializers; mozc_ffi's are Mozc's own.
        let library = unsafe { Library::new(path) }.map_err(Error::Load)?;
        // SAFETY: each symbol is declared with the signature in mozc_ffi.h, and the pointers
        // stay valid because `_library` lives as long as they do.
        unsafe {
            macro_rules! symbol {
                ($name:literal) => {
                    *library.get($name).map_err(Error::Load)?
                };
            }
            let abi_version: unsafe extern "C" fn() -> i32 = symbol!(b"mozc_ffi_abi_version\0");
            let found = abi_version();
            if found != ABI_VERSION {
                return Err(Error::Abi { found });
            }
            Ok(Api {
                mozc_version: symbol!(b"mozc_ffi_mozc_version\0"),
                last_error: symbol!(b"mozc_ffi_last_error\0"),
                open: symbol!(b"mozc_ffi_open\0"),
                close: symbol!(b"mozc_ffi_close\0"),
                convert: symbol!(b"mozc_ffi_convert\0"),
                predict: symbol!(b"mozc_ffi_predict\0"),
                segment_count: symbol!(b"mozc_ffi_segment_count\0"),
                segment_reading: symbol!(b"mozc_ffi_segment_reading\0"),
                candidate_count: symbol!(b"mozc_ffi_candidate_count\0"),
                candidate: symbol!(b"mozc_ffi_candidate\0"),
                candidate_description: symbol!(b"mozc_ffi_candidate_description\0"),
                result_free: symbol!(b"mozc_ffi_result_free\0"),
                learn: symbol!(b"mozc_ffi_learn\0"),
                clear_learning: symbol!(b"mozc_ffi_clear_learning\0"),
                flush: symbol!(b"mozc_ffi_flush\0"),
                _library: ManuallyDrop::new(library),
            })
        }
    }
}

/// One Mozc engine. Dropping it saves what was learned.
pub struct Mozc {
    api: Api,
    handle: Handle,
    error: Mutex<String>,
}

// SAFETY: mozc_ffi serializes the calls on one handle.
unsafe impl Send for Mozc {}
unsafe impl Sync for Mozc {}

impl Mozc {
    /// Opens Mozc with the default library. `profile_dir` keeps what it learns (None: Mozc's
    /// default); `incognito` learns nothing and leaves the profile untouched.
    pub fn open(profile_dir: Option<&Path>, incognito: bool) -> std::result::Result<Mozc, Error> {
        Mozc::open_with_library(&default_library(), profile_dir, incognito)
    }

    /// Opens Mozc with the native library at `library`.
    pub fn open_with_library(
        library: &Path,
        profile_dir: Option<&Path>,
        incognito: bool,
    ) -> std::result::Result<Mozc, Error> {
        let api = Api::load(library)?;
        let profile = match profile_dir {
            Some(dir) => Some(
                dir.to_str()
                    .and_then(|s| CString::new(s).ok())
                    .ok_or(Error::Path)?,
            ),
            None => None,
        };
        let flags = if incognito { INCOGNITO } else { 0 };
        // SAFETY: the profile string outlives the call; NULL means Mozc's default.
        let handle =
            unsafe { (api.open)(profile.as_ref().map_or(ptr::null(), |p| p.as_ptr()), flags) };
        if handle.is_null() {
            // SAFETY: a static NUL-terminated string.
            return Err(Error::Open(unsafe { text((api.last_error)()) }));
        }
        Ok(Mozc {
            api,
            handle,
            error: Mutex::new(String::new()),
        })
    }

    /// Mozc's version, such as "3.35.6354.102".
    pub fn mozc_version(&self) -> String {
        // SAFETY: a static NUL-terminated string.
        unsafe { text((self.api.mozc_version)()) }
    }

    /// Why the last `convert`, `predict`, `learn`, `clear_learning` or `flush` on this `Mozc`
    /// failed; empty if it succeeded.
    pub fn last_error(&self) -> String {
        self.error.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// Segments of `reading` with candidates, best first. `lengths` (one per segment, in
    /// characters) fixes the segments, or is empty to let Mozc choose; `context` is the text
    /// just before the reading, or "". Empty if it can't be converted as asked.
    pub fn convert(&self, reading: &str, lengths: &[usize], context: &str) -> Vec<Segment> {
        let (Ok(reading), Ok(context), Some(lengths)) = (
            CString::new(reading),
            CString::new(context),
            to_i32(lengths),
        ) else {
            return self.fail(BAD_ARGUMENT, Vec::new());
        };
        // SAFETY: every pointer outlives the call; lengths has `lengths.len()` entries.
        let result = unsafe {
            (self.api.convert)(
                self.handle,
                reading.as_ptr(),
                lengths.as_ptr(),
                lengths.len() as i32,
                context.as_ptr(),
            )
        };
        self.note();
        self.read(result)
    }

    /// Completions of `reading` typed so far.
    pub fn predict(&self, reading: &str, context: &str) -> Vec<String> {
        let (Ok(reading), Ok(context)) = (CString::new(reading), CString::new(context)) else {
            return self.fail(BAD_ARGUMENT, Vec::new());
        };
        // SAFETY: both strings outlive the call.
        let result = unsafe { (self.api.predict)(self.handle, reading.as_ptr(), context.as_ptr()) };
        self.note();
        self.read(result)
            .into_iter()
            .next()
            .map_or_else(Vec::new, |segment| segment.candidates)
    }

    /// Learns a sent conversion: `texts[i]` picked for the segment of `lengths[i]`, so the picks
    /// rank first next time. False, and nothing learned, if a text isn't a candidate.
    pub fn learn(&self, reading: &str, lengths: &[usize], texts: &[&str], context: &str) -> bool {
        if lengths.is_empty() || lengths.len() != texts.len() {
            return self.fail(
                "lengths and texts must be the same length, and not empty",
                false,
            );
        }
        let (Ok(reading), Ok(context), Some(lengths)) = (
            CString::new(reading),
            CString::new(context),
            to_i32(lengths),
        ) else {
            return self.fail(BAD_ARGUMENT, false);
        };
        let Ok(texts) = texts
            .iter()
            .map(|t| CString::new(*t))
            .collect::<std::result::Result<Vec<_>, _>>()
        else {
            return self.fail(BAD_ARGUMENT, false);
        };
        let pointers: Vec<*const c_char> = texts.iter().map(|t| t.as_ptr()).collect();
        // SAFETY: every pointer outlives the call; the arrays have `pointers.len()` entries.
        let status = unsafe {
            (self.api.learn)(
                self.handle,
                reading.as_ptr(),
                lengths.as_ptr(),
                pointers.as_ptr(),
                pointers.len() as i32,
                context.as_ptr(),
            )
        };
        self.note();
        status == 1
    }

    /// Forgets everything learned.
    pub fn clear_learning(&self) -> bool {
        // SAFETY: the handle is open until drop.
        let status = unsafe { (self.api.clear_learning)(self.handle) };
        self.note();
        status == 1
    }

    /// Writes what was learned to the profile.
    pub fn flush(&self) -> bool {
        // SAFETY: the handle is open until drop.
        let status = unsafe { (self.api.flush)(self.handle) };
        self.note();
        status == 1
    }

    /// Keeps the library's reason for the call just made on this thread.
    fn note(&self) {
        // SAFETY: a static NUL-terminated string.
        let why = unsafe { text((self.api.last_error)()) };
        *self.error.lock().unwrap_or_else(|e| e.into_inner()) = why;
    }

    fn fail<T>(&self, why: &str, value: T) -> T {
        *self.error.lock().unwrap_or_else(|e| e.into_inner()) = why.to_owned();
        value
    }

    fn read(&self, result: Result) -> Vec<Segment> {
        if result.is_null() {
            return Vec::new();
        }
        let api = &self.api;
        // SAFETY: the result is valid until result_free; its strings are NUL-terminated UTF-8.
        unsafe {
            let segments = (0..(api.segment_count)(result))
                .map(|s| Segment {
                    reading: text((api.segment_reading)(result, s)),
                    candidates: (0..(api.candidate_count)(result, s))
                        .map(|c| text((api.candidate)(result, s, c)))
                        .collect(),
                    descriptions: (0..(api.candidate_count)(result, s))
                        .map(|c| text((api.candidate_description)(result, s, c)))
                        .collect(),
                })
                .collect();
            (api.result_free)(result);
            segments
        }
    }
}

impl Drop for Mozc {
    fn drop(&mut self) {
        // SAFETY: closed once, here.
        unsafe { (self.api.close)(self.handle) }
    }
}

fn default_library() -> PathBuf {
    if let Some(path) = std::env::var_os("MOZC_FFI_LIBRARY") {
        return PathBuf::from(path);
    }
    let name = if cfg!(windows) {
        "mozc_ffi.dll"
    } else if cfg!(target_os = "macos") {
        "libmozc_ffi.dylib"
    } else {
        "libmozc_ffi.so"
    };
    let beside = std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join(name)));
    match (beside, DOWNLOADED_LIBRARY) {
        (Some(path), _) if path.exists() => path,
        (_, Some(path)) if Path::new(path).exists() => PathBuf::from(path),
        _ => PathBuf::from(name),
    }
}

fn to_i32(values: &[usize]) -> Option<Vec<i32>> {
    values.iter().map(|&v| i32::try_from(v).ok()).collect()
}

/// # Safety
/// `text` is NULL or a NUL-terminated string.
unsafe fn text(text: *const c_char) -> String {
    if text.is_null() {
        String::new()
    } else {
        CStr::from_ptr(text).to_string_lossy().into_owned()
    }
}
