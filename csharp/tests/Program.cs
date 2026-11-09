// Checks the C# bindings against the built native library. Exit code 0 when all pass.

using System;
using System.IO;
using System.Linq;
using MozcFfi;

static class Program
{
    static int failures;

    static void Check(bool ok, string what)
    {
        Console.WriteLine($"{(ok ? "ok  " : "FAIL")} {what}");
        if (!ok)
            failures++;
    }

    static string First(System.Collections.Generic.IReadOnlyList<Segment> segments) =>
        string.Concat(segments.Select(s => s.Candidates[0]));

    static int Main()
    {
        // Mozc keeps one profile per process.
        string profile = Path.Combine(Path.GetTempPath(), "mozc-ffi-cs-" + Guid.NewGuid().ToString("N"));
        try
        {
            using (var mozc = new Mozc(profile, incognito: true))
            {
                Check(System.Text.RegularExpressions.Regex.IsMatch(Mozc.MozcVersion, @"^\d+\.\d+\.\d+\.\d+$"),
                      $"Mozc version {Mozc.MozcVersion}");

                var segments = mozc.Convert("きょうはさむいですね");
                Check(string.Concat(segments.Select(s => s.Reading)) == "きょうはさむいですね", "segments cover the reading");
                Check(First(segments) == "今日は寒いですね", $"best conversion {First(segments)}");

                segments = mozc.Convert("ここではきものをぬぐ", new[] { 3, 5, 2 });
                Check(segments.Select(s => s.Reading).SequenceEqual(new[] { "ここで", "はきものを", "ぬぐ" }),
                      "lengths fix the segments");
                Check(segments.Count == 3 && segments[1].Candidates.Contains("履物を"), "履物を is a candidate");
                Check(mozc.Convert("ここではきものをぬぐ", new[] { 3, 3 }).Count == 0, "bad lengths give nothing");

                var predictions = mozc.Predict("ありがと");
                Check(predictions.Any(p => p.StartsWith("ありがとう", StringComparison.Ordinal)), "predict completes");

                var lines = File.ReadAllLines(Path.Combine(AppContext.BaseDirectory, "chat.tsv"))
                                .Where(l => l.Length > 0 && !l.StartsWith("#"));
                int total = 0, top1 = 0;
                foreach (string line in lines)
                {
                    string[] parts = line.Split('\t');
                    total++;
                    if (parts[1].Split('|').Contains(First(mozc.Convert(parts[0]))))
                        top1++;
                }
                Check(top1 >= total * 0.80, $"chat.tsv top-1 {top1}/{total}");
            }

            string pick;
            using (var mozc = new Mozc(profile))
            {
                var before = mozc.Convert("かんじ", new[] { 3 })[0].Candidates;
                Check(before.Distinct().Count() == before.Count, "no candidate twice");
                pick = before[1];
                Check(mozc.Learn("かんじ", new[] { 3 }, new[] { pick }), "learn accepts a candidate");
                Check(mozc.Convert("かんじ", new[] { 3 })[0].Candidates[0] == pick, "the pick ranks first");
                Check(!mozc.Learn("かんじ", new[] { 3 }, new[] { "not a candidate" }), "learn refuses a non-candidate");
                Check(mozc.Flush(), "flush");
            }
            using (var mozc = new Mozc(profile))
            {
                Check(mozc.Convert("かんじ", new[] { 3 })[0].Candidates[0] == pick, "learning persists");
                Check(mozc.ClearLearning(), "clear learning");
                Check(mozc.Convert("かんじ", new[] { 3 })[0].Candidates[0] != pick, "cleared");
            }
        }
        finally
        {
            try { Directory.Delete(profile, true); } catch (IOException) { }
        }
        Console.WriteLine(failures == 0 ? "All checks passed." : $"{failures} check(s) failed.");
        return failures == 0 ? 0 : 1;
    }
}
