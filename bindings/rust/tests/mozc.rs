//! Tests against the library in build/ (or MOZC_FFI_LIBRARY): cargo test

use std::path::{Path, PathBuf};
use std::sync::{Mutex, MutexGuard, OnceLock};

use mozc_ffi::{Mozc, Segment, ABI_VERSION};

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .unwrap()
        .to_path_buf()
}

fn library() -> PathBuf {
    match std::env::var_os("MOZC_FFI_LIBRARY") {
        Some(path) => PathBuf::from(path),
        None => root().join("build").join(if cfg!(windows) {
            "mozc_ffi.dll"
        } else {
            "libmozc_ffi.so"
        }),
    }
}

/// Mozc keeps one profile per process, and tests run in parallel: take turns on one profile.
fn profile() -> (MutexGuard<'static, ()>, &'static Path) {
    static LOCK: Mutex<()> = Mutex::new(());
    static DIR: OnceLock<PathBuf> = OnceLock::new();
    let guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let dir = DIR
        .get_or_init(|| std::env::temp_dir().join(format!("mozc-ffi-rs-{}", std::process::id())));
    (guard, dir)
}

fn open(dir: &Path, incognito: bool) -> Mozc {
    Mozc::open_with_library(&library(), Some(dir), incognito).expect("open")
}

fn first(segments: &[Segment]) -> String {
    segments.iter().map(|s| s.candidates[0].as_str()).collect()
}

/// Whether picking one candidate per segment can spell `target`.
fn reachable(target: &str, segments: &[Segment]) -> bool {
    let mut ends = vec![0usize];
    for segment in segments {
        ends = ends
            .iter()
            .flat_map(|&e| {
                segment
                    .candidates
                    .iter()
                    .filter(move |c| target[e..].starts_with(c.as_str()))
                    .map(move |c| e + c.len())
            })
            .collect();
    }
    ends.contains(&target.len())
}

#[test]
fn converts_and_predicts() {
    let (_guard, dir) = profile();
    let mozc = open(dir, true);
    assert_eq!(ABI_VERSION, 2);
    assert_eq!(mozc.mozc_version().split('.').count(), 4);

    let segments = mozc.convert("きょうはさむいですね", &[], "");
    assert_eq!(
        segments
            .iter()
            .map(|s| s.reading.as_str())
            .collect::<String>(),
        "きょうはさむいですね"
    );
    assert_eq!(first(&segments), "今日は寒いですね");

    let segments = mozc.convert("ここではきものをぬぐ", &[3, 5, 2], "");
    let readings: Vec<_> = segments.iter().map(|s| s.reading.as_str()).collect();
    assert_eq!(readings, ["ここで", "はきものを", "ぬぐ"]);
    assert!(segments[1].candidates.iter().any(|c| c == "履物を"));

    assert!(mozc.convert("ここではきものをぬぐ", &[3, 3], "").is_empty());
    assert!(mozc.last_error().contains("do not add up"));
    assert!(mozc.convert("", &[], "").is_empty());
    assert!(mozc.last_error().contains("empty"));
    assert!(mozc.convert("nul\0inside", &[], "").is_empty());
    assert!(mozc.last_error().contains("NUL"));
    assert!(!mozc.learn("かんじ", &[3], &["not a candidate"], ""));
    assert!(mozc.last_error().contains("not a candidate"));
    assert!(!mozc.convert("かんじ", &[], "").is_empty());
    assert_eq!(mozc.last_error(), "");

    let kanji = &mozc.convert("かんじ", &[3], "")[0];
    assert_eq!(kanji.descriptions.len(), kanji.candidates.len());
    let katakana = kanji.candidates.iter().position(|c| c == "カンジ").unwrap();
    assert_eq!(kanji.descriptions[katakana], "カタカナ");

    let candidates = &mozc.convert("かんじ", &[3], "")[0].candidates;
    let mut unique = candidates.clone();
    unique.sort();
    unique.dedup();
    assert_eq!(unique.len(), candidates.len());

    assert!(mozc
        .predict("ありがと", "")
        .iter()
        .any(|p| p.starts_with("ありがとう")));
    assert_eq!(
        first(&mozc.convert("さむいですね", &[], "今日は")),
        "寒いですね"
    );
}

#[test]
fn chat_quality() {
    let (_guard, dir) = profile();
    let mozc = open(dir, true);
    let chat = std::fs::read_to_string(root().join("tests/chat.tsv")).unwrap();
    let cases: Vec<(&str, Vec<&str>)> = chat
        .lines()
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| {
            let (reading, answers) = l.split_once('\t').unwrap();
            (reading, answers.split('|').collect())
        })
        .collect();
    let (mut top1, mut picks) = (0, 0);
    for (reading, answers) in &cases {
        let segments = mozc.convert(reading, &[], "");
        top1 += answers.contains(&first(&segments).as_str()) as usize;
        picks += answers.iter().any(|a| reachable(a, &segments)) as usize;
    }
    println!(
        "chat.tsv: top-1 {top1}/{}, reachable by picks {picks}/{}",
        cases.len(),
        cases.len()
    );
    assert!(top1 * 100 >= cases.len() * 80);
    assert!(picks * 100 >= cases.len() * 95);
}

#[test]
fn learns_persists_and_clears() {
    let (_guard, dir) = profile();
    let pick;
    let before;
    {
        let mozc = open(dir, false);
        before = mozc.convert("かんじ", &[3], "")[0].candidates.clone();
        pick = before[1].clone();
        assert_ne!(pick, before[0]);
        assert!(mozc.learn("かんじ", &[3], &[pick.as_str()], ""));
        assert_eq!(mozc.convert("かんじ", &[3], "")[0].candidates[0], pick);
        assert!(!mozc.learn("かんじ", &[3], &["not a candidate"], ""));
        assert!(!mozc.learn("かんじ", &[2, 1], &["かん"], ""));
        assert!(mozc.flush());
    }
    {
        let mozc = open(dir, false);
        assert_eq!(mozc.convert("かんじ", &[3], "")[0].candidates[0], pick);
        assert!(mozc.clear_learning());
        assert_eq!(mozc.convert("かんじ", &[3], "")[0].candidates[0], before[0]);
    }
    {
        let mozc = open(dir, true);
        let before = mozc.convert("はし", &[2], "")[0].candidates.clone();
        mozc.learn("はし", &[2], &[before[1].as_str()], "");
        assert_eq!(mozc.convert("はし", &[2], "")[0].candidates[0], before[0]);
    }
}
