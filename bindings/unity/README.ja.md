# mozc-ffi（Unity）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/unity/README.md) | 日本語

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) の C# バインディングを、ネイティブライブラリと一緒に Unity パッケージにしたものです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC もインストールも不要です。非公式のもので、Google とは提携関係にありません。

## インストール

Unity は NuGet ではなく npm 形式のレジストリからパッケージをインストールするため、このパッケージは npm に `com.malorn44.mozc-ffi` として公開しています。プロジェクトの `Packages/manifest.json` に、npm をスコープ付きレジストリとして追加し、パッケージを依存関係に加えてください（既存の内容はそのまま残します）。

<!-- x-release-please-start-version -->
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
<!-- x-release-please-end -->

以降の新しいバージョンは Package Manager に表示されます。

Unity 2021.3 以降が必要です。ライブラリは Windows x64 と Linux x64（glibc 2.28 以降）の Editor とスタンドアロンプレイヤー向けに設定してあり、Mono と IL2CPP のどちらでも動作します。Linux arm64 を含むほかのプラットフォーム向けのライブラリは、このパッケージには入っていません。

## 使い方

バインディングは NuGet パッケージと同じもので、`MozcFfi` アセンブリに入っています。このアセンブリは Unity が自動で参照します。スクリプトに独自のアセンブリ定義がある場合は、その参照に `MozcFfi` を追加してください。

```csharp
using System.IO;
using System.Linq;
using MozcFfi;
using UnityEngine;

public class Converter : MonoBehaviour
{
    Mozc mozc;

    void Awake() => mozc = new Mozc(Path.Combine(Application.persistentDataPath, "mozc"));

    void OnDestroy() => mozc?.Dispose();

    // きょうはさむいですね なら 今日は寒いですね
    public string Best(string reading) => string.Concat(mozc.Convert(reading).Select(s => s.Candidates[0]));

    // ユーザーが文節 i に texts[i] を送った: 次回から先頭に並ぶ
    public void Sent(string reading, int[] lengths, string[] texts) => mozc.Learn(reading, lengths, texts);
}
```

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前の文を渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。

| | |
|---|---|
| `Convert(reading, lengths = null, context = null)` | `Segment`（`Reading`、`Candidates`、`Descriptions`）の一覧。候補は良い順です。`lengths` で文節の区切りを指定でき、省略すると Mozc が決めます。`context` は読みの直前の文で、最初の文節の変換の助けになります。 |
| `Predict(reading, context = null)` | 入力途中の読みの補完候補。良い順です。 |
| `Learn(reading, lengths, texts, context = null)` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から先頭に並べます。候補にないテキストがあると `false` を返し、何も学習しません。 |
| `ClearLearning()` | 学習した内容をすべて消します。 |
| `Flush()` | 学習した内容をすぐにプロファイルへ書き込みます。`Dispose()` でも書き込まれます。 |
| `LastError` | 直前の呼び出しが失敗した理由（英語）。成功していれば `""`。入力された文字列は含みません。 |
| `Mozc.MozcVersion` | Mozc のバージョン（例: `"2.32.5994.102"`）。 |

文節の長さは UTF-16 のコード単位ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。要求どおりに処理できなかった呼び出しは空の一覧または `false` を返し、理由は `LastError` で分かります。

## プロファイルとスレッド

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。Mozc はプロファイルディレクトリをプロセス単位で保持しますが、Editor ではそのプロセスが Play モードをまたいで動き続けます。毎回同じプロファイルを開き、停止するときに `Mozc` を破棄してください。`new Mozc(path, incognito: true)` は何も学習せず、プロファイルにも触れません。

1 つの `Mozc` は複数のスレッドから使えます。呼び出しは順番に処理されます。

## 関連情報

- [ドキュメント](https://malorn44.github.io/mozc-ffi/ja/unity/)
- [NuGet の C# バインディング](https://www.nuget.org/packages/MozcFfi)（Unity 以外の .NET 向け）
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md)（このパッケージにも同梱）に記載しています。
