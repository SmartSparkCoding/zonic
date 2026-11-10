using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Zonic;

public sealed record LyricLine(double Time, string Text);

public sealed class Lyrics
{
    public IReadOnlyList<LyricLine> Lines { get; init; } = Array.Empty<LyricLine>();
    public string Plain { get; init; } = "";
    public bool IsSynced => Lines.Count > 0;

    private static readonly Regex Stamp = new(@"\[(\d+):(\d+(?:\.\d+)?)\]", RegexOptions.Compiled);

    public static Lyrics? FromJson(JsonElement root)
    {
        var synced = root.TryGetProperty("syncedLyrics", out var s) ? s.GetString() : null;
        var plain = root.TryGetProperty("plainLyrics", out var p) ? p.GetString() : null;

        if (!string.IsNullOrWhiteSpace(synced))
        {
            var lines = Parse(synced!);
            if (lines.Count > 0)
            {
                return new Lyrics { Lines = lines, Plain = plain ?? "" };
            }
        }
        if (!string.IsNullOrWhiteSpace(plain))
        {
            return new Lyrics { Plain = plain! };
        }
        return null;
    }

    /// <summary>LRC: one or more [m:ss.xx] stamps in front of each line.</summary>
    public static List<LyricLine> Parse(string lrc)
    {
        var lines = new List<LyricLine>();
        foreach (var raw in lrc.Split('\n'))
        {
            var matches = Stamp.Matches(raw);
            if (matches.Count == 0) { continue; }
            var text = Stamp.Replace(raw, "").Trim();
            if (text.Length == 0) { continue; }
            foreach (Match match in matches)
            {
                var minutes = int.Parse(match.Groups[1].Value);
                var seconds = double.Parse(match.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture);
                lines.Add(new LyricLine(minutes * 60 + seconds, text));
            }
        }
        lines.Sort((a, b) => a.Time.CompareTo(b.Time));
        return lines;
    }
}

public static class LyricsService
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };
    private static readonly Dictionary<string, Lyrics?> Memory = new();

    private static string CacheFolder
    {
        get
        {
            var path = Path.Combine(Settings.Folder, "lyrics");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    public static async Task<Lyrics?> FetchAsync(string artist, string title, string album, double duration)
    {
        if (string.IsNullOrWhiteSpace(artist) || string.IsNullOrWhiteSpace(title)) { return null; }

        var key = (artist + "|" + title).ToLowerInvariant();
        if (Memory.TryGetValue(key, out var cached)) { return cached; }

        var file = Path.Combine(CacheFolder, Safe(key) + ".json");
        if (File.Exists(file))
        {
            try
            {
                using var document = JsonDocument.Parse(File.ReadAllText(file));
                var fromDisk = Lyrics.FromJson(document.RootElement);
                Memory[key] = fromDisk;
                return fromDisk;
            }
            catch (Exception)
            {
                // A bad cache entry just means fetching again.
            }
        }

        var result = await FetchRemoteAsync(artist, title, album, duration);
        Memory[key] = result;
        if (result is not null)
        {
            try
            {
                var payload = JsonSerializer.Serialize(new
                {
                    syncedLyrics = result.IsSynced
                        ? string.Join("\n", result.Lines.Select(l => "[" + (int)(l.Time / 60) + ":" + (l.Time % 60).ToString("00.00", System.Globalization.CultureInfo.InvariantCulture) + "]" + l.Text))
                        : null,
                    plainLyrics = result.Plain
                });
                File.WriteAllText(file, payload);
            }
            catch (Exception)
            {
                // Caching is a nicety.
            }
        }
        return result;
    }

    private static async Task<Lyrics?> FetchRemoteAsync(string artist, string title, string album, double duration)
    {
        var exact = "https://lrclib.net/api/get?artist_name=" + Uri.EscapeDataString(artist) +
                    "&track_name=" + Uri.EscapeDataString(title) +
                    "&album_name=" + Uri.EscapeDataString(album) +
                    "&duration=" + ((int)Math.Round(duration)).ToString(System.Globalization.CultureInfo.InvariantCulture);
        var found = await TryAsync(exact);
        if (found is not null) { return found; }

        var search = "https://lrclib.net/api/search?artist_name=" + Uri.EscapeDataString(artist) +
                     "&track_name=" + Uri.EscapeDataString(title);
        try
        {
            using var response = await Send(search);
            if (!response.IsSuccessStatusCode) { return null; }
            var body = await response.Content.ReadAsStringAsync();
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.ValueKind != JsonValueKind.Array) { return null; }
            foreach (var entry in document.RootElement.EnumerateArray())
            {
                var lyrics = Lyrics.FromJson(entry);
                if (lyrics is not null) { return lyrics; }
            }
        }
        catch (Exception)
        {
            // Offline, or LRCLIB is having a day.
        }
        return null;
    }

    private static async Task<Lyrics?> TryAsync(string url)
    {
        try
        {
            using var response = await Send(url);
            if (!response.IsSuccessStatusCode) { return null; }
            var body = await response.Content.ReadAsStringAsync();
            using var document = JsonDocument.Parse(body);
            return Lyrics.FromJson(document.RootElement);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static Task<HttpResponseMessage> Send(string url)
    {
        var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", "Zonic for Windows");
        return Http.SendAsync(request);
    }

    private static string Safe(string key)
    {
        var builder = new System.Text.StringBuilder();
        foreach (var c in key)
        {
            builder.Append(char.IsLetterOrDigit(c) ? c : '_');
        }
        return builder.ToString();
    }
}
