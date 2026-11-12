# mozc-ffi

[English](README.md) | 日本語

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を使うための、非公式の C API と各言語のバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC もインストールも不要です。Google とは提携関係にありません。

呼び出しはそれぞれ独立しています。読みと、必要に応じて文節の長さと直前の文を渡すと、文節ごとの候補が返ってきます。`learn` で学習させた候補は、次回から先頭に並びます。

## 対応言語

どのパッケージにもビルド済みのライブラリが入っています。対応環境は Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。インストール方法、使用例、ライブラリの読み込み方は、各言語の README にあります。

| | インストール | 必要なもの | |
|---|---|---|---|
| Python | `pip install mozc-ffi` | Python 3.11 以降 | [README](bindings/python/README.ja.md) |
| C# | `dotnet add package MozcFfi` | .NET Standard 2.0 | [README](bindings/csharp/README.ja.md) |
| Unity | npm の `com.malorn44.mozc-ffi` パッケージ | Unity 2021.3 以降、Windows または Linux の x64 | [README](bindings/unity/README.ja.md) |
| Node.js | `npm install mozc-ffi` | Node.js 22 以降 | [README](bindings/node/README.ja.md) |
| Rust | `cargo add mozc-ffi --features download` | Rust 1.88 以降 | [README](bindings/rust/README.ja.md) |
| C | [Releases](https://github.com/Malorn44/mozc-ffi/releases) のアーカイブ | | [下記](#c) |

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    segments = mozc.convert("きょうはさむいですね")
    print("".join(s.candidates[0] for s in segments))  # 今日は寒いですね
```

要求どおりに処理できなかった呼び出しは、空のリストまたは false を返します。理由は `last_error` で英語の文として取得でき、入力された文字列がそこに含まれることはありません。文節の長さは Unicode の文字数で数えます。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。`incognito` を指定すると何も学習しません。

## C

アーカイブには、ヘッダー、ライブラリ、そして Windows 用にはインポートライブラリが入っています。チェックサムは `SHA256SUMS` にあります。すべての関数の説明は [`mozc_ffi.h`](core/mozc_ffi.h) にあります。

```c
#include <stdio.h>

#include "mozc_ffi.h"

int main(void) {
  mozc_ffi* mozc = mozc_ffi_open("/path/to/profile", 0);
  if (mozc == NULL) {
    fprintf(stderr, "%s\n", mozc_ffi_last_error());
    return 1;
  }
  mozc_ffi_result* result = mozc_ffi_convert(mozc, "きょうはさむいですね", NULL, 0, NULL);
  for (int32_t s = 0; s < mozc_ffi_segment_count(result); s++) {
    fputs(mozc_ffi_candidate(result, s, 0), stdout);  // 今日は寒いですね
  }
  putchar('\n');
  mozc_ffi_result_free(result);
  mozc_ffi_close(mozc);
  return 0;
}
```

```sh
cc -std=c99 -Iinclude example.c -Llib -lmozc_ffi -o example
LD_LIBRARY_PATH=lib ./example
```

文字列はすべて UTF-8 です。結果の文字列は `mozc_ffi_result_free` を呼ぶまで有効です。1 つのハンドルは複数のスレッドから使え、呼び出しは順番に処理されます。

## リポジトリ

| | |
|---|---|
| `core/` | C API（`mozc_ffi.h`）と、Mozc の変換エンジンを使ったその実装 |
| `bindings/python/` | Python バインディング（ctypes、1 モジュール）と README、テスト |
| `bindings/csharp/` | C# バインディング（netstandard2.0、Unity でも動作）と README、テスト |
| `bindings/unity/` | Unity パッケージ用のファイル（`package.json`、README、`.meta`）。`scripts/package.sh` が C# バインディングとライブラリを加えます |
| `bindings/rust/` | Rust バインディング（`mozc-ffi` クレート）と README、テスト |
| `bindings/node/` | Node.js バインディング（koffi、TypeScript の型定義付き）と README、テスト |
| `scripts/` | ビルドスクリプト、`check.sh`（すべての lint とテスト）、固定した Mozc のコミット（`MOZC_COMMIT`） |
| `tests/` | すべてのテストで使う日常的なチャットの文例 `chat.tsv` と、API を使う C プログラム `smoke.c` |

各パッケージの README は `bindings/` の各ディレクトリにあるもので、PyPI、NuGet、npm、crates.io にもそれが表示されます。

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

## テスト

```sh
scripts/check.sh              # すべての lint を実行してから、すべてのテスト
scripts/check.sh lint python  # lint を 1 つだけ: c, python, csharp, rust, node, scripts
scripts/check.sh test rust    # 1 つのバインディングのテスト: c, csharp, python, node, rust
```

テストは `build/` にあるライブラリを使います。各バインディングのテストでは、その README の使用例も実行し、コメントに書いたとおりの出力になるかを確かめます。CI はすべてのプルリクエストで、同じコマンドを Linux と Windows で実行します。

## リリース

リリースは、Conventional Commits 形式の PR タイトルをもとに release-please が作成します。手順は [.github/RELEASING.md](.github/RELEASING.md) を参照してください。

## ライセンス

BSD-3-Clause です。ビルドしたライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) に記載しています。
