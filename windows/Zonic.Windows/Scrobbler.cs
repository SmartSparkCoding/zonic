using System.Diagnostics;
using System.Globalization;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Zonic;

/// <summary>Last.fm, ported from the macOS build. The signature rules are the fiddly part:
/// parameters sorted by name, concatenated as key+value, secret appended, MD5 hex, and
/// format=json added only after signing.</summary>
public sealed class Scrobbler
{
    public static Scrobbler Shared { get; } = new();

    private const string Api = "https://ws.audioscrobbler.com/2.0/";

    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private readonly Queue<string> _answers = new();
    private readonly HashSet<string> _scrobbled = new();

    private PlayerState _state = PlayerState.Empty;
    private string _trackKey = "";
    private DateTime _startedAt = DateTime.UtcNow;
    private double _played;
    private DateTime? _lastTick;
    private bool _nowPlayingSent;

    public string LastMessage { get; private set; } = "";
    public event EventHandler? StatusChanged;

    private static Settings S => Settings.Current;

    public bool IsConnected => !string.IsNullOrEmpty(S.LastfmSession) && !string.IsNullOrEmpty(S.LastfmUser);
    public bool IsEnabled => S.LastfmEnabled;

    public string StatusLine
    {
        get
        {
            if (IsConnected) { return "Scrobbling to Last.fm as " + S.LastfmUser; }
            if (!string.IsNullOrEmpty(S.LastfmPendingToken)) { return "Authorise Zonic in your browser to finish connecting"; }
            if (string.IsNullOrEmpty(S.LastfmApiKey) || string.IsNullOrEmpty(S.LastfmApiSecret))
            {
                return "Add your Last.fm API key and secret to start scrobbling";
            }
            return "Not connected";
        }
    }

    public IReadOnlyList<string> LogText() => _answers.ToList();

    // MARK: - Observing playback

    public void Observe(PlayerState state)
    {
        var key = (state.Artist + "|" + state.Title).ToLowerInvariant();

        if (key != _trackKey)
        {
            _trackKey = key;
            _startedAt = DateTime.UtcNow;
            _played = 0;
            _lastTick = null;
            _nowPlayingSent = false;
            _state = state;
            if (state.HasTrack) { _ = NowPlayingAsync(state); }
            return;
        }

        _state = state;
        AdvanceClock(state.Playing);

        if (state.HasTrack && !_nowPlayingSent) { _ = NowPlayingAsync(state); }
        if (state.HasTrack && Listened(state) >= Threshold(state)) { _ = ScrobbleAsync(state); }
    }

    /// <summary>Wall clock that only runs while the page says it is playing. The page's own
    /// position is preferred, but it can sit at zero on some tracks, and then this is what
    /// makes a scrobble happen at all.</summary>
    private void AdvanceClock(bool playing)
    {
        var now = DateTime.UtcNow;
        if (_lastTick is { } last && playing)
        {
            var delta = (now - last).TotalSeconds;
            if (delta > 0 && delta < 30) { _played += delta; }
        }
        _lastTick = now;
    }

    private double Listened(PlayerState state) => state.Position > 0 ? state.Position : _played;

    private static double Threshold(PlayerState state) =>
        Math.Max(30, Math.Min(240, state.Duration > 0 ? state.Duration / 2 : 0));

    private string ScrobbleKey(PlayerState state) =>
        (state.Artist + "|" + state.Title + "|" + new DateTimeOffset(_startedAt).ToUnixTimeSeconds())
            .ToLowerInvariant();

    // MARK: - Calls

    private async Task NowPlayingAsync(PlayerState state)
    {
        if (!IsConnected || string.IsNullOrEmpty(state.Title)) { return; }
        _nowPlayingSent = true;
        await CallAsync(new Dictionary<string, string>
        {
            ["method"] = "track.updateNowPlaying",
            ["artist"] = state.Artist,
            ["track"] = state.Title,
            ["album"] = state.Album,
            ["duration"] = ((int)Math.Round(state.Duration)).ToString(CultureInfo.InvariantCulture),
            ["sk"] = S.LastfmSession
        });
    }

