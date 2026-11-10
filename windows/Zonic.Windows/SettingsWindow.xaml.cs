using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace Zonic;

public partial class SettingsWindow : Window
{
    private bool _loading = true;

    public SettingsWindow()
    {
        InitializeComponent();
        BuildCombos();
        Load();
        ApplyTheme();
        ThemeManager.Shared.Changed += OnThemeChanged;
        Scrobbler.Shared.StatusChanged += OnScrobbleStatus;
        Closed += (_, _) =>
        {
            ThemeManager.Shared.Changed -= OnThemeChanged;
            Scrobbler.Shared.StatusChanged -= OnScrobbleStatus;
        };
        _loading = false;
    }

    private void BuildCombos()
    {
        foreach (var palette in ThemeManager.Shared.Palettes)
        {
            ThemeCombo.Items.Add(new ComboBoxItem { Content = palette.Name, Tag = palette.Id });
        }
        foreach (var mode in new[] { "Auto", "Off", "Tint", "Invert" })
        {
            SkinCombo.Items.Add(new ComboBoxItem { Content = mode, Tag = mode.ToLowerInvariant() });
        }
        foreach (var seconds in new[] { 0, 2, 4, 6, 8 })
        {
            CrossfadeCombo.Items.Add(new ComboBoxItem
            {
                Content = seconds == 0 ? "Off" : seconds + " seconds",
                Tag = seconds
            });
        }
    }

    private void Load()
    {
        var settings = Settings.Current;

        Select(ThemeCombo, settings.Theme);
        Select(SkinCombo, settings.SkinMode);
        Select(CrossfadeCombo, settings.Crossfade);

        SeekCheck.IsChecked = settings.SeekControls;
        FinishCheck.IsChecked = settings.FinishTrackSkips;
        LastfmCheck.IsChecked = settings.LastfmEnabled;
        AutoUpdateCheck.IsChecked = settings.AutoCheckUpdates;

        KeyBox.Text = settings.LastfmApiKey;
        SecretBox.Password = settings.LastfmApiSecret;
        LastfmStatus.Text = Scrobbler.Shared.StatusLine;
        VersionText.Text = "Zonic " + Updater.CurrentVersion;
    }

    private static void Select(ComboBox combo, object tag)
    {
        foreach (var item in combo.Items)
        {
            if (item is ComboBoxItem entry && Equals(entry.Tag?.ToString(), tag?.ToString()))
            {
                combo.SelectedItem = entry;
                return;
            }
        }
        if (combo.Items.Count > 0) { combo.SelectedIndex = 0; }
    }

    private static string TagOf(ComboBox combo) =>
        (combo.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "";

    private void ApplyTheme()
    {
        var palette = ThemeManager.Shared.Palette;
        Root.Background = palette.BgBrush;
        Background = palette.BgBrush;
        Header.Background = palette.BgBrush;
        CloseButton.Foreground = palette.FgBrush;

        foreach (var text in FindTextBlocks(Root))
        {
            text.Foreground = text.FontSize <= 11 ? palette.MutedBrush : palette.FgBrush;
        }
        foreach (var check in Find<CheckBox>(Root)) { check.Foreground = palette.FgBrush; }
        foreach (var combo in Find<ComboBox>(Root))
        {
            combo.Background = palette.SurfaceBrush;
            combo.Foreground = palette.FgBrush;
            combo.BorderBrush = palette.MutedBrush;
        }
        foreach (var box in Find<TextBox>(Root))
        {
            box.Background = palette.SurfaceBrush;
            box.Foreground = palette.FgBrush;
            box.BorderBrush = palette.MutedBrush;
            box.CaretBrush = palette.FgBrush;
        }
        foreach (var box in Find<PasswordBox>(Root))
        {
            box.Background = palette.SurfaceBrush;
            box.Foreground = palette.FgBrush;
            box.BorderBrush = palette.MutedBrush;
            box.CaretBrush = palette.FgBrush;
        }
        foreach (var button in Find<Button>(Root))
        {
            if (button.Style is null) { button.Foreground = palette.FgBrush; }
        }
    }

    private static IEnumerable<T> Find<T>(DependencyObject root) where T : DependencyObject
    {
        var count = System.Windows.Media.VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(root, i);
            if (child is T match) { yield return match; }
            foreach (var nested in Find<T>(child)) { yield return nested; }
        }
    }

