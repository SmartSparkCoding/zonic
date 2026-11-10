using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Zonic;

public partial class WhatsNewWindow : Window
{
    private static WhatsNewWindow? _current;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };

    private readonly string _version = Updater.CurrentVersion;

    /// <summary>Shows the notes once per version. A first launch just records the version,
    /// so nobody gets a changelog before they have played a song.</summary>
    public static void PresentIfNeeded()
    {
        var settings = Settings.Current;
        if (string.IsNullOrEmpty(settings.LastSeenVersion))
        {
            settings.LastSeenVersion = Updater.CurrentVersion;
            Settings.Save();
            return;
        }
        if (settings.LastSeenVersion == Updater.CurrentVersion) { return; }
        settings.LastSeenVersion = Updater.CurrentVersion;
        Settings.Save();
        Present();
    }

    public static void Present()
    {
        if (_current is { IsVisible: true })
        {
            _current.Activate();
            return;
        }
        _current = new WhatsNewWindow();
        _current.Closed += (_, _) => _current = null;
        _current.Show();
        _current.Activate();
    }

    public WhatsNewWindow()
    {
        InitializeComponent();
        HeaderText.Text = "What's new in Zonic " + _version;
        ApplyTheme();
        ThemeManager.Shared.Changed += OnThemeChanged;
        Closed += (_, _) => ThemeManager.Shared.Changed -= OnThemeChanged;
        Render(BundledNotes());
        _ = LoadRemoteAsync();
    }

    private void OnThemeChanged(object? sender, EventArgs e) => ApplyTheme();

    private void ApplyTheme()
    {
        var palette = ThemeManager.Shared.Palette;
        Root.Background = palette.BgBrush;
        Background = palette.BgBrush;
        Header.Background = palette.BgBrush;
        HeaderText.Foreground = palette.FgBrush;
        CloseButton.Foreground = palette.FgBrush;
        ReleaseButton.Foreground = palette.FgBrush;
        NiceButton.Foreground = palette.FgBrush;
        Render(_lastMarkdown);
    }

    private string _lastMarkdown = "";

    private static string BundledNotes()
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, "RELEASE_NOTES.md");
            if (File.Exists(path))
            {
                var text = File.ReadAllText(path);
                if (!string.IsNullOrWhiteSpace(text)) { return text; }
            }
        }
        catch (Exception)
        {
            // Fall through to the generic line.
        }
        return "### What changed\n- This build did not ship its notes, so here is the short version: it is newer than the one you had.";
    }

    private async Task LoadRemoteAsync()
    {
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get,
                $"https://api.github.com/repos/SmartSparkCoding/zonic/releases/tags/v{_version}");
            request.Headers.TryAddWithoutValidation("User-Agent", "Zonic for Windows");
            request.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");

            using var response = await Http.SendAsync(request);
            if (!response.IsSuccessStatusCode) { return; }
            var body = await response.Content.ReadAsStringAsync();
            using var document = JsonDocument.Parse(body);
            if (!document.RootElement.TryGetProperty("body", out var notes)) { return; }
            var text = notes.GetString() ?? "";
            text = string.Join("\n", text.Split('\n').Where(line => !line.Contains("Full Changelog"))).Trim();
            if (text.Length == 0) { return; }
            Dispatcher.Invoke(() => Render(text));
        }
        catch (Exception)
        {
            // The bundled notes are already on screen.
        }
    }

    /// <summary>Small markdown renderer: headings, bullets, paragraphs and **bold**.</summary>
    private void Render(string markdown)
    {
        _lastMarkdown = markdown;
        var palette = ThemeManager.Shared.Palette;
        NotesPanel.Children.Clear();

        foreach (var raw in markdown.Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) { continue; }

            var block = new TextBlock
            {
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 6)
            };

            if (line.StartsWith("# "))
            {
                block.Text = line[2..];
                block.FontSize = 20;
                block.FontWeight = FontWeights.Bold;
                block.Foreground = palette.FgBrush;
                block.Margin = new Thickness(0, 4, 0, 10);
            }
            else if (line.StartsWith("### ") || line.StartsWith("## "))
            {
                block.Text = line.TrimStart('#').Trim();
                block.FontSize = 13;
                block.FontWeight = FontWeights.SemiBold;
                block.Foreground = palette.AccentBrush;
                block.Margin = new Thickness(0, 10, 0, 6);
            }
            else if (line.StartsWith("- ") || line.StartsWith("* "))
            {
                block.Text = "  •  " + line[2..];
                block.FontSize = 13;
                block.Foreground = palette.FgBrush;
                block.Margin = new Thickness(0, 0, 0, 5);
            }
            else
            {
                block.Text = line;
                block.FontSize = 13;
                block.Foreground = palette.FgBrush;
            }

            block.Text = block.Text.Replace("**", "").Replace("`", "");
            NotesPanel.Children.Add(block);
        }
    }

    private void Header_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed) { DragMove(); }
    }

    private void Release_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo($"https://github.com/SmartSparkCoding/zonic/releases/tag/v{_version}")
            {
                UseShellExecute = true
            });
        }
        catch (Exception)
        {
            // No browser, no problem.
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
