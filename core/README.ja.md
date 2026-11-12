# mozc-ffi（C）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/core/README.md) | 日本語

<!-- --8<-- [start:guide] -->

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を使うための C API で、ほかのすべてのバインディングはこれをラップしています。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC も Mozc 本体のインストールも不要です。非公式のもので、Google とは関係ありません。

## インストール

[Releases](https://github.com/Malorn44/mozc-ffi/releases) から使用する環境のアーカイブをダウンロードしてください。

| アーカイブ | 中身 |
|---|---|
| `mozc-ffi-X.Y.Z-linux-x64.tar.gz`、`-linux-arm64.tar.gz` | `include/mozc_ffi.h`、`lib/libmozc_ffi.so` |
| `mozc-ffi-X.Y.Z-windows-x64.zip` | `include/mozc_ffi.h`、`bin/mozc_ffi.dll`、`lib/mozc_ffi.lib`（インポートライブラリ） |

チェックサムは `SHA256SUMS` にあります。ヘッダーは素の C99 です。

## 対応環境

Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。Windows の DLL は C++ ランタイムを静的リンクしているので、Visual C++ 再頒布可能パッケージは不要です。ほかの環境では、[リポジトリの README](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md#ビルド) の手順でライブラリを自分でビルドしてください。

## 使用例

```c
#include <stdio.h>

#include "mozc_ffi.h"

// 各文節の第一候補（Mozc が最有力とする変換）を出力する
static void print_best(mozc_ffi_result* result) {
  for (int32_t s = 0; s < mozc_ffi_segment_count(result); s++) {
    fputs(mozc_ffi_candidate(result, s, 0), stdout);
  }
  putchar('\n');
  mozc_ffi_result_free(result);
}

int main(void) {
  mozc_ffi* mozc = mozc_ffi_open("/path/to/profile", 0);
  if (mozc == NULL) {
    fprintf(stderr, "%s\n", mozc_ffi_last_error());
    return 1;
  }
  print_best(mozc_ffi_convert(mozc, "きょうはさむいですね", NULL, 0, NULL));  // 今日は寒いですね

  // 文節の長さを指定: ここで / はきものを / ぬぐ
  const int32_t lengths[] = {3, 5, 2};
  mozc_ffi_result* result = mozc_ffi_convert(mozc, "ここではきものをぬぐ", lengths, 3, NULL);
  printf("%s, %s\n", mozc_ffi_candidate(result, 1, 0), mozc_ffi_candidate(result, 1, 1));  // は着物を, 履物を
  mozc_ffi_result_free(result);

  // 確定した変換は、次回から第一候補になる
  const char* const texts[] = {"ここで", "履物を", "脱ぐ"};
  mozc_ffi_learn(mozc, "ここではきものをぬぐ", lengths, texts, 3, NULL);
  print_best(mozc_ffi_convert(mozc, "ここではきものをぬぐ", NULL, 0, NULL));  // ここで履物を脱ぐ

  result = mozc_ffi_predict(mozc, "ありがと", NULL);
  printf("%s, %s\n", mozc_ffi_candidate(result, 0, 0), mozc_ffi_candidate(result, 0, 1));  // ありがとうございます, ありがとう
  mozc_ffi_result_free(result);

  mozc_ffi_close(mozc);
  return 0;
}
```

出力は新しいプロファイルでのものです。学習が進むと、第一候補はユーザーの選択に沿って変わります。

## 呼び出し一覧

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前のテキストを渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。文字列はすべて UTF-8 です。

| | |
|---|---|
| `mozc_ffi_open(profile_dir, flags)` | Mozc を開きます。`flags` は `0` か `MOZC_FFI_INCOGNITO`。 |
| `mozc_ffi_close(mozc)` | 学習した内容を保存し、ハンドルを解放します。 |
| `mozc_ffi_convert(mozc, reading, lengths, n_lengths, context)` | 読みの文節と候補（優先度の高い順）を持つ結果。`lengths` で文節の区切りを指定でき、`NULL` なら Mozc が決めます。`context` は読みの直前のテキストで、最初の文節を変換する手がかりになります。なければ `NULL`。 |
| `mozc_ffi_predict(mozc, reading, context)` | 文節が 1 つの結果。入力途中の読みの予測候補が優先度の高い順に入ります。 |
| `mozc_ffi_segment_count`、`_segment_reading`、`_candidate_count`、`_candidate`、`_candidate_description` | 結果を読みます。結果の文字列は `mozc_ffi_result_free` を呼ぶまで有効です。 |
| `mozc_ffi_result_free(result)` | 結果を解放します。 |
| `mozc_ffi_learn(mozc, reading, lengths, texts, n, context)` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から第一候補にします。 |
| `mozc_ffi_clear_learning(mozc)` | 学習した内容をすべて消します。 |
| `mozc_ffi_flush(mozc)` | 学習した内容をすぐにプロファイルへ書き込みます。閉じるときにも書き込まれます。 |
| `mozc_ffi_last_error()` | このスレッドでの直前の呼び出しが失敗した理由。成功していれば `""`。 |
| `mozc_ffi_mozc_version()`、`mozc_ffi_abi_version()` | Mozc のバージョン（例: `"3.35.6354.102"`）と、C API のバージョン。後者は `MOZC_FFI_ABI_VERSION` と一致している必要があります。 |

文節の長さはバイト数ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。候補の description には、その候補についての Mozc の注記（例: `カタカナ`）が日本語で入り、注記がなければ `""` です。

## エラー

要求どおりに処理できなかった呼び出しは `NULL` または `0` を返し、理由は `mozc_ffi_last_error()` で確認できます。「the segment lengths do not add up to the reading's length」のような英語の文です。決まった文字列なので入力された文字列が含まれることはなく、プロセスが終わるまで有効です。候補にないテキストがあると、`mozc_ffi_learn` は `0` を返し、何も学習しません。

Mozc を起動できない場合、`mozc_ffi_open` は `NULL` を返します。別のバージョンのヘッダーでビルドされたライブラリを見分けるため、先に `mozc_ffi_abi_version()` と `MOZC_FFI_ABI_VERSION` を比べてください。

## プロファイル

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。`NULL` または `""` を渡すと Mozc の既定の場所（Linux では、`~/.mozc` があればそこ、なければ `$XDG_CONFIG_HOME/mozc` または `~/.config/mozc`）を使います。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。閉じてから開き直すのは問題ありません。`MOZC_FFI_INCOGNITO` は何も学習せず、プロファイルにも触れません。

## スレッド

1 つのハンドルは複数のスレッドから使え、呼び出しは順番に処理されます。`mozc_ffi_last_error()` はスレッドごとです。呼び出しは呼び出し元のスレッドで動き、短い文なら 1 ミリ秒ほどで終わります。

## ライブラリの読み込み

ライブラリをリンクし、プログラムの実行時に見つかるようにしてください。

```sh
# Linux
cc -std=c99 -Iinclude example.c -Llib -lmozc_ffi -o example
LD_LIBRARY_PATH=lib ./example
```

Linux では、`LD_LIBRARY_PATH` を設定するか、`-Wl,-rpath,'$ORIGIN'` のような rpath を付けてリンクするか、システムのライブラリパスにインストールしてください。Windows では `lib/mozc_ffi.lib` をリンクし、`bin/mozc_ffi.dll` を実行ファイルと同じ場所に置いてください。

<!-- --8<-- [end:guide] -->

## API リファレンス

すべての関数の説明は [`mozc_ffi.h`](https://github.com/Malorn44/mozc-ffi/blob/main/core/mozc_ffi.h) にあります（英語）。[ドキュメント](https://mozc-ffi.readthedocs.io/stable/ja/c/#api-reference)ではヘッダー全体を見られます。

## 関連情報

- [ドキュメント](https://mozc-ffi.readthedocs.io/stable/ja/c/)
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md) に記載しています。
