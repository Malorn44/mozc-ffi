# mozc-ffi（C#）

[English](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/csharp/README.md) | 日本語

<!-- --8<-- [start:guide] -->

Google 製のオープンソース日本語かな漢字変換エンジン [Mozc](https://github.com/google/mozc) を C# から使うためのバインディングです。Mozc は辞書を内蔵した状態でアプリと同じプロセス内で動作するため、`mozc_server` も IPC も Mozc 本体のインストールも不要です。非公式のもので、Google とは関係ありません。

## インストール

```sh
dotnet add package MozcFfi
```

パッケージは .NET Standard 2.0 向けで、ライブラリが入っています。Unity では NuGet からインストールできないため、[Unity 用のパッケージ](https://mozc-ffi.readthedocs.io/stable/ja/unity/)を使ってください。

## 対応環境

Linux x64 と arm64（glibc 2.28 以降）、Windows x64 です。ほかの環境では、ライブラリを自分でビルドしてプログラムと同じ場所に置いてください。

## 使用例

```csharp
using System;
using System.Linq;
using MozcFfi;

using var mozc = new Mozc("/path/to/profile");
string Best(string reading) => string.Concat(mozc.Convert(reading).Select(s => s.Candidates[0]));

Console.WriteLine(Best("きょうはさむいですね"));  // 今日は寒いですね

// 文節の長さを指定: ここで / はきものを / ぬぐ
var segments = mozc.Convert("ここではきものをぬぐ", new[] { 3, 5, 2 });
Console.WriteLine(string.Join(", ", segments[1].Candidates.Take(2)));  // は着物を, 履物を

// 確定した変換は、次回から第一候補になる
mozc.Learn("ここではきものをぬぐ", new[] { 3, 5, 2 }, new[] { "ここで", "履物を", "脱ぐ" });
Console.WriteLine(Best("ここではきものをぬぐ"));  // ここで履物を脱ぐ

Console.WriteLine(string.Join(", ", mozc.Predict("ありがと").Take(2)));  // ありがとうございます, ありがとう
```

出力は新しいプロファイルでのものです。学習が進むと、第一候補はユーザーの選択に沿って変わります。

## 呼び出し一覧

呼び出しはそれぞれ独立しています。ひらがなの読みと、必要に応じて文節の長さと直前のテキストを渡すと、文節ごとの候補が返ってきます。Mozc と同期させておく状態はありません。

| | |
|---|---|
| `new Mozc(profileDir = null, incognito = false)` | Mozc を開きます。破棄するか、`using` で使ってください。 |
| `Convert(reading, lengths = null, context = null)` | `Segment`（`Reading`、`Candidates`、`Descriptions`）の一覧。候補は優先度の高い順です。`lengths` で文節の区切りを指定でき、省略すると Mozc が決めます。`context` は読みの直前のテキストで、最初の文節を変換する手がかりになります。 |
| `Predict(reading, context = null)` | 入力途中の読みの予測候補。優先度の高い順です。 |
| `Learn(reading, lengths, texts, context = null)` | 文節 `i` で `texts[i]` が選ばれたことを学習し、次回から第一候補にします。 |
| `ClearLearning()` | 学習した内容をすべて消します。 |
| `Flush()` | 学習した内容をすぐにプロファイルへ書き込みます。`Dispose()` でも書き込まれます。 |
| `Dispose()` | 学習した内容を保存し、エンジンを解放します。 |
| `LastError` | 直前の呼び出しが失敗した理由。成功していれば `""`。 |
| `Mozc.MozcVersion` | Mozc のバージョン（例: `"3.35.6354.102"`）。 |

文節の長さは UTF-16 のコード単位ではなく Unicode の文字数で数え、合計が読みの長さと一致する必要があります。`Descriptions` には各候補についての Mozc の注記（例: `カタカナ`）が日本語で入り、注記がなければ `""` です。

## エラー

要求どおりに処理できなかった呼び出しは空のリストまたは `false` を返し、理由は `LastError` で確認できます。「the segment lengths do not add up to the reading's length」のような英語の文です。入力された文字列が含まれることはありません。候補にないテキストがあると、`Learn` は `false` を返し、何も学習しません。

ライブラリの C API のバージョンが異なる場合や Mozc を起動できない場合、`new Mozc()` は `MozcException` を、ライブラリが見つからない場合は `DllNotFoundException` をスローします。

## プロファイル

プロファイルディレクトリには Mozc が学習した内容が保存され、存在しなければ作成されます。ディレクトリを指定しない `new Mozc()` は Mozc の既定の場所（Linux では、`~/.mozc` があればそこ、なければ `$XDG_CONFIG_HOME/mozc` または `~/.config/mozc`）を使います。Mozc はプロファイルディレクトリをプロセス単位で保持するため、1 つのプロセスで開くプロファイルは 1 つだけにしてください。破棄してから開き直すのは問題ありません。`new Mozc(path, incognito: true)` は何も学習せず、プロファイルにも触れません。

## スレッド

1 つの `Mozc` は複数のスレッドから使えます。呼び出しは順番に処理されます。呼び出しは呼び出し元のスレッドで動き、短い文なら 1 ミリ秒ほどで終わります。

## ライブラリの読み込み

バインディングは P/Invoke で `mozc_ffi` を読み込みます。パッケージは各環境のライブラリを `runtimes/` に入れており、.NET がマシンに合うものを読み込みます。それ以外の環境では、`mozc_ffi.dll` または `libmozc_ffi.so` をプログラムと同じ場所か、システムのライブラリパスに置いてください。C# バインディングは `MOZC_FFI_LIBRARY` を読みません。

<!-- --8<-- [end:guide] -->

## API リファレンス

パッケージにはドキュメントコメント（`MozcFfi.xml`、英語）が入っているので、エディターに説明が表示されます。バインディングのソースは [`MozcFfi.cs`](https://github.com/Malorn44/mozc-ffi/blob/main/bindings/csharp/MozcFfi.cs) の 1 ファイルです。

## 関連情報

- [ドキュメント](https://mozc-ffi.readthedocs.io/stable/ja/csharp/)
- [ほかの言語と、ライブラリを自分でビルドする方法](https://github.com/Malorn44/mozc-ffi/blob/main/README.ja.md)
- [変更履歴](https://github.com/Malorn44/mozc-ffi/blob/main/CHANGELOG.md)

BSD-3-Clause です。ライブラリには Mozc とその辞書が含まれており、それらのライセンスは [THIRD_PARTY_NOTICES.md](https://github.com/Malorn44/mozc-ffi/blob/main/THIRD_PARTY_NOTICES.md) に記載しています。
