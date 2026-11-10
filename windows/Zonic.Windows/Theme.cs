using System.IO;
using System.Reflection;
using System.Windows.Media;

namespace Zonic;

/// <summary>One colour set. The ids match the macOS build so a theme means the same thing
/// on both platforms.</summary>
public sealed record Palette(
    string Id,
    string Name,
    bool IsDark,
    bool IsNative,
    string Background,
    string Surface,
    string Foreground,
    string Muted,
    string Accent)
{
    public Color BgColor => Hex.ToColor(Background);
    public Color SurfaceColor => Hex.ToColor(Surface);
    public Color FgColor => Hex.ToColor(Foreground);
    public Color MutedColor => Hex.ToColor(Muted);
    public Color AccentColor => Hex.ToColor(Accent);

    public SolidColorBrush BgBrush => Hex.ToBrush(Background);
    public SolidColorBrush SurfaceBrush => Hex.ToBrush(Surface);
    public SolidColorBrush FgBrush => Hex.ToBrush(Foreground);
    public SolidColorBrush MutedBrush => Hex.ToBrush(Muted);
    public SolidColorBrush AccentBrush => Hex.ToBrush(Accent);
}

public static class Hex
{
    public static Color ToColor(string hex)
    {
        if (string.IsNullOrWhiteSpace(hex)) { return Colors.Transparent; }
        var value = hex.TrimStart('#');
        if (value.Length == 3)
        {
            value = string.Concat(value[0], value[0], value[1], value[1], value[2], value[2]);
        }
        if (value.Length != 6 || !uint.TryParse(value, System.Globalization.NumberStyles.HexNumber, null, out var packed))
        {
            return Colors.Transparent;
        }
        return Color.FromRgb((byte)(packed >> 16), (byte)(packed >> 8), (byte)packed);
    }

    public static SolidColorBrush ToBrush(string hex)
    {
        var brush = new SolidColorBrush(ToColor(hex));
        brush.Freeze();
        return brush;
    }

    public static Color Mix(Color a, Color b, double amount)
    {
        var t = Math.Clamp(amount, 0, 1);
        return Color.FromRgb(
            (byte)(a.R + (b.R - a.R) * t),
            (byte)(a.G + (b.G - a.G) * t),
            (byte)(a.B + (b.B - a.B) * t));
    }
}

public enum SkinMode
{
    Auto,
    Off,
    Tint,
    Invert
}

public sealed class ThemeManager
{
    public static ThemeManager Shared { get; } = new();

    public IReadOnlyList<Palette> Palettes { get; } = new[]
    {
        new Palette("system", "Match System", true, true, "1c1c1e", "2c2c2e", "f2f2f7", "98989f", "0a84ff"),
        new Palette("light", "Light", false, true, "f5f5f7", "ffffff", "1d1d1f", "86868b", "0071e3"),
        new Palette("dark", "Dark", true, true, "1c1c1e", "2c2c2e", "f2f2f7", "98989f", "0a84ff"),
        new Palette("gruvbox-dark", "Gruvbox Dark", true, false, "282828", "3c3836", "ebdbb2", "928374", "fabd2f"),
        new Palette("nord", "Nord", true, false, "2e3440", "3b4252", "eceff4", "7b88a1", "88c0d0"),
        new Palette("catppuccin-mocha", "Catppuccin Mocha", true, false, "1e1e2e", "313244", "cdd6f4", "a6adc8", "cba6f7"),
        new Palette("tokyo-night", "Tokyo Night", true, false, "1a1b26", "24283b", "c0caf5", "565f89", "7aa2f7"),
        new Palette("dracula", "Dracula", true, false, "282a36", "44475a", "f8f8f2", "6272a4", "bd93f9"),
        new Palette("one-dark", "One Dark", true, false, "282c34", "333842", "abb2bf", "5c6370", "61afef"),
        new Palette("solarized-dark", "Solarized Dark", true, false, "002b36", "073642", "93a1a1", "657b83", "b58900"),
        new Palette("amoled", "AMOLED Black", true, false, "000000", "0d0d0d", "e8e8e8", "7d7d7d", "6ea8fe"),
        new Palette("rose-pine", "Rose Pine", true, false, "191724", "1f1d2e", "e0def4", "6e6a86", "ebbcba"),
    };

    public event EventHandler? Changed;

    public Palette Palette
    {
        get
        {
            var id = Settings.Current.Theme;
            return Palettes.FirstOrDefault(p => p.Id == id) ?? Palettes[0];
        }
    }

    public SkinMode SkinMode
    {
        get
        {
            var raw = Settings.Current.SkinMode;
            if (Enum.TryParse<SkinMode>(raw, true, out var mode)) { return mode; }
            return SkinMode.Auto;
        }
        set
        {
            Settings.Current.SkinMode = value.ToString().ToLowerInvariant();
            Settings.Save();
            Changed?.Invoke(this, EventArgs.Empty);
        }
    }

    public void SetTheme(string id)
    {
        Settings.Current.Theme = id;
        Settings.Save();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Cycle()
    {
        var index = Palettes.ToList().FindIndex(p => p.Id == Palette.Id);
        SetTheme(Palettes[(index + 1) % Palettes.Count].Id);
    }

    /// <summary>The CSS injected into the Amazon page. Empty when the skin is off.</summary>
    public string PageCss()
    {
        var mode = SkinMode;
        if (mode == SkinMode.Auto)
        {
            mode = Palette.IsNative ? SkinMode.Off : SkinMode.Invert;
        }
        return mode switch
        {
            SkinMode.Off => string.Empty,
            SkinMode.Tint => Fill(Load("tint.css")),
            SkinMode.Invert => Palette.IsDark ? Fill(Load("invert.css")) : Fill(Load("tint.css")),
            _ => string.Empty
        };
    }

    private string Fill(string template)
    {
        var p = Palette;
        return template
            .Replace("__BG__", p.Background)
            .Replace("__SURFACE__", p.Surface)
            .Replace("__FG__", p.Foreground)
            .Replace("__MUTED__", p.Muted)
            .Replace("__ACCENT__", p.Accent)
            .Replace("__SCHEME__", p.IsDark ? "dark" : "light");
    }

    private static string Load(string name)
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream("Zonic." + name);
        if (stream is null) { return string.Empty; }
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
