using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;

namespace Zonic;

public partial class MainWindow : Window
{
    private const string HomeUrl = "https://music.amazon.com/";

    /// <summary>Small additions to the shared bridge: space to play, and the shortcuts
    /// that would otherwise be swallowed by the page's own focus.</summary>
    private const string ExtraScript = """
        (function () {
          if (window.__zonicExtra) { return; }
          window.__zonicExtra = true;
          var editable = function () {
            var el = document.activeElement;
            if (!el) { return false; }
            var tag = (el.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea' || tag === 'select') { return true; }
            return !!el.isContentEditable;
          };
          document.addEventListener('keydown', function (e) {
            if (editable()) { return; }
            if (e.code === 'Space' && !e.repeat && !e.ctrlKey && !e.altKey && !e.metaKey) {
              if (!window.__zonic) { return; }
              var d = window.__zonic.debug();
              if (!d || !d.hasMedia) { return; }
              e.preventDefault();
              window.__zonic.command('toggle');
              return;
            }
            if (e.ctrlKey && e.shiftKey && (e.key === 'L' || e.key === 'l')) {
              e.preventDefault();
              window.chrome.webview.postMessage({ lyrics: true });
              return;
            }
            if (e.ctrlKey && e.key === ',') {
              e.preventDefault();
              window.chrome.webview.postMessage({ settings: true });
            }
          }, true);
        })();
        """;

    private Bridge? _bridge;
    private readonly MediaKeys _keys = new();
    private PlayerState _state = PlayerState.Empty;
    private LyricsWindow? _lyrics;
    private SettingsWindow? _settings;
    private bool _scrubbing;
    private bool _ready;

    public MainWindow()
    {
        InitializeComponent();

        var settings = Settings.Current;
        Width = Math.Max(settings.WindowWidth, MinWidth);
        Height = Math.Max(settings.WindowHeight, MinHeight);
        if (settings.WindowMaximised) { WindowState = WindowState.Maximized; }

        ApplyTheme();
        ThemeManager.Shared.Changed += OnThemeChanged;

        Loaded += async (_, _) => await InitWebAsync();
        Closing += OnClosing;
        PreviewKeyDown += OnKey;

        _keys.Pressed += action => Dispatcher.Invoke(() => _ = SendAsync(action));
        _keys.Start();
    }

    // MARK: - Startup

    private async Task InitWebAsync()
    {
        try
        {
            var dataFolder = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Zonic", "WebView2");
            Directory.CreateDirectory(dataFolder);

            var environment = await CoreWebView2Environment.CreateAsync(null, dataFolder);
            await Web.EnsureCoreWebView2Async(environment);

            var core = Web.CoreWebView2;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.AreDevToolsEnabled = true;
            core.Settings.IsSwipeNavigationEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = true;
            core.Settings.IsGeneralAutofillEnabled = true;

            _ = core.AddScriptToExecuteOnDocumentCreatedAsync(Bridge.Script);
            _ = core.AddScriptToExecuteOnDocumentCreatedAsync(ExtraScript);

            core.WebMessageReceived += OnMessage;
            core.NavigationCompleted += OnNavigated;
            core.NewWindowRequested += OnNewWindow;
            core.HistoryChanged += (_, _) => UpdateNav();

            _bridge = new Bridge(core);
            Web.ZoomFactor = Math.Clamp(Settings.Current.Zoom, 0.65, 2.2);
            Web.DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 28, 28, 30);

            core.Navigate(HomeUrl);
            _ready = true;

            _ = Task.Delay(1500).ContinueWith(_ => Dispatcher.Invoke(WhatsNewWindow.PresentIfNeeded));
            if (Settings.Current.AutoCheckUpdates)
            {
                _ = Task.Delay(4000).ContinueWith(_ => Dispatcher.InvokeAsync(() => CheckForUpdatesAsync(silent: true)));
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Zonic could not start its web view.\n\n" + ex.Message +
                "\n\nThe WebView2 runtime is required. Windows 11 has it; on Windows 10 you may need the Evergreen runtime from Microsoft.",
                "Zonic", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    // MARK: - Page messages

    private void OnMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        var json = e.WebMessageAsJson;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;

            if (root.TryGetProperty("lyrics", out _)) { ToggleLyrics(); return; }
            if (root.TryGetProperty("settings", out _)) { OpenSettings(); return; }

            var state = JsonSerializer.Deserialize<PlayerState>(json);
            if (state is not null) { ApplyState(state); }
        }
        catch (JsonException)
        {
            // A message we do not understand is not worth interrupting playback for.
        }
    }

