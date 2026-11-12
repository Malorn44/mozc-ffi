# mozc-ffi（Node.js）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/node/README.md) | 日本語

<!-- --8<-- [start:guide] -->

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を Node.js から使うためのバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC もインストールも不要です。非公式のもので、Google とは提携関係にありません。

## インストール

```sh
npm install mozc-ffi
```

Node.js 22 以降が必要です。対応環境は Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。TypeScript の型定義が付いています。

ライブラリは環境ごとに別のパッケージ（`@mozc-ffi/linux-x64`、`@mozc-ffi/linux-arm64`、`@mozc-ffi/win32-x64`）に入っています。これらは `mozc-ffi` の optional dependencies で、npm はマシンに合うものだけをインストールするため、自分でインストールする必要はありません。optional dependencies なしでインストールした場合は、代わりに `MOZC_FFI_LIBRARY` を設定してください（後述）。

## 使い方

```js
const { Mozc } = require('mozc-ffi');

const mozc = new Mozc('/path/to/profile');
try {
  const segments = mozc.convert('きょうはさむいですね');
  console.log(segments.map((s) => s.candidates[0]).join('')); // 今日は寒いですね

  // 文節の長さを指定: ここで / はきものを / ぬぐ
  console.log(mozc.convert('ここではきものをぬぐ', [3, 5, 2])[1].candidates.slice(0, 2)); // [ 'は着物を', '履物を' ]

  // ユーザーが送った変換は、次回から先頭に並ぶ
  mozc.learn('ここではきものをぬぐ', [3, 5, 2], ['ここで', '履物を', '脱ぐ']);
  console.log(mozc.convert('ここではきものをぬぐ').map((s) => s.candidates[0]).join('')); // ここで履物を脱ぐ

  console.log(mozc.predict('ありがと').slice(0, 2)); // [ 'ありがとうございます', 'ありがとう' ]
} finally {
  mozc.close();
}
```

`using` 宣言が使える環境では、`using mozc = new Mozc(...)` と書けば自動で閉じられます。

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前の文を渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。

| | |
|---|---|
| `convert(reading, lengths?, context?)` | `{ reading, candidates, descriptions }` の配列。候補は良い順です。`lengths` で文節の区切りを指定でき、省略すると Mozc が決めます。`context` は読みの直前の文で、最初の文節の変換の助けになります。 |
| `predict(reading, context?)` | 入力途中の読みの補完候補。良い順です。 |
| `learn(reading, lengths, texts, context?)` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から先頭に並べます。候補にないテキストがあると `false` を返し、何も学習しません。 |
| `clearLearning()` | 学習した内容をすべて消します。 |
| `flush()` | 学習した内容をすぐにプロファイルへ書き込みます。閉じるときにも書き込まれます。 |
| `close()` | 学習した内容を保存し、エンジンを解放します。 |
| `lastError` | 直前の呼び出しが失敗した理由（英語）。成功していれば `''`。入力された文字列は含みません。 |
| `Mozc.mozcVersion` | Mozc のバージョン（例: `'2.32.5994.102'`）。 |

文節の長さは UTF-16 のコード単位ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。`descriptions` には各候補についての Mozc の注記（例: `カタカナ`）が日本語で入り、注記がなければ `''` です。

要求どおりに処理できなかった呼び出しは `[]` または `false` を返し、理由は `lastError` で分かります。ライブラリを読み込めない場合や Mozc を起動できない場合、`new Mozc()` は例外を投げます。

## プロファイル

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。ディレクトリを指定しない `new Mozc()` は Mozc の既定の場所（Linux では `~/.mozc`）を使います。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。`new Mozc(path, { incognito: true })` は何も学習せず、プロファイルにも触れません。

## ライブラリの読み込み

`mozc-ffi` は最初に `Mozc` を開くときに、次の順で最初に見つかったライブラリを読み込みます。

1. 環境変数 `MOZC_FFI_LIBRARY`
2. このマシン用の `@mozc-ffi/<platform>-<arch>` パッケージ
3. システムのライブラリパス

一度読み込んだライブラリは、プロセスが終了するまで読み込まれたままです。

<!-- --8<-- [end:guide] -->

## 関連情報

- [ドキュメント](https://malorn44.github.io/mozc-ffi/ja/node/)
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md) に記載しています。
