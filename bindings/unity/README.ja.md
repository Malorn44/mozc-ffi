# mozc-ffi（Unity）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/unity/README.md) | 日本語

<!-- --8<-- [start:guide] -->

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

以降の新しいバージョンは Package Manager に表示されます。Unity 2021.3 以降が必要です。

## 対応環境

Windows x64 と Linux x64（glibc 2.28 以降）の Editor とスタンドアロンプレイヤーで、Mono と IL2CPP のどちらでも動作します。Linux arm64、macOS、モバイルを含むほかのプラットフォーム向けのライブラリは、このパッケージには入っていません。

## 使用例

バインディングは `MozcFfi` アセンブリに入っており、Unity が自動で参照します。スクリプトに独自のアセンブリ定義がある場合は、その参照に `MozcFfi` を追加してください。

```csharp
using System.IO;
using System.Linq;
using MozcFfi;
using UnityEngine;

public class MozcExample : MonoBehaviour
{
    void Start()
    {
        using var mozc = new Mozc(Path.Combine(Application.persistentDataPath, "mozc"));
        string Best(string reading) => string.Concat(mozc.Convert(reading).Select(s => s.Candidates[0]));

        Debug.Log(Best("きょうはさむいですね"));  // 今日は寒いですね

        // 文節の長さを指定: ここで / はきものを / ぬぐ
        var segments = mozc.Convert("ここではきものをぬぐ", new[] { 3, 5, 2 });
        Debug.Log(string.Join(", ", segments[1].Candidates.Take(2)));  // は着物を, 履物を

        // ユーザーが送った変換は、次回から先頭に並ぶ
        mozc.Learn("ここではきものをぬぐ", new[] { 3, 5, 2 }, new[] { "ここで", "履物を", "脱ぐ" });
        Debug.Log(Best("ここではきものをぬぐ"));  // ここで履物を脱ぐ

        Debug.Log(string.Join(", ", mozc.Predict("ありがと").Take(2)));  // ありがとうございます, ありがとう
    }
}
```

出力は新しいプロファイルでのものです。学習が進むと、最初の候補はユーザーの選択に沿って変わります。実際のシーンでは、Mozc は `Awake` で一度だけ開き、`OnDestroy` で破棄してください。

## 呼び出し一覧

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前の文を渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。

| | |
|---|---|
| `new Mozc(profileDir = null, incognito = false)` | Mozc を開きます。破棄するか、`using` で使ってください。 |
| `Convert(reading, lengths = null, context = null)` | `Segment`（`Reading`、`Candidates`、`Descriptions`）の一覧。候補は良い順です。`lengths` で文節の区切りを指定でき、省略すると Mozc が決めます。`context` は読みの直前の文で、最初の文節の変換の助けになります。 |
| `Predict(reading, context = null)` | 入力途中の読みの補完候補。良い順です。 |
| `Learn(reading, lengths, texts, context = null)` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から先頭に並べます。 |
| `ClearLearning()` | 学習した内容をすべて消します。 |
| `Flush()` | 学習した内容をすぐにプロファイルへ書き込みます。`Dispose()` でも書き込まれます。 |
| `Dispose()` | 学習した内容を保存し、エンジンを解放します。 |
| `LastError` | 直前の呼び出しが失敗した理由。成功していれば `""`。 |
| `Mozc.MozcVersion` | Mozc のバージョン（例: `"2.32.5994.102"`）。 |

文節の長さは UTF-16 のコード単位ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。`Descriptions` には各候補についての Mozc の注記（例: `カタカナ`）が日本語で入り、注記がなければ `""` です。

## エラー

要求どおりに処理できなかった呼び出しは空の一覧または `false` を返し、理由は `LastError` で「the segment lengths do not add up to the reading's length」のような英語の文として分かります。入力された文字列が含まれることはありません。候補にないテキストがあると、`Learn` は `false` を返し、何も学習しません。

ライブラリの C API のバージョンが異なる場合や Mozc を起動できない場合、`new Mozc()` は `MozcException` を、そのプラットフォーム向けのライブラリがない場合は `DllNotFoundException` を投げます。

## プロファイル

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。置き場所には `Application.persistentDataPath` が適しています。Mozc はプロファイルディレクトリをプロセス単位で保持しますが、Editor ではそのプロセスが Play モードをまたいで動き続けます。毎回同じプロファイルを開き、停止するときに `Mozc` を破棄してください。破棄してから開き直すのは問題ありません。`new Mozc(path, incognito: true)` は何も学習せず、プロファイルにも触れません。

## スレッド

1 つの `Mozc` は複数のスレッドから使えます。呼び出しは順番に処理されます。呼び出しは呼び出し元のスレッドで動き、短い文なら 1 ミリ秒ほどで終わるので、メインスレッドから呼んでも問題ありません。

## ライブラリの読み込み

パッケージの `Runtime/Plugins/x86_64` には `mozc_ffi.dll` と `libmozc_ffi.so` が入っており、Windows x64 と Linux x64 の Editor とスタンドアロンプレイヤー向けのプラグインとして設定してあります。Unity はプラットフォームに合うものを読み込み、ビルド時にはプレイヤーにコピーします。バインディングは `MOZC_FFI_LIBRARY` を読みません。

<!-- --8<-- [end:guide] -->

## API リファレンス

バインディングは NuGet パッケージと同じもので、ソース（`Runtime/MozcFfi.cs`）として入っているので、エディターにドキュメントコメントが表示されます。一覧は [C# の API リファレンス](https://mozc-ffi.readthedocs.io/stable/ja/csharp/#api-reference)（英語）にあります。

## 関連情報

- [ドキュメント](https://mozc-ffi.readthedocs.io/stable/ja/unity/)
- [NuGet の C# バインディング](https://www.nuget.org/packages/MozcFfi)（Unity 以外の .NET 向け）
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md)（このパッケージにも同梱）に記載しています。
