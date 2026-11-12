# mozc-ffi

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を使うための、非公式の C API と各言語のバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC も Mozc 本体のインストールも不要です。Google とは関係ありません。

呼び出しはそれぞれ独立しています。読みと、必要に応じて文節の長さと直前のテキストを渡すと、文節ごとの候補が返ってきます。学習させた候補は、次回から第一候補になります。

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    segments = mozc.convert("きょうはさむいですね")
    print("".join(s.candidates[0] for s in segments))  # 今日は寒いですね
```

## 対応言語

どのパッケージにもビルド済みのライブラリが入っています。対応環境は Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。

| | インストール | 必要なもの |
|---|---|---|
| [Python](python.md) | `pip install mozc-ffi` | Python 3.10 以降 |
| [C#](csharp.md) | `dotnet add package MozcFfi` | .NET Standard 2.0 |
| [Unity](unity.md) | npm の `com.malorn44.mozc-ffi` パッケージ | Unity 2021.3 以降、Windows または Linux の x64 |
| [Node.js](node.md) | `npm install mozc-ffi` | Node.js 22 以降 |
| [Rust](rust.md) | `cargo add mozc-ffi --features download` | Rust 1.88 以降 |
| [C](c.md) | [Releases](https://github.com/Malorn44/mozc-ffi/releases) のアーカイブ | |

読み、文節、学習、プロファイルといった[呼び出しの仕組み](concepts.md)は、どの言語でも同じです。

## リンク

- [GitHub のソース](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)（ライブラリを自分でビルドする方法も README にあります）
- [Releases](https://github.com/Malorn44/mozc-ffi/releases) と[変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)
- [ライセンス](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md): mozc-ffi は BSD-3-Clause で、ライブラリには Mozc とその辞書が含まれています
