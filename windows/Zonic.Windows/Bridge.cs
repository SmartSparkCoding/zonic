using System.IO;
using System.Reflection;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;

namespace Zonic;

/// <summary>The native half of the injected script. Every call is a small JS expression
/// evaluated in the page, so nothing here needs to know Amazon's markup.</summary>
public sealed class Bridge
{
    private readonly CoreWebView2 _core;

    public Bridge(CoreWebView2 core) => _core = core;

    /// <summary>The script itself, shared with the macOS build. Only the message channel
    /// differs: WebView2 posts through chrome.webview, WebKit through messageHandlers.</summary>
    public static string Script { get; } = LoadScript();

    private static string LoadScript()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream("Zonic.Bridge.js");
        if (stream is null) { return string.Empty; }
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }

    public async Task<string> EvalAsync(string expression)
    {
        try
        {
            return await _core.ExecuteScriptAsync(expression);
        }
        catch (Exception)
        {
            return "null";
        }
    }

    /// <summary>ExecuteScriptAsync hands back JSON, so a string result arrives quoted.</summary>
    public static string AsText(string json)
    {
        if (string.IsNullOrEmpty(json) || json == "null") { return ""; }
        try
        {
            return JsonSerializer.Deserialize<string>(json) ?? "";
        }
        catch (JsonException)
        {
            return json.Trim('"');
        }
    }

    public Task<string> CommandAsync(string action) =>
        EvalAsync($"window.__zonic ? window.__zonic.command({JsonSerializer.Serialize(action)}) : 'missing'");

    public Task<string> SeekToAsync(double seconds) =>
        EvalAsync($"window.__zonic ? window.__zonic.seekTo({seconds.ToString(System.Globalization.CultureInfo.InvariantCulture)}) : 'missing'");

    public Task<string> SeekByAsync(double delta) =>
        EvalAsync($"window.__zonic ? window.__zonic.seekBy({delta.ToString(System.Globalization.CultureInfo.InvariantCulture)}) : 'missing'");

    public Task<string> SeekFractionAsync(double fraction) =>
        EvalAsync($"window.__zonic ? window.__zonic.seekFraction({fraction.ToString(System.Globalization.CultureInfo.InvariantCulture)}) : 'missing'");

    public Task<string> FinishTrackAsync() =>
        EvalAsync("window.__zonic ? window.__zonic.finishTrack() : 'missing'");

    public Task<string> DebugAsync() =>
        EvalAsync("window.__zonic ? JSON.stringify(window.__zonic.debug()) : 'null'");

    /// <summary>Pushes the settings the page needs: the skip fallback and the crossfade
    /// length. Called on load and whenever either changes.</summary>
    public Task PushOptionsAsync()
    {
        var settings = Settings.Current;
        var options = JsonSerializer.Serialize(new
        {
            finishTrack = settings.FinishTrackSkips,
            crossfade = Math.Clamp(settings.Crossfade, 0, 15)
        });
        return EvalAsync($"window.__zonic ? JSON.stringify(window.__zonic.options({options})) : 'null'");
    }

    /// <summary>Replaces the page skin. An empty string removes it, which is what the
    /// "leave the page alone" mode does.</summary>
    public Task ApplyThemeAsync(string css)
    {
        var payload = JsonSerializer.Serialize(css);
        var script = $$"""
            (function () {
              var id = 'zonic-theme';
              var existing = document.getElementById(id);
              if (!{{payload}}) {
                if (existing) { existing.remove(); }
                return 'off';
              }
              if (!existing) {
                existing = document.createElement('style');
                existing.id = id;
                (document.head || document.documentElement).appendChild(existing);
              }
              existing.textContent = {{payload}};
              return 'applied';
            })();
            """;
        return EvalAsync(script);
    }
}
