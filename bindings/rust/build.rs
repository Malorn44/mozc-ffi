//! With the `download` feature, fetches this version's native library from its GitHub release,
//! checks it against the SHA-256 published with the crate, and tells the crate where it is.
//! Without the feature this does nothing.

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=SHA256SUMS");
    #[cfg(feature = "download")]
    download::run();
}

#[cfg(feature = "download")]
mod download {
    use std::path::{Path, PathBuf};
    use std::process::Command;
    use std::{env, fs};

    use sha2::{Digest, Sha256};

    const RELEASES: &str = "https://github.com/Malorn44/mozc-ffi/releases/download";

    pub fn run() {
        let var = |name: &str| env::var(name).unwrap_or_else(|_| panic!("{name} is not set"));
        let version = var("CARGO_PKG_VERSION");
        let (os, arch) = (var("CARGO_CFG_TARGET_OS"), var("CARGO_CFG_TARGET_ARCH"));
        let (platform, extension, library) = match (os.as_str(), arch.as_str()) {
            ("linux", "x86_64") => ("linux-x64", "tar.gz", "lib/libmozc_ffi.so"),
            ("linux", "aarch64") => ("linux-arm64", "tar.gz", "lib/libmozc_ffi.so"),
            ("windows", "x86_64") => ("windows-x64", "zip", "bin/mozc_ffi.dll"),
            _ => panic!("mozc-ffi has no prebuilt library for {os} {arch}; build it and set MOZC_FFI_LIBRARY"),
        };
        let name = format!("mozc-ffi-{version}-{platform}");
        let archive = format!("{name}.{extension}");

        // SHA256SUMS is added when the crate is published; a checkout of the repository has none.
        let sums = Path::new(&var("CARGO_MANIFEST_DIR")).join("SHA256SUMS");
        let sums = fs::read_to_string(&sums).unwrap_or_else(|_| {
            panic!(
                "the download feature needs mozc-ffi from crates.io: {} is missing",
                sums.display()
            )
        });
        let expected = sums
            .lines()
            .filter_map(|line| line.split_once(char::is_whitespace))
            .find(|(_, file)| file.trim().trim_start_matches('*') == archive)
            .map(|(sum, _)| sum.to_lowercase())
            .unwrap_or_else(|| panic!("mozc-ffi {version} has no prebuilt library for {platform}"));

        let out = PathBuf::from(var("OUT_DIR"));
        let found = out.join(&name).join(library);
        if !found.exists() {
            let file = out.join(&archive);
            let url = format!("{RELEASES}/v{version}/{archive}");
            run_tool(
                "curl",
                &["-fsSL", "--retry", "3", "-o"],
                &[file.as_path()],
                &[&url],
            );
            let bytes = fs::read(&file).expect("read the downloaded archive");
            let actual: String = Sha256::digest(&bytes)
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect();
            if actual != expected {
                let _ = fs::remove_file(&file);
                panic!("{url} has SHA-256 {actual}, expected {expected}");
            }
            // GNU tar reads the tar.gz; Windows' own tar (bsdtar) also reads the zip.
            run_tool(
                "tar",
                &["-xf"],
                &[file.as_path(), Path::new("-C"), out.as_path()],
                &[],
            );
            let _ = fs::remove_file(&file);
        }
        assert!(found.exists(), "{archive} holds no {library}");
        println!("cargo:rustc-env=MOZC_FFI_DOWNLOADED={}", found.display());
    }

    fn run_tool(tool: &str, flags: &[&str], paths: &[&Path], rest: &[&str]) {
        let status = Command::new(tool)
            .args(flags)
            .args(paths)
            .args(rest)
            .status();
        match status {
            Ok(status) if status.success() => {}
            Ok(status) => panic!("{tool} failed ({status}) while fetching mozc-ffi's library"),
            Err(error) => panic!("the download feature needs {tool} on PATH: {error}"),
        }
    }
}