    private void ApplyState(PlayerState state)
    {
        _state = state;

        NowPlayingText.Text = state.DisplayText;
        Title = state.HasTrack ? state.Title + " · Zonic" : "Zonic";

        var showScrubber = state.Duration > 0;
        ScrubPanel.Visibility = showScrubber ? Visibility.Visible : Visibility.Collapsed;
        if (showScrubber && !_scrubbing)
        {
            SetScrubber(state.Fraction);
            TimeText.Text = state.ProgressText;
        }

        Scrobbler.Shared.Observe(state);
        _lyrics?.Update(state);
    }

    private void SetScrubber(double fraction)
    {
        var width = ScrubTrack.ActualWidth;
        if (width <= 0) { return; }
        var clamped = Math.Clamp(fraction, 0, 1);
        ScrubFill.Width = Math.Max(0, width * clamped);
        ScrubThumb.Margin = new Thickness(Math.Max(0, width * clamped - 4), 0, 0, 0);
        ScrubThumb.Visibility = Visibility.Visible;
    }

    private void OnNavigated(object? sender, CoreWebView2NavigationCompletedEventArgs e)
    {
        UpdateNav();
        _ = PushThemeAsync();
        _ = _bridge?.PushOptionsAsync() ?? Task.CompletedTask;
    }

