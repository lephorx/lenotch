using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Threading;
using Lenotch.Core;

namespace Lenotch.Services;

/// Looks for a newer Lenotch.exe on the latest GitHub release and swaps it in.
public sealed class UpdateService
{
    private const string LatestRelease = "https://api.github.com/repos/lephorx/lenotch/releases/latest";
    private readonly AppSettings settings;

    public event Action? Changed;
    public string? AvailableVersion { get; private set; }
    public bool IsInstalling { get; private set; }
    private string? downloadUrl;

    public static Version CurrentVersion =>
        Assembly.GetExecutingAssembly().GetName().Version ?? new Version(0, 0);

    public static string CurrentVersionText
    {
        get
        {
            var v = CurrentVersion;
            return v.Build > 0 ? $"{v.Major}.{v.Minor}.{v.Build}" : $"{v.Major}.{v.Minor}";
        }
    }

    public UpdateService(AppSettings settings)
    {
        this.settings = settings;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromHours(6) };
        timer.Tick += async (_, _) => { if (settings.CheckForUpdates) await Check(); };
        timer.Start();
    }

    /// Returns true when an update was found.
    public async Task<bool> Check()
    {
        try
        {
            using var request = new System.Net.Http.HttpRequestMessage(System.Net.Http.HttpMethod.Get, LatestRelease);
            request.Headers.Accept.ParseAdd("application/vnd.github+json");
            using var response = await Http.Client.SendAsync(request);
            if (!response.IsSuccessStatusCode) return false;
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            var root = document.RootElement;
            var tag = root.Text("tag_name")?.TrimStart('v', 'V');
            if (tag == null || !Version.TryParse(tag.Contains('.') ? tag : tag + ".0", out var latest)) return false;
            string? url = null;
            if (root.TryGetProperty("assets", out var assets))
                foreach (var asset in assets.EnumerateArray())
                    if (string.Equals(asset.Text("name"), "Lenotch.exe", StringComparison.OrdinalIgnoreCase))
                        url = asset.Text("browser_download_url");
            if (url == null || Normalize(latest) <= Normalize(CurrentVersion)) return false;
            AvailableVersion = tag;
            downloadUrl = url;
            Changed?.Invoke();
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static Version Normalize(Version v) => new(v.Major, v.Minor, Math.Max(v.Build, 0));

    /// Downloads the new exe, then a small script waits for Lenotch to quit,
    /// replaces the exe and starts it again.
    public async Task<bool> Install()
    {
        if (downloadUrl == null || Environment.ProcessPath is not { } exe || IsInstalling) return false;
        IsInstalling = true;
        Changed?.Invoke();
        try
        {
            var temp = Path.Combine(Path.GetTempPath(), "Lenotch-update.exe");
            await using (var source = await Http.Client.GetStreamAsync(downloadUrl))
            await using (var target = File.Create(temp))
                await source.CopyToAsync(target);

            var script = Path.Combine(Path.GetTempPath(), "Lenotch-update.cmd");
            var pid = Environment.ProcessId;
            File.WriteAllText(script, $"""
                @echo off
                :wait
                tasklist /FI "PID eq {pid}" | find "{pid}" >nul && (timeout /t 1 /nobreak >nul & goto wait)
                move /y "{temp}" "{exe}" >nul
                start "" "{exe}"
                del "%~f0"
                """);
            Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{script}\"")
            {
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                UseShellExecute = false,
            });
            settings.SaveNow();
            System.Windows.Application.Current.Shutdown();
            return true;
        }
        catch (Exception)
        {
            IsInstalling = false;
            Changed?.Invoke();
            return false;
        }
    }
}
