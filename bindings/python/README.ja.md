# mozc-ffi（Python）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/python/README.md) | 日本語

<!-- --8<-- [start:guide] -->

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を Python から使うためのバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC もインストールも不要です。非公式のもので、Google とは提携関係にありません。

## インストール

```sh
pip install mozc-ffi
```

Python 3.11 以降が必要です。対応環境は Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。どの wheel にもライブラリが入っているので、ほかにインストールするものはありません。

## 使い方

```python
from mozc_ffi import Mozc

with Mozc("/path/to/profile") as mozc:
    segments = mozc.convert("きょうはさむいですね")
    print("".join(s.candidates[0] for s in segments))  # 今日は寒いですね

    # 文節の長さを指定: ここで / はきものを / ぬぐ
    segments = mozc.convert("ここではきものをぬぐ", [3, 5, 2])
    print(segments[1].candidates[:2])  # ['は着物を', '履物を']

    # ユーザーが送った変換は、次回から先頭に並ぶ
    mozc.learn("ここではきものをぬぐ", [3, 5, 2], ["ここで", "履物を", "脱ぐ"])
    print("".join(s.candidates[0] for s in mozc.convert("ここではきものをぬぐ")))  # ここで履物を脱ぐ

    print(mozc.predict("ありがと")[:2])  # ['ありがとうございます', 'ありがとう']
```

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前の文を渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。

| | |
|---|---|
| `convert(reading, lengths=None, context="")` | `Segment(reading, candidates, descriptions)` のリスト。候補は良い順です。`lengths` で文節の区切りを指定でき、省略すると Mozc が決めます。`context` は読みの直前の文で、最初の文節の変換の助けになります。 |
| `predict(reading, context="")` | 入力途中の読みの補完候補。良い順です。 |
| `learn(reading, lengths, texts, context="")` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から先頭に並べます。候補にないテキストがあると `False` を返し、何も学習しません。 |
| `clear_learning()` | 学習した内容をすべて消します。 |
| `flush()` | 学習した内容をすぐにプロファイルへ書き込みます。閉じるときにも書き込まれます。 |
| `last_error` | 直前の呼び出しが失敗した理由（英語）。成功していれば `""`。入力された文字列は含みません。 |
| `mozc_version` | Mozc のバージョン（例: `"2.32.5994.102"`）。 |

文節の長さはバイト数ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。`descriptions` には各候補についての Mozc の注記（例: `カタカナ`）が日本語で入り、注記がなければ `""` です。

要求どおりに処理できなかった呼び出しは `[]` または `False` を返し、理由は `last_error` で分かります。ライブラリを読み込めない場合や Mozc を起動できない場合、`Mozc(...)` は `MozcError` を送出します。

## プロファイル

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。ディレクトリを指定しない `Mozc()` は Mozc の既定の場所（Linux では `~/.mozc`）を使います。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。`Mozc(path, incognito=True)` は何も学習せず、プロファイルにも触れません。

1 つの `Mozc` は複数のスレッドから使えます。呼び出しは順番に処理されます。

## ライブラリの読み込み

`Mozc` は最初に開くときに、次の順で最初に見つかったライブラリを読み込みます。

1. 引数 `library=`
2. 環境変数 `MOZC_FFI_LIBRARY`
3. `mozc_ffi` モジュールと同じ場所（wheel はここに入れます）
4. システムのライブラリパス

一度読み込んだライブラリは、プロセスが終了するまで読み込まれたままです。

<!-- --8<-- [end:guide] -->

## 関連情報

- [ドキュメント](https://malorn44.github.io/mozc-ffi/ja/python/)
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md) に記載しています。