    private void OnNewWindow(object? sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        e.Handled = true;
        if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) &&
            (uri.Host.Contains("amazon.") || uri.Host.Contains("amazonaws.")))
        {
            Web.CoreWebView2.Navigate(e.Uri);
            return;
        }
        OpenExternal(e.Uri);
    }

    private static void OpenExternal(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch (Exception)
        {
            // No default browser is a strange machine, not a crash.
        }
    }

    private void UpdateNav()
    {
        if (!_ready) { return; }
        BackButton.IsEnabled = Web.CoreWebView2.CanGoBack;
        ForwardButton.IsEnabled = Web.CoreWebView2.CanGoForward;
    }

    // MARK: - Commands

    private async Task SendAsync(string action)
    {
        if (_bridge is null) { return; }
        await _bridge.CommandAsync(action);
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (Web.CoreWebView2?.CanGoBack == true) { Web.CoreWebView2.GoBack(); }
    }

    private void Forward_Click(object sender, RoutedEventArgs e)
    {
        if (Web.CoreWebView2?.CanGoForward == true) { Web.CoreWebView2.GoForward(); }
    }

    private void Reload_Click(object sender, RoutedEventArgs e) => Web.CoreWebView2?.Reload();

    private void Theme_Click(object sender, RoutedEventArgs e) => ThemeManager.Shared.Cycle();

    private void Lyrics_Click(object sender, RoutedEventArgs e) => ToggleLyrics();

    private void More_Click(object sender, RoutedEventArgs e)
    {
        var palette = ThemeManager.Shared.Palette;
        var menu = new ContextMenu
        {
            Background = palette.SurfaceBrush,
            Foreground = palette.FgBrush,
            BorderBrush = palette.MutedBrush,
            BorderThickness = new Thickness(1),
            PlacementTarget = MoreButton,
            IsOpen = true
        };

        menu.Items.Add(Item("Settings…", palette, OpenSettings));
        menu.Items.Add(Item("Check for Updates…", palette, async () => await CheckForUpdatesAsync(silent: false)));
        menu.Items.Add(Item("What's New", palette, WhatsNewWindow.Present));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Zoom In", palette, () => SetZoom(Settings.Current.Zoom + 0.1)));
        menu.Items.Add(Item("Zoom Out", palette, () => SetZoom(Settings.Current.Zoom - 0.1)));
        menu.Items.Add(Item("Actual Size", palette, () => SetZoom(1.0)));
        menu.Items.Add(new Separator());
        menu.Items.Add(Item("Love on Last.fm", palette, () => _ = Scrobbler.Shared.Love()));
        menu.Items.Add(Item("Copy Diagnostics", palette, CopyDiagnostics));
        menu.Items.Add(Item("Open in Browser", palette, () => OpenExternal(HomeUrl)));
    }

    private static MenuItem Item(string header, Palette palette, Action action)
    {
        var item = new MenuItem
        {
            Header = header,
            Foreground = palette.FgBrush,
            Background = palette.SurfaceBrush
        };
        item.Click += (_, _) => action();
        return item;
    }

    private void SetZoom(double zoom)
    {
        var clamped = Math.Clamp(Math.Round(zoom, 2), 0.65, 2.2);
        Settings.Current.Zoom = clamped;
        Settings.Save();
        Web.ZoomFactor = clamped;
    }

    private void CopyDiagnostics()
    {
        var lines = new List<string>
        {
            "Zonic " + Updater.CurrentVersion + " (Windows)",
            "theme: " + ThemeManager.Shared.Palette.Id + " / skin: " + ThemeManager.Shared.SkinMode,
            "state: " + _state.DisplayText + " " + _state.ProgressText,
            "webview: " + (Web.CoreWebView2?.Environment?.BrowserVersionString ?? "not ready"),
            "settings: " + Settings.FilePath
        };
        lines.AddRange(Scrobbler.Shared.LogText());
        try
        {
            Clipboard.SetText(string.Join(Environment.NewLine, lines));
            NowPlayingText.Text = "Diagnostics copied";
        }
        catch (Exception)
        {
            MessageBox.Show(string.Join(Environment.NewLine, lines), "Zonic diagnostics");
        }
    }

    // MARK: - Scrubber

    private void Scrub_Down(object sender, MouseButtonEventArgs e)
    {
        if (_state.Duration <= 0) { return; }
        _scrubbing = true;
        ScrubTrack.CaptureMouse();
        ScrubTo(e);
    }

    private void Scrub_Move(object sender, MouseEventArgs e)
    {
        if (!_scrubbing) { return; }
        ScrubTo(e);
    }

    private void Scrub_Up(object sender, MouseButtonEventArgs e)
    {
        if (!_scrubbing) { return; }
        _scrubbing = false;
        ScrubTrack.ReleaseMouseCapture();
        ScrubTo(e);
    }

    private void ScrubTo(MouseEventArgs e)
    {
        var width = ScrubTrack.ActualWidth;
        if (width <= 0) { return; }
        var fraction = Math.Clamp(e.GetPosition(ScrubTrack).X / width, 0, 1);
        SetScrubber(fraction);
        TimeText.Text = PlayerState.Clock(fraction * _state.Duration) + " / " + PlayerState.Clock(_state.Duration);
        _ = _bridge?.SeekFractionAsync(fraction) ?? Task.CompletedTask;
    }

    // MARK: - Windows

    private void ToggleLyrics()
    {
        if (_lyrics is { IsVisible: true })
        {
            _lyrics.Close();
            _lyrics = null;
            return;
        }
        _lyrics = new LyricsWindow();
        _lyrics.SeekRequested += seconds => _ = _bridge?.SeekToAsync(seconds) ?? Task.CompletedTask;
        _lyrics.TransportRequested += action => _ = SendAsync(action);
        _lyrics.Closed += (_, _) => _lyrics = null;
        _lyrics.Owner = this;
        _lyrics.Update(_state);
        _lyrics.Show();
    }

    private void OpenSettings()
    {
        if (_settings is { IsVisible: true })
        {
            _settings.Activate();
            return;
        }
        _settings = new SettingsWindow();
        _settings.Closed += (_, _) => _settings = null;
        _settings.Owner = this;
        _settings.Show();
    }

    private async Task CheckForUpdatesAsync(bool silent)
    {
        var result = await Updater.Shared.CheckAsync();
        if (result is null)
        {
            if (!silent) { MessageBox.Show("You are on the newest version.", "Zonic"); }
            return;
        }
        var answer = MessageBox.Show(
            $"Zonic {result.Version} is available. You have {Updater.CurrentVersion}.\n\nDownload and install it now?",
            "Update available", MessageBoxButton.YesNo, MessageBoxImage.Information);
        if (answer == MessageBoxResult.Yes)
        {
            await Updater.Shared.InstallAsync(result);
        }
    }

    // MARK: - Theme

    private void OnThemeChanged(object? sender, EventArgs e)
    {
        ApplyTheme();
        _ = PushThemeAsync();
    }

    private void ApplyTheme()
    {
        var palette = ThemeManager.Shared.Palette;
        Background = palette.BgBrush;
        Chrome.Background = palette.BgBrush;
        WebHost.Background = palette.BgBrush;
        NowPlayingText.Foreground = palette.FgBrush;
        TimeText.Foreground = palette.MutedBrush;
        ScrubFill.Background = palette.AccentBrush;
        ScrubThumb.Fill = palette.AccentBrush;

        foreach (var button in new[] { BackButton, ForwardButton, ReloadButton, LyricsButton, ThemeButton, MoreButton })
        {
            button.Foreground = palette.FgBrush;
        }
    }

    private async Task PushThemeAsync()
    {
        if (_bridge is null) { return; }
        await _bridge.ApplyThemeAsync(ThemeManager.Shared.PageCss());
    }

    // MARK: - Input and lifetime

    private void Chrome_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
            return;
        }
        if (e.ButtonState == MouseButtonState.Pressed) { DragMove(); }
    }

    private void OnKey(object sender, KeyEventArgs e)
    {
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var shift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        var alt = Keyboard.Modifiers.HasFlag(ModifierKeys.Alt);

        switch (e.Key)
        {
            case Key.F5:
                Web.CoreWebView2?.Reload();
                e.Handled = true;
                break;
            case Key.Left when alt:
                if (Web.CoreWebView2?.CanGoBack == true) { Web.CoreWebView2.GoBack(); }
                e.Handled = true;
                break;
            case Key.Right when alt:
                if (Web.CoreWebView2?.CanGoForward == true) { Web.CoreWebView2.GoForward(); }
                e.Handled = true;
                break;
            case Key.L when ctrl && shift:
                ToggleLyrics();
                e.Handled = true;
                break;
            case Key.OemComma when ctrl:
                OpenSettings();
                e.Handled = true;
                break;
            case Key.OemPlus when ctrl:
                SetZoom(Settings.Current.Zoom + 0.1);
                e.Handled = true;
                break;
            case Key.OemMinus when ctrl:
                SetZoom(Settings.Current.Zoom - 0.1);
                e.Handled = true;
                break;
            case Key.D0 when ctrl:
                SetZoom(1.0);
                e.Handled = true;
                break;
        }
    }

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        var settings = Settings.Current;
        settings.WindowMaximised = WindowState == WindowState.Maximized;
        if (WindowState == WindowState.Normal)
        {
            settings.WindowWidth = Width;
            settings.WindowHeight = Height;
        }
        Settings.Save();
        _keys.Dispose();
        _lyrics?.Close();
        _settings?.Close();
    }
}