    private static IEnumerable<TextBlock> FindTextBlocks(DependencyObject root) => Find<TextBlock>(root);

    private void OnThemeChanged(object? sender, EventArgs e) => ApplyTheme();

    private void OnScrobbleStatus(object? sender, EventArgs e) =>
        Dispatcher.Invoke(() => LastfmStatus.Text = Scrobbler.Shared.LastMessage.Length > 0
            ? Scrobbler.Shared.LastMessage
            : Scrobbler.Shared.StatusLine);

    // MARK: - Handlers

    private void Theme_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) { return; }
        ThemeManager.Shared.SetTheme(TagOf(ThemeCombo));
    }

    private void Skin_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) { return; }
        if (Enum.TryParse<SkinMode>(TagOf(SkinCombo), true, out var mode))
        {
            ThemeManager.Shared.SkinMode = mode;
        }
    }

    private void Seek_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) { return; }
        Settings.Current.SeekControls = SeekCheck.IsChecked == true;
        Settings.Save();
    }

    private void Finish_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) { return; }
        Settings.Current.FinishTrackSkips = FinishCheck.IsChecked == true;
        Settings.Save();
    }

    private void Crossfade_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) { return; }
        if (int.TryParse(TagOf(CrossfadeCombo), out var seconds))
        {
            Settings.Current.Crossfade = seconds;
            Settings.Save();
        }
    }

    private void Lastfm_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) { return; }
        Settings.Current.LastfmEnabled = LastfmCheck.IsChecked == true;
        Settings.Save();
    }

    private void AutoUpdate_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) { return; }
        Settings.Current.AutoCheckUpdates = AutoUpdateCheck.IsChecked == true;
        Settings.Save();
    }

    private void SaveCredentials()
    {
        Settings.Current.LastfmApiKey = KeyBox.Text.Trim();
        Settings.Current.LastfmApiSecret = SecretBox.Password.Trim();
        Settings.Save();
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        SaveCredentials();
        LastfmStatus.Text = await Scrobbler.Shared.BeginAuth();
    }

    private async void Finish_Click(object sender, RoutedEventArgs e)
    {
        SaveCredentials();
        LastfmStatus.Text = await Scrobbler.Shared.FinishAuth();
    }

    private void Disconnect_Click(object sender, RoutedEventArgs e)
    {
        Scrobbler.Shared.Disconnect();
        LastfmStatus.Text = Scrobbler.Shared.StatusLine;
    }

    private async void Test_Click(object sender, RoutedEventArgs e)
    {
        SaveCredentials();
        LastfmStatus.Text = "Sending…";
        LastfmStatus.Text = await Scrobbler.Shared.TestScrobble();
    }

    private async void CheckNow_Click(object sender, RoutedEventArgs e)
    {
        CheckNowButton.IsEnabled = false;
        VersionText.Text = "Checking…";
        var info = await Updater.Shared.CheckAsync();
        CheckNowButton.IsEnabled = true;
        if (info is null)
        {
            VersionText.Text = "Zonic " + Updater.CurrentVersion + " is the newest version";
            return;
        }
        VersionText.Text = "Zonic " + Updater.CurrentVersion;
        var answer = MessageBox.Show(
            $"Zonic {info.Version} is available. Install it now?", "Update available",
            MessageBoxButton.YesNo, MessageBoxImage.Information);
        if (answer == MessageBoxResult.Yes) { await Updater.Shared.InstallAsync(info); }
    }

    private void Header_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed) { DragMove(); }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
