using System.Text.Json.Serialization;

namespace Zonic;

/// <summary>What the page last told us. Mirrors the payload the injected script posts.</summary>
public sealed class PlayerState
{
    [JsonPropertyName("title")] public string Title { get; set; } = "";
    [JsonPropertyName("artist")] public string Artist { get; set; } = "";
    [JsonPropertyName("album")] public string Album { get; set; } = "";
    [JsonPropertyName("artwork")] public string? Artwork { get; set; }
    [JsonPropertyName("playing")] public bool Playing { get; set; }
    [JsonPropertyName("editing")] public bool Editing { get; set; }
    [JsonPropertyName("position")] public double Position { get; set; }
    [JsonPropertyName("duration")] public double Duration { get; set; }
    [JsonPropertyName("canSeek")] public bool CanSeek { get; set; }

    public static PlayerState Empty { get; } = new();

    [JsonIgnore] public bool HasTrack => !string.IsNullOrWhiteSpace(Title);

    [JsonIgnore] public string DisplayText => HasTrack
        ? (string.IsNullOrWhiteSpace(Artist) ? Title : Title + " · " + Artist)
        : "Amazon Music";

    [JsonIgnore] public double Fraction => Duration > 0 ? Math.Clamp(Position / Duration, 0, 1) : 0;

    public static string Clock(double seconds)
    {
        if (double.IsNaN(seconds) || double.IsInfinity(seconds) || seconds < 0) { seconds = 0; }
        var total = (int)Math.Round(seconds);
        return $"{total / 60}:{total % 60:00}";
    }

    public string ProgressText => Duration > 0 ? $"{Clock(Position)} / {Clock(Duration)}" : "";
}
