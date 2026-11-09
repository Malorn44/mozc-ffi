# Builds build\mozc_ffi.dll from Mozc at the commit in MOZC_COMMIT.
#
#   .\build.ps1
#
# Needs: bazelisk on PATH (or $env:BAZELISK), Python 3.12+ as "python", Git,
# Visual Studio 2022 or 2026 with "Desktop development with C++" and
# "C++ ATL for latest build tools (x86 & x64)", and Windows Developer Mode
# (Mozc's Bazel config creates symlinks).
#
# Run it from a clone on a Windows drive such as C:\src\mozc-ffi, not from
# \\wsl.localhost: Bazel can't build on a network path. Mozc is fetched into
# third_party\mozc (not tracked) along with the LLVM and MSYS2 it builds with.
# The first build downloads about 1 GB and takes a while.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$commit = (Get-Content (Join-Path $root 'MOZC_COMMIT') -Raw).Trim()
$mozc = Join-Path $root 'third_party\mozc'
$bazelisk = if ($env:BAZELISK) { $env:BAZELISK } else { 'bazelisk' }

function Invoke-Checked([string]$exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "$exe $($arguments -join ' ') failed with exit code $LASTEXITCODE" }
}

function Stop-Missing([string]$what) {
    Write-Host "Missing: $what" -ForegroundColor Red
    exit 1
}

if ($root.StartsWith('\\')) { Stop-Missing 'a clone on a Windows drive; Bazel cannot build on a network path' }
if (-not (Get-Command $bazelisk -ErrorAction SilentlyContinue)) { Stop-Missing 'bazelisk on PATH (or set $env:BAZELISK)' }
$pythonVersion = & python -c 'import sys; print(sys.version_info >= (3, 12))' 2>$null
if ($pythonVersion -ne 'True') { Stop-Missing 'Python 3.12 or later as "python"' }
$devMode = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue
if (-not $devMode -or $devMode.AllowDevelopmentWithoutDevLicense -ne 1) {
    Stop-Missing 'Developer Mode (Settings > System > For developers)'
}

if (-not (Test-Path (Join-Path $mozc '.git'))) {
    Invoke-Checked git @('clone', '--filter=blob:none', '--no-checkout', 'https://github.com/google/mozc', $mozc)
}
$head = & git -C $mozc rev-parse HEAD 2>$null
if ($head -ne $commit) {
    Invoke-Checked git @('-C', $mozc, 'fetch', '--filter=blob:none', 'origin', $commit)
    Invoke-Checked git @('-C', $mozc, 'checkout', '--quiet', $commit)
}

Push-Location (Join-Path $mozc 'src')
try {
    # Mozc builds with the Visual Studio this picks (2022 when both are installed); it needs ATL.
    $vc = (& python build_tools/vs_util.py).Trim()
    if (-not (Get-ChildItem (Join-Path $vc 'Tools\MSVC\*\atlmfc\include\atlbase.h') -ErrorAction SilentlyContinue)) {
        Stop-Missing "C++ ATL in $vc (Visual Studio Installer > Modify > Individual components)"
    }

    # core\ goes into Mozc's source tree as //mozc_ffi.
    $target = Join-Path (Get-Location) 'mozc_ffi'
    if (Test-Path $target) { Remove-Item -Recurse -Force $target }
    Copy-Item -Recurse (Join-Path $root 'core') $target

    # LLVM (clang-cl) and MSYS2 (bash for build rules); Qt, Ninja and the installer tools aren't needed.
    if (-not (Test-Path 'third_party\llvm\bin\clang-cl.exe') -or -not (Test-Path 'third_party\msys64\usr\bin\bash.exe')) {
        Invoke-Checked python @('build_tools/update_deps.py', '--noqt', '--noninja', '--nowix', '--nondk')
    }

    Invoke-Checked $bazelisk @('build', '--config', 'release_build',
        "--downloader_config=$(Join-Path $root 'bazel_downloader.cfg')", '//mozc_ffi:mozc_ffi.dll')
    New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
    Copy-Item -Force 'bazel-bin\mozc_ffi\mozc_ffi.dll' (Join-Path $root 'build')
}
finally {
    Pop-Location
}
Write-Host "Built $(Join-Path $root 'build\mozc_ffi.dll')"
