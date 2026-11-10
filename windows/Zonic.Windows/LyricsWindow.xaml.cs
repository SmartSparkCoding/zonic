using System.IO;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Zonic;

public partial class LyricsWindow : Window
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };

    private readonly List<TextBlock> _lineBlocks = new();
    private Lyrics? _lyrics;
    private string _trackKey = "";
    private int _activeIndex = -1;
    private PlayerState _state = PlayerState.Empty;

    public event Action<double>? SeekRequested;
    public event Action<string>? TransportRequested;

    public LyricsWindow()
    {
        InitializeComponent();
        ApplyTheme();
        ThemeManager.Shared.Changed += OnThemeChanged;
        PreviewKeyDown += OnKey;
        Closed += (_, _) => ThemeManager.Shared.Changed -= OnThemeChanged;
    }

    private void OnThemeChanged(object? sender, EventArgs e) => ApplyTheme();

    private void ApplyTheme()
    {
        var palette = ThemeManager.Shared.Palette;
        Root.Background = palette.BgBrush;
        Background = palette.BgBrush;
        TitleText.Foreground = palette.FgBrush;
        ArtistText.Foreground = palette.MutedBrush;
        ElapsedText.Foreground = palette.MutedBrush;
        RemainingText.Foreground = palette.MutedBrush;
        StatusText.Foreground = palette.MutedBrush;
        ProgressFill.Background = palette.AccentBrush;
        ArtworkPlaceholder.Foreground = palette.MutedBrush;
        foreach (var button in new[] { PreviousButton, PlayButton, NextButton, CloseButton })
        {
            button.Foreground = palette.FgBrush;
        }
        Highlight(force: true);
    }

    public void Update(PlayerState state)
    {
        _state = state;
        TitleText.Text = state.HasTrack ? state.Title : "Nothing playing";
        ArtistText.Text = state.Artist;
        PlayButton.Content = state.Playing ? "\uE769" : "\uE768";

        var fraction = state.Fraction;
        var trackWidth = ProgressTrack.ActualWidth > 0 ? ProgressTrack.ActualWidth : 240;
        ProgressFill.Width = Math.Max(0, trackWidth * fraction);
        ElapsedText.Text = PlayerState.Clock(state.Position);
        RemainingText.Text = "-" + PlayerState.Clock(Math.Max(0, state.Duration - state.Position));

        var key = (state.Artist + "|" + state.Title).ToLowerInvariant();
        if (key != _trackKey)
        {
            _trackKey = key;
            _ = LoadAsync(state);
        }
        Highlight(force: false);
    }

    private async Task LoadAsync(PlayerState state)
    {
        _lyrics = null;
        _lineBlocks.Clear();
        LinesPanel.Children.Clear();
        _activeIndex = -1;

        if (!state.HasTrack)
        {
            StatusText.Text = "Play something and the words show up here.";
            return;
        }

        StatusText.Text = "Looking for lyrics…";
        _ = LoadArtworkAsync(state.Artwork);

        var lyrics = await LyricsService.FetchAsync(state.Artist, state.Title, state.Album, state.Duration);
        if (lyrics is null)
        {
            StatusText.Text = "No lyrics found for this one.";
            return;
        }

        _lyrics = lyrics;
        StatusText.Text = lyrics.IsSynced ? "" : "These lyrics are not timed, so they will not follow along.";

        if (lyrics.IsSynced)
        {
            foreach (var line in lyrics.Lines)
            {
                var block = new TextBlock
                {
                    Text = line.Text,
                    TextWrapping = TextWrapping.Wrap,
                    FontSize = 24,
                    FontWeight = FontWeights.SemiBold,
                    Margin = new Thickness(0, 0, 0, 18),
                    Cursor = Cursors.Hand,
                    Tag = line.Time
                };
                block.MouseLeftButtonUp += (_, _) => SeekRequested?.Invoke(line.Time);
                _lineBlocks.Add(block);
                LinesPanel.Children.Add(block);
            }
        }
        else
        {
            foreach (var raw in lyrics.Plain.Split('\n'))
            {
                var text = raw.Trim();
                if (text.Length == 0) { continue; }
                LinesPanel.Children.Add(new TextBlock
                {
                    Text = text,
                    TextWrapping = TextWrapping.Wrap,
                    FontSize = 20,
                    Margin = new Thickness(0, 0, 0, 14)
                });
            }
        }
        Highlight(force: true);
    }

    private async Task LoadArtworkAsync(string? url)
    {
        Artwork.Source = null;
        if (string.IsNullOrWhiteSpace(url)) { return; }
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)");
            request.Headers.TryAddWithoutValidation("Referer", "https://music.amazon.com/");
            using var response = await Http.SendAsync(request);
            if (!response.IsSuccessStatusCode) { return; }
            var bytes = await response.Content.ReadAsByteArrayAsync();

            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.StreamSource = new MemoryStream(bytes);
            image.EndInit();
            image.Freeze();
            Artwork.Source = image;
        }
        catch (Exception)
        {
            // A missing cover is not worth a dialog.
        }
    }

    private void Highlight(bool force)
    {
        if (_lineBlocks.Count == 0) { return; }
        var palette = ThemeManager.Shared.Palette;

        var index = -1;
        for (var i = 0; i < _lyrics!.Lines.Count; i++)
        {
            if (_lyrics.Lines[i].Time <= _state.Position + 0.15) { index = i; } else { break; }
        }
        if (index == _activeIndex && !force) { return; }
        _activeIndex = index;

        for (var i = 0; i < _lineBlocks.Count; i++)
        {
            var block = _lineBlocks[i];
            var active = i == index;
            block.Foreground = active ? palette.AccentBrush : palette.MutedBrush;
            block.FontSize = active ? 28 : 24;
            block.FontWeight = active ? FontWeights.Bold : FontWeights.SemiBold;
            block.Opacity = active ? 1.0 : 0.55;
        }

        if (index >= 0 && index < _lineBlocks.Count)
        {
            _lineBlocks[index].BringIntoView();
        }
    }

    private void Root_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed) { DragMove(); }
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape) { Close(); }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void Previous_Click(object sender, RoutedEventArgs e) => TransportRequested?.Invoke("previous");

    private void Next_Click(object sender, RoutedEventArgs e) => TransportRequested?.Invoke("next");

    private void Play_Click(object sender, RoutedEventArgs e) => TransportRequested?.Invoke("toggle");
}
