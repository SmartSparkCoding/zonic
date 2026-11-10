using System.Threading;
using System.Windows;

namespace Zonic;

public partial class App : Application
{
    private Mutex? _single;

    protected override void OnStartup(StartupEventArgs e)
    {
        // One window, one WebView2 profile. A second launch just brings the first forward.
        _single = new Mutex(true, "Zonic.SingleInstance", out var isFirst);
        if (!isFirst)
        {
            MessageBox.Show("Zonic is already running.", "Zonic", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        base.OnStartup(e);

        var window = new MainWindow();
        MainWindow = window;
        window.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Settings.Save();
        _single?.Dispose();
        base.OnExit(e);
    }
}
