using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Reflection;
using System.Text.Json;
using System.Windows;

namespace Zonic;

public sealed record UpdateInfo(string Version, string PageUrl, string AssetUrl);

/// <summary>Checks GitHub for a newer release and swaps the app folder for the new one.
/// Windows will not let a running exe overwrite itself, so the swap happens in a small
/// batch file that waits for this process to exit.</summary>
public sealed class Updater
{
    public static Updater Shared { get; } = new();

    private const string Repo = "SmartSparkCoding/zonic";
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private bool _busy;

    public static string CurrentVersion =>
        Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";

    public async Task<UpdateInfo?> CheckAsync()
    {
        if (_busy) { return null; }
        _busy = true;
        try
        {
            var request = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{Repo}/releases/latest");
            request.Headers.TryAddWithoutValidation("User-Agent", "Zonic for Windows");
            request.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");

            using var response = await _http.SendAsync(request);
            if (!response.IsSuccessStatusCode) { return null; }
            var body = await response.Content.ReadAsStringAsync();
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;

            var tag = root.TryGetProperty("tag_name", out var t) ? t.GetString() ?? "" : "";
            var version = tag.TrimStart('v', 'V');
            if (string.IsNullOrEmpty(version) || !IsNewer(version, CurrentVersion)) { return null; }

            var page = root.TryGetProperty("html_url", out var h) ? h.GetString() ?? "" : "";
            var asset = "";
            if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
            {
                foreach (var entry in assets.EnumerateArray())
                {
                    var name = entry.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                    if (name.Contains("windows", StringComparison.OrdinalIgnoreCase) &&
                        name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                    {
                        asset = entry.TryGetProperty("browser_download_url", out var u) ? u.GetString() ?? "" : "";
                        break;
                    }
                }
            }
            if (string.IsNullOrEmpty(asset)) { return null; }
            return new UpdateInfo(version, page, asset);
        }
        catch (Exception)
        {
            return null;
        }
        finally
        {
            _busy = false;
        }
    }

    /// <summary>Compares the numeric parts only, so 0.54.0 beats 0.53.0 and a run number
    /// that jumps by twenty still counts as newer.</summary>
    public static bool IsNewer(string candidate, string current)
    {
        var a = candidate.Split('.');
        var b = current.Split('.');
        for (var i = 0; i < Math.Max(a.Length, b.Length); i++)
        {
            var left = i < a.Length && int.TryParse(a[i], out var x) ? x : 0;
            var right = i < b.Length && int.TryParse(b[i], out var y) ? y : 0;
            if (left != right) { return left > right; }
        }
        return false;
    }

    public async Task InstallAsync(UpdateInfo info)
    {
        var appFolder = AppContext.BaseDirectory.TrimEnd('\\');
        var staging = Path.Combine(Path.GetTempPath(), "zonic-update-" + info.Version);

        try
        {
            if (Directory.Exists(staging)) { Directory.Delete(staging, true); }
            Directory.CreateDirectory(staging);

            var zip = Path.Combine(staging, "update.zip");
            using (var response = await _http.GetAsync(info.AssetUrl))
            {
                response.EnsureSuccessStatusCode();
                await using var file = File.Create(zip);
                await response.Content.CopyToAsync(file);
            }

            var extracted = Path.Combine(staging, "app");
            ZipFile.ExtractToDirectory(zip, extracted, true);

            // Releases are zipped with the app in a folder; find the folder holding the exe.
            var source = Directory.GetFiles(extracted, "Zonic.exe", SearchOption.AllDirectories)
                .Select(Path.GetDirectoryName)
                .FirstOrDefault();
            if (source is null)
            {
                MessageBox.Show("That download did not contain Zonic.exe.", "Zonic");
                return;
            }

            var script = Path.Combine(staging, "install.bat");
            File.WriteAllText(script, $"""
                @echo off
                :wait
                tasklist /fi "imagename eq Zonic.exe" | find /i "Zonic.exe" >nul
                if not errorlevel 1 (
                  timeout /t 1 /nobreak >nul
                  goto wait
                )
                xcopy /y /e /i /q "{source}\*" "{appFolder}\"
                start "" "{Path.Combine(appFolder, "Zonic.exe")}"
                del "%~f0"
                """);

            Process.Start(new ProcessStartInfo(script)
            {
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Hidden
            });
            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            MessageBox.Show("The update did not install: " + ex.Message, "Zonic");
        }
    }
}
