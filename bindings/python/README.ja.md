# mozc-ffi（Python）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/python/README.md) | 日本語

<!-- --8<-- [start:guide] -->

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を Python から使うためのバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC も Mozc 本体のインストールも不要です。非公式のもので、Google とは関係ありません。

## インストール

```sh
pip install mozc-ffi
```

Python 3.10 以降が必要です。どの wheel にもライブラリが入っているので、ほかにインストールするものはありません。

## 対応環境

Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。macOS や Alpine Linux（musl）など、ほかの環境向けの wheel はありません。

## 使用例

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    segments = mozc.convert("きょうはさむいですね")
    print("".join(s.candidates[0] for s in segments))  # 今日は寒いですね

    # 文節の長さを指定: ここで / はきものを / ぬぐ
    segments = mozc.convert("ここではきものをぬぐ", [3, 5, 2])
    print(segments[1].candidates[:2])  # ['は着物を', '履物を']

    # 確定した変換は、次回から第一候補になる
    mozc.learn("ここではきものをぬぐ", [3, 5, 2], ["ここで", "履物を", "脱ぐ"])
    print("".join(s.candidates[0] for s in mozc.convert("ここではきものをぬぐ")))  # ここで履物を脱ぐ

    print(mozc.predict("ありがと")[:2])  # ['ありがとうございます', 'ありがとう']
```

出力は新しいプロファイルでのものです。学習が進むと、第一候補はユーザーの選択に沿って変わります。

## 呼び出し一覧

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前のテキストを渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。

| | |
|---|---|
| `Mozc(profile_dir=None, *, incognito=False, library=None)` | Mozc を開きます。`with` ブロックで使うか、`close()` を呼んでください。 |
| `convert(reading, lengths=None, context="")` | `Segment(reading, candidates, descriptions)` のリスト。候補は優先度の高い順です。`lengths` で文節の区切りを指定でき、省略すると Mozc が決めます。`context` は読みの直前のテキストで、最初の文節を変換する手がかりになります。 |
| `predict(reading, context="")` | 入力途中の読みの予測候補。優先度の高い順です。 |
| `learn(reading, lengths, texts, context="")` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から第一候補にします。 |
| `clear_learning()` | 学習した内容をすべて消します。 |
| `flush()` | 学習した内容をすぐにプロファイルへ書き込みます。閉じるときにも書き込まれます。 |
| `close()` | 学習した内容を保存し、エンジンを解放します。 |
| `last_error` | 直前の呼び出しが失敗した理由。成功していれば `""`。 |
| `mozc_version` | Mozc のバージョン（例: `"3.35.6354.102"`）。 |

文節の長さはバイト数ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。`descriptions` には各候補についての Mozc の注記（例: `カタカナ`）が日本語で入り、注記がなければ `""` です。

## エラー

要求どおりに処理できなかった呼び出しは `[]` または `False` を返し、理由は `last_error` で確認できます。「the segment lengths do not add up to the reading's length」のような英語の文です。入力された文字列が含まれることはありません。候補にないテキストがあると、`learn` は `False` を返し、何も学習しません。

ライブラリを読み込めない場合、C API のバージョンが異なる場合、Mozc を起動できない場合、`Mozc(...)` は `MozcError` を送出します。

## プロファイル

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。ディレクトリを指定しない `Mozc()` は Mozc の既定の場所（Linux では、`~/.mozc` があればそこ、なければ `$XDG_CONFIG_HOME/mozc` または `~/.config/mozc`）を使います。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。閉じてから開き直すのは問題ありません。`Mozc(path, incognito=True)` は何も学習せず、プロファイルにも触れません。

## スレッド

1 つの `Mozc` は複数のスレッドから使えます。呼び出しは順番に処理されます。呼び出しは呼び出し元のスレッドで動き、短い文なら 1 ミリ秒ほどで終わります。

## ライブラリの読み込み

`Mozc` は最初に開くときに、次の順で最初に見つかったライブラリを読み込みます。

1. 引数 `library=`
2. 環境変数 `MOZC_FFI_LIBRARY`
3. `mozc_ffi` モジュールと同じ場所（wheel はここに入れます）
4. システムのライブラリパス

一度読み込んだライブラリは、プロセスが終了するまで読み込まれたままです。

<!-- --8<-- [end:guide] -->

## API リファレンス

すべてのクラスとメソッドは、docstring から生成した [API リファレンス](https://mozc-ffi.readthedocs.io/stable/ja/python/#api-reference)（英語）にあります。エディターにも同じ docstring が表示され、パッケージには型情報が付いています。

## 関連情報

- [ドキュメント](https://mozc-ffi.readthedocs.io/stable/ja/python/)
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md) に記載しています。
