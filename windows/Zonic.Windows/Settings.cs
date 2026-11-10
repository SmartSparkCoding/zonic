using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Zonic;

/// <summary>Everything the app remembers, in one JSON file under %APPDATA%\Zonic.</summary>
public sealed class Settings
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never
    };

    private static Settings? _current;

    public static Settings Current => _current ??= Load();

    public static string Folder
    {
        get
        {
            var root = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var path = Path.Combine(root, "Zonic");
            Directory.CreateDirectory(path);
            return path;
        }
    }

    public static string FilePath => Path.Combine(Folder, "settings.json");

    // Appearance
    public string Theme { get; set; } = "system";
    public string SkinMode { get; set; } = "auto";

    // Playback
    public bool SeekControls { get; set; } = true;
    public bool FinishTrackSkips { get; set; } = true;
    public int Crossfade { get; set; } = 4;
    public double Zoom { get; set; } = 1.0;

    // Updates
    public bool AutoCheckUpdates { get; set; } = true;
    public string LastSeenVersion { get; set; } = "";

    // Last.fm
    public string LastfmApiKey { get; set; } = "";
    public string LastfmApiSecret { get; set; } = "";
    public string LastfmSession { get; set; } = "";
    public string LastfmUser { get; set; } = "";
    public bool LastfmEnabled { get; set; } = true;
    public string LastfmPendingToken { get; set; } = "";

    // Window
    public double WindowWidth { get; set; } = 1200;
    public double WindowHeight { get; set; } = 800;
    public bool WindowMaximised { get; set; }

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var json = File.ReadAllText(FilePath);
                var loaded = JsonSerializer.Deserialize<Settings>(json, Options);
                if (loaded is not null) { return loaded; }
            }
        }
        catch (Exception)
        {
            // A corrupt settings file should never stop the app from opening.
        }
        return new Settings();
    }

    public static void Save()
    {
        try
        {
            var json = JsonSerializer.Serialize(Current, Options);
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, json);
            File.Move(temp, FilePath, true);
        }
        catch (Exception)
        {
            // Losing a preference is not worth crashing over.
        }
    }
}
