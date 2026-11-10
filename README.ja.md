# mozc-ffi

[English](README.md) | 日本語

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を使うための、非公式の C API と各言語のバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC もインストールも不要です。Google とは提携関係にありません。

呼び出しはそれぞれ独立しています。読みと、必要に応じて文節の長さと直前の文を渡すと、文節ごとの候補が返ってきます。`learn` で学習させた候補は、次回から先頭に並びます。

| | |
|---|---|
| `core/` | C API（`mozc_ffi.h`）と、Mozc の変換エンジンを使ったその実装 |
| `bindings/python/` | Python バインディング（ctypes、1 モジュール）とテスト |
| `bindings/csharp/` | C# バインディング（netstandard2.0、Unity でも動作）とテスト |
| `bindings/unity/` | Unity パッケージ用のファイル（`package.json` と `.meta`）。`scripts/package.sh` が C# バインディングとライブラリを加えます |
| `bindings/rust/` | Rust バインディング（`mozc-ffi` クレート）とテスト |
| `bindings/node/` | Node.js バインディング（koffi、TypeScript の型定義付き）とテスト |
| `scripts/` | ビルドスクリプト、`check.sh`（すべての lint とテスト）、固定した Mozc のコミット（`MOZC_COMMIT`） |
| `tests/` | すべてのテストで使う日常的なチャットの文例 `chat.tsv` と、API を使う C プログラム `smoke.c` |

## インストール

どのパッケージにもビルド済みのライブラリが入っています。対応環境は Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。

| | インストール | 必要なもの |
|---|---|---|
| Python | `pip install mozc-ffi` | Python 3.11 以降 |
| C# | `dotnet add package MozcFfi` | .NET Standard 2.0 |
| Unity | `com.malorn44.mozc-ffi` パッケージ（下記） | Unity 2021.3 以降、Windows または Linux の x64 |
| Node.js | `npm install mozc-ffi` | Node.js 22 以降 |
| Rust | `cargo add mozc-ffi --features download` | Rust 1.88 以降 |
| C | [Releases](https://github.com/Malorn44/mozc-ffi/releases) のアーカイブ | |

Rust のクレートに入っているのはバインディングだけです。ライブラリが crates.io の上限より大きいためです。`download` フィーチャーを有効にすると、ビルド時にそのバージョンのリリースからライブラリを取得し、SHA-256 を検証します（`curl` と `tar` が必要です）。

```sh
cargo add mozc-ffi --features download
```

プログラムを配布するときは、ライブラリ（`mozc_ffi::DOWNLOADED_LIBRARY`）を実行ファイルと同じ場所にコピーしてください。フィーチャーを使わない場合は、[Releases](https://github.com/Malorn44/mozc-ffi/releases) から使用する環境のアーカイブをダウンロードし、`libmozc_ffi.so` または `mozc_ffi.dll` を実行ファイルと同じ場所に置くか、`MOZC_FFI_LIBRARY` にそのパスを設定してください。

Unity では、プロジェクトの `Packages/manifest.json` に、npm をスコープ付きレジストリとして追加し、パッケージを依存関係に加えてください（既存の内容はそのまま残します）。パッケージには C# バインディングとライブラリが入っており、新しいバージョンは Package Manager に表示されます。

```json
{
  "scopedRegistries": [
    { "name": "npm", "url": "https://registry.npmjs.org", "scopes": ["com.malorn44"] }
  ],
  "dependencies": {
    "com.malorn44.mozc-ffi": "0.2.0"
  }
}
```

アーカイブには、ヘッダー、ライブラリ、そして Windows 用にはインポートライブラリが入っています。チェックサムは `SHA256SUMS` にあります。

## ビルド

ライブラリを自分でビルドする場合の手順です。どちらのスクリプトも、`scripts/MOZC_COMMIT` に書かれたコミットの Mozc を `build/mozc` に取得し、そのソースツリーの中で `core/` をビルドします。初回は Mozc の依存関係をダウンロードするため時間がかかります。ビルドしたものはすべて `build/` に入るので、このディレクトリを消せば完全なクリーンになります。

Linux では [Bazelisk](https://github.com/bazelbuild/bazelisk)、Git、GCC が必要です。

```sh
scripts/build.sh            # → build/libmozc_ffi.so
```

Windows では Bazelisk、Git、Python 3.12 以降、C++ ツールと C++ ATL を含む Visual Studio 2022 または 2026、そして開発者モードが必要です。クローンは Windows のドライブ上に置いてビルドしてください（`\\wsl.localhost` 上ではビルドできません）。

```powershell
.\scripts\build.ps1         # → build\mozc_ffi.dll
```

DLL は C++ ランタイムを静的リンクしているので、Visual C++ 再頒布可能パッケージは不要です。

## 使い方

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    mozc.convert("ここではきものをぬぐ", [3, 5, 2])  # [Segment("ここで", [...]), Segment("はきものを", ["履物を", ...]), ...]
    mozc.predict("ありがと")                     # ["ありがとう", ...]
    mozc.learn("かんじ", [3], ["感じ"])           # 次回から「感じ」が先頭に
```

```csharp
using var mozc = new MozcFfi.Mozc(profileDir);
var segments = mozc.Convert("きょうはさむいですね");   // segments[0].Candidates[0] == "今日は"
mozc.Learn("かんじ", new[] { 3 }, new[] { "感じ" });
```

```rust
let mozc = mozc_ffi::Mozc::open(Some(Path::new("/path/to/profile")), false)?;
let segments = mozc.convert("ここではきものをぬぐ", &[3, 5, 2], "");
mozc.learn("かんじ", &[3], &["感じ"], "");
```

```js
const { Mozc } = require('mozc-ffi');
const mozc = new Mozc('/path/to/profile');
mozc.convert('ここではきものをぬぐ', [3, 5, 2]);
mozc.learn('かんじ', [3], ['感じ']);
mozc.close();
```

各バインディングは Mozc を開くときにライブラリを読み込みます。読み込み元は `MOZC_FFI_LIBRARY`、プログラム（またはパッケージ）と同じ場所、またはシステムのライブラリパスです。一度読み込んだライブラリは、プロセスが終了するまで読み込まれたままです。

要求どおりに処理できなかった呼び出しは、空のリストまたは false を返します。理由は `last_error` で英語の文として取得でき、入力された文字列がそこに含まれることはありません。

文節の長さは Unicode の文字数で数えます。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。`incognito` を指定すると何も学習しません。

## テスト

```sh
scripts/check.sh              # すべての lint を実行してから、すべてのテスト
scripts/check.sh lint python  # lint を 1 つだけ: c, python, csharp, rust, node, scripts
scripts/check.sh test rust    # 1 つのバインディングのテスト: c, csharp, python, node, rust
```

テストは `build/` にあるライブラリを使います。CI はすべてのプルリクエストで、同じコマンドを Linux と Windows で実行します。

## リリース

リリースは、Conventional Commits 形式の PR タイトルをもとに release-please が作成します。手順は [.github/RELEASING.md](.github/RELEASING.md) を参照してください。

## ライセンス

BSD-3-Clause です。ビルドしたライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) に記載しています。