    private async Task ScrobbleAsync(PlayerState state)
    {
        if (!IsConnected || !IsEnabled) { return; }
        var key = ScrobbleKey(state);
        if (_scrobbled.Contains(key)) { return; }

        var answer = await CallAsync(new Dictionary<string, string>
        {
            ["method"] = "track.scrobble",
            ["artist"] = state.Artist,
            ["track"] = state.Title,
            ["album"] = state.Album,
            ["timestamp"] = new DateTimeOffset(_startedAt).ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture),
            ["sk"] = S.LastfmSession
        });

        if (answer is not null && !answer.Value.Failed)
        {
            _scrobbled.Add(key);
            Report("Scrobbled " + state.DisplayText);
        }
        else if (answer is not null)
        {
            Report("Scrobble refused: " + answer.Value.Message);
        }
    }

    public async Task Love()
    {
        if (!IsConnected || !_state.HasTrack) { Report("Nothing to love yet"); return; }
        var answer = await CallAsync(new Dictionary<string, string>
        {
            ["method"] = "track.love",
            ["artist"] = _state.Artist,
            ["track"] = _state.Title,
            ["sk"] = S.LastfmSession
        });
        Report(answer is { Failed: false } ? "Loved " + _state.DisplayText : "Last.fm said no: " + answer?.Message);
    }

    /// <summary>Sends a scrobble for whatever is playing, ignoring the listening rules, so
    /// a broken setup shows Last.fm's own words instead of silence.</summary>
    public async Task<string> TestScrobble()
    {
        if (string.IsNullOrEmpty(S.LastfmApiKey) || string.IsNullOrEmpty(S.LastfmApiSecret))
        {
            return "Add your API key and secret first.";
        }
        if (!IsConnected) { return "Connect to Last.fm first."; }
        if (!_state.HasTrack) { return "Play something first, so there is a track to send."; }

        var answer = await CallAsync(new Dictionary<string, string>
        {
            ["method"] = "track.scrobble",
            ["artist"] = _state.Artist,
            ["track"] = _state.Title,
            ["timestamp"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture),
            ["sk"] = S.LastfmSession
        });

        if (answer is null) { return "No answer from Last.fm."; }
        return answer.Value.Failed
            ? "Last.fm refused it: " + answer.Value.Message
            : "Last.fm accepted the test scrobble.";
    }

    private async Task<(bool Failed, string Message)?> CallAsync(Dictionary<string, string> parameters)
    {
        if (string.IsNullOrEmpty(S.LastfmApiKey) || string.IsNullOrEmpty(S.LastfmApiSecret)) { return null; }

        parameters["api_key"] = S.LastfmApiKey;
        var signature = Sign(parameters, S.LastfmApiSecret);
        parameters["api_sig"] = signature;
        parameters["format"] = "json";

        try
        {
            using var content = new FormUrlEncodedContent(parameters);
            using var response = await _http.PostAsync(Api, content);
            var body = await response.Content.ReadAsStringAsync();
            Record(parameters["method"] + " → " + Trim(body));

            using var document = JsonDocument.Parse(body);
            if (document.RootElement.TryGetProperty("error", out var error))
            {
                var message = document.RootElement.TryGetProperty("message", out var m) ? m.GetString() : "";
                return (true, error.GetInt32() + " " + message);
            }
            return (false, "ok");
        }
        catch (Exception ex)
        {
            Record(parameters["method"] + " → " + ex.GetType().Name);
            return (true, ex.Message);
        }
    }

    private static string Sign(Dictionary<string, string> parameters, string secret)
    {
        var builder = new StringBuilder();
        foreach (var pair in parameters.OrderBy(p => p.Key, StringComparer.Ordinal))
        {
            builder.Append(pair.Key).Append(pair.Value);
        }
        builder.Append(secret);
        var hash = MD5.HashData(Encoding.UTF8.GetBytes(builder.ToString()));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    private static string Trim(string body) => body.Length <= 160 ? body : body[..160] + "…";

    private void Record(string line)
    {
        _answers.Enqueue(line);
        while (_answers.Count > 8) { _answers.Dequeue(); }
    }

    private void Report(string message)
    {
        LastMessage = message;
        Record(message);
        StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    // MARK: - Authorisation

    public async Task<string> BeginAuth()
    {
        if (string.IsNullOrEmpty(S.LastfmApiKey) || string.IsNullOrEmpty(S.LastfmApiSecret))
        {
            return "Add your API key and secret first.";
        }
        var token = await FetchTokenAsync();
        if (string.IsNullOrEmpty(token)) { return "Last.fm would not issue a token."; }

        S.LastfmPendingToken = token;
        Settings.Save();
        var url = "https://www.last.fm/api/auth/?api_key=" + Uri.EscapeDataString(S.LastfmApiKey) + "&token=" + Uri.EscapeDataString(token);
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch (Exception) { }
        Report("Approve Zonic in your browser, then press Finish Connecting");
        return "Approve Zonic in your browser, then press Finish Connecting.";
    }

    private async Task<string> FetchTokenAsync()
    {
        var parameters = new Dictionary<string, string>
        {
            ["method"] = "auth.getToken",
            ["api_key"] = S.LastfmApiKey
        };
        parameters["api_sig"] = Sign(parameters, S.LastfmApiSecret);
        parameters["format"] = "json";
        try
        {
            using var content = new FormUrlEncodedContent(parameters);
            using var response = await _http.PostAsync(Api, content);
            var body = await response.Content.ReadAsStringAsync();
            using var document = JsonDocument.Parse(body);
            return document.RootElement.TryGetProperty("token", out var token) ? token.GetString() ?? "" : "";
        }
        catch (Exception)
        {
            return "";
        }
    }

    public async Task<string> FinishAuth()
    {
        var token = S.LastfmPendingToken;
        if (string.IsNullOrEmpty(token)) { return "Start the connection first."; }

        var parameters = new Dictionary<string, string>
        {
            ["method"] = "auth.getSession",
            ["api_key"] = S.LastfmApiKey,
            ["token"] = token
        };
        parameters["api_sig"] = Sign(parameters, S.LastfmApiSecret);
        parameters["format"] = "json";

        try
        {
            using var content = new FormUrlEncodedContent(parameters);
            using var response = await _http.PostAsync(Api, content);
            var body = await response.Content.ReadAsStringAsync();
            Record("auth.getSession → " + Trim(body));
            using var document = JsonDocument.Parse(body);

            if (document.RootElement.TryGetProperty("error", out var error))
            {
                var message = document.RootElement.TryGetProperty("message", out var m) ? m.GetString() : "";
                return "Last.fm says that token is not approved yet (" + error.GetInt32() + " " + message + ").";
            }
            if (!document.RootElement.TryGetProperty("session", out var session))
            {
                return "Last.fm did not return a session.";
            }

            S.LastfmSession = session.TryGetProperty("key", out var key) ? key.GetString() ?? "" : "";
            S.LastfmUser = session.TryGetProperty("name", out var name) ? name.GetString() ?? "" : "";
            S.LastfmPendingToken = "";
            Settings.Save();
            Report("Connected as " + S.LastfmUser);
            return "Connected as " + S.LastfmUser + ".";
        }
        catch (Exception ex)
        {
            return "Could not reach Last.fm: " + ex.Message;
        }
    }

    public void Disconnect()
    {
        S.LastfmSession = "";
        S.LastfmUser = "";
        S.LastfmPendingToken = "";
        Settings.Save();
        Report("Disconnected");
    }
}
