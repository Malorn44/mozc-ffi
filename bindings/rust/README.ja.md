# mozc-ffi（Rust）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/rust/README.md) | 日本語

<!-- --8<-- [start:guide] -->

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を Rust から使うためのバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC もインストールも不要です。非公式のもので、Google とは提携関係にありません。

## インストール

```sh
cargo add mozc-ffi --features download
```

Rust 1.88 以降が必要です。対応環境は Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。

ネイティブライブラリが crates.io の上限より大きいため、クレートに入っているのはバインディングだけです。`download` フィーチャーを有効にすると、ビルド時にそのバージョンの [GitHub のリリース](https://github.com/Malorn44/mozc-ffi/releases) からライブラリを取得し、SHA-256 を検証します（`curl` と `tar` が必要です）。フィーチャーを使わない場合は、リリースから使用する環境のアーカイブを自分でダウンロードしてください。

## 使い方

```rust no_run
use std::path::Path;

use mozc_ffi::Mozc;

fn main() -> Result<(), mozc_ffi::Error> {
    let mozc = Mozc::open(Some(Path::new("/path/to/profile")), false)?;
    let best = |reading: &str| -> String {
        let segments = mozc.convert(reading, &[], "");
        segments.iter().map(|s| s.candidates[0].as_str()).collect()
    };
    println!("{}", best("きょうはさむいですね")); // 今日は寒いですね

    // 文節の長さを指定: ここで / はきものを / ぬぐ
    let segments = mozc.convert("ここではきものをぬぐ", &[3, 5, 2], "");
    println!("{:?}", &segments[1].candidates[..2]); // ["は着物を", "履物を"]

    // ユーザーが送った変換は、次回から先頭に並ぶ
    mozc.learn("ここではきものをぬぐ", &[3, 5, 2], &["ここで", "履物を", "脱ぐ"], "");
    println!("{}", best("ここではきものをぬぐ")); // ここで履物を脱ぐ

    println!("{:?}", &mozc.predict("ありがと", "")[..2]); // ["ありがとうございます", "ありがとう"]
    Ok(())
}
```

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前の文を渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。

| | |
|---|---|
| `convert(reading, lengths, context)` | `Segment`（`reading`、`candidates`、`descriptions`）の一覧。候補は良い順です。`lengths` で文節の区切りを指定でき、`&[]` なら Mozc が決めます。`context` は読みの直前の文で、最初の文節の変換の助けになります。なければ `""`。 |
| `predict(reading, context)` | 入力途中の読みの補完候補。良い順です。 |
| `learn(reading, lengths, texts, context)` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から先頭に並べます。候補にないテキストがあると `false` を返し、何も学習しません。 |
| `clear_learning()` | 学習した内容をすべて消します。 |
| `flush()` | 学習した内容をすぐにプロファイルへ書き込みます。`Mozc` を drop したときにも書き込まれます。 |
| `last_error()` | 直前の呼び出しが失敗した理由（英語）。成功していれば `""`。入力された文字列は含みません。 |
| `mozc_version()` | Mozc のバージョン（例: `"2.32.5994.102"`）。 |

文節の長さはバイト数ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。`descriptions` には各候補についての Mozc の注記（例: `カタカナ`）が日本語で入り、注記がなければ `""` です。

要求どおりに処理できなかった呼び出しは空の `Vec` または `false` を返し、理由は `last_error()` で分かります。ライブラリを読み込めない場合、ABI が異なる場合、Mozc を起動できない場合、`Mozc::open` は `Error` を返します。

`Mozc` は `Send` かつ `Sync` です。1 つの `Mozc` への呼び出しは順番に処理されます。

## プロファイル

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。`None` を渡すと Mozc の既定の場所（Linux では `~/.mozc`）を使います。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。`incognito` を `true` にして開くと、何も学習せず、プロファイルにも触れません。

## ライブラリの読み込み

`Mozc::open` は、次の順で最初に見つかったライブラリを読み込みます。

1. 環境変数 `MOZC_FFI_LIBRARY`
2. 実行ファイルと同じ場所
3. `download` フィーチャーが置いた場所（`mozc_ffi::DOWNLOADED_LIBRARY`）
4. システムのライブラリパス

`Mozc::open_with_library` を使うと、パスを直接指定できます。一度読み込んだライブラリは、プロセスが終了するまで読み込まれたままです。

プログラムを配布するときは、ライブラリ（`libmozc_ffi.so` または `mozc_ffi.dll`）を実行ファイルと同じ場所にコピーしてください。`download` フィーチャーを使った場合、その場所は `mozc_ffi::DOWNLOADED_LIBRARY` で分かります。

<!-- --8<-- [end:guide] -->

## 関連情報

- [ドキュメント](https://malorn44.github.io/mozc-ffi/ja/rust/)と [API リファレンス](https://docs.rs/mozc-ffi)
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md) に記載しています。
