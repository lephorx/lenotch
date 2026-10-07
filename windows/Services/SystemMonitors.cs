using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Lenotch.Services;

/// Battery level and charging state, polled (the battery changes slowly).
public sealed class BatteryMonitor
{
    [StructLayout(LayoutKind.Sequential)]
    private struct SYSTEM_POWER_STATUS
    {
        public byte ACLineStatus;
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;
        public int BatteryLifeTime;
        public int BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll")]
    private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);

    public event Action? Changed;
    public bool HasBattery { get; private set; }
    /// 0...1
    public double Level { get; private set; } = 1;
    public bool IsCharging { get; private set; }
    public bool IsPluggedIn { get; private set; }
    /// Battery saver is on.
    public bool IsSaver { get; private set; }

    public BatteryMonitor()
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(20) };
        timer.Tick += (_, _) => Read();
        timer.Start();
        // PowerModeChanged arrives on SystemEvents' own thread.
        var dispatcher = Dispatcher.CurrentDispatcher;
        SystemEvents.PowerModeChanged += (_, _) => dispatcher.BeginInvoke(() => Read());
        Read();
    }

    private void Read()
    {
        if (!GetSystemPowerStatus(out var status)) return;
        // 128 = no system battery, 255 = unknown.
        var hasBattery = (status.BatteryFlag & 128) == 0 && status.BatteryFlag != 255;
        var level = status.BatteryLifePercent <= 100 ? status.BatteryLifePercent / 100.0 : 1;
        var plugged = status.ACLineStatus == 1;
        var charging = (status.BatteryFlag & 8) != 0;
        var saver = status.SystemStatusFlag == 1;
        if (hasBattery == HasBattery && Math.Abs(level - Level) < 0.001 && plugged == IsPluggedIn
            && charging == IsCharging && saver == IsSaver) return;
        HasBattery = hasBattery;
        Level = level;
        IsPluggedIn = plugged;
        IsCharging = charging;
        IsSaver = saver;
        Changed?.Invoke();
    }
}

public readonly record struct NetworkSpeed(double Down, double Up);

/// Download and upload speed over Wi-Fi/Ethernet from the adapters' byte counters.
/// Reports a speed while a sizeable transfer runs, nil when quiet again.
public sealed class NetworkMonitor
{
    public event Action<NetworkSpeed?>? Changed;

    /// Starts showing above 1 MB/s for 2 seconds, hides below 150 KB/s for 3 seconds.
    private const double StartRate = 1_000_000, StopRate = 150_000;
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private (long down, long up, DateTime time)? last;
    private int fastSeconds, slowSeconds;
    private bool isBusy;

    public NetworkMonitor()
    {
        timer.Tick += (_, _) => Tick();
    }

    public bool IsEnabled
    {
        get => timer.IsEnabled;
        set
        {
            if (value == timer.IsEnabled) return;
            if (value)
            {
                last = Counters();
                timer.Start();
            }
            else
            {
                timer.Stop();
                if (isBusy) { isBusy = false; Changed?.Invoke(null); }
            }
        }
    }

    private void Tick()
    {
        var now = Counters();
        var previous = last;
        last = now;
        if (previous is not { } before) return;
        var seconds = Math.Max((now.time - before.time).TotalSeconds, 0.1);
        var speed = new NetworkSpeed(Math.Max(now.down - before.down, 0) / seconds, Math.Max(now.up - before.up, 0) / seconds);
        var rate = Math.Max(speed.Down, speed.Up);
        fastSeconds = rate >= StartRate ? fastSeconds + 1 : 0;
        slowSeconds = rate < StopRate ? slowSeconds + 1 : 0;
        if (!isBusy && fastSeconds >= 2)
        {
            isBusy = true;
        }
        else if (isBusy && slowSeconds >= 3)
        {
            isBusy = false;
            Changed?.Invoke(null);
        }
        if (isBusy) Changed?.Invoke(speed);
    }

    /// Summed counters of the physical adapters, so VPNs and virtual switches don't count twice.
    private static (long down, long up, DateTime time) Counters()
    {
        long down = 0, up = 0;
        try
        {
            foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (adapter.OperationalStatus != OperationalStatus.Up) continue;
                if (adapter.NetworkInterfaceType is not (NetworkInterfaceType.Ethernet or NetworkInterfaceType.Wireless80211
                    or NetworkInterfaceType.GigabitEthernet or NetworkInterfaceType.FastEthernetT)) continue;
                var description = adapter.Description.ToLowerInvariant();
                if (adapter.Name.StartsWith("vEthernet", StringComparison.OrdinalIgnoreCase)
                    || description.Contains("virtual") || description.Contains("hyper-v")
                    || description.Contains("vpn") || description.Contains("tap-")) continue;
                var stats = adapter.GetIPStatistics();
                down += stats.BytesReceived;
                up += stats.BytesSent;
            }
        }
        catch (NetworkInformationException) { }
        return (down, up, DateTime.UtcNow);
    }

    /// "12.4 MB/s", "850 KB/s".
    public static string Format(double bytesPerSecond) => bytesPerSecond >= 1_000_000
        ? (bytesPerSecond >= 100_000_000 ? $"{bytesPerSecond / 1_000_000:0} MB/s" : $"{bytesPerSecond / 1_000_000:0.0} MB/s")
        : $"{bytesPerSecond / 1000:0} KB/s";
}

public sealed record PrivacyActivity(bool IsMicOn, bool IsCameraOn)
{
    public static readonly PrivacyActivity None = new(false, false);
    public bool IsEmpty => !IsMicOn && !IsCameraOn;
}

/// Whether any app uses the microphone or camera right now, from the same records
/// Windows' own privacy indicator uses (no permission needed).
public sealed class PrivacyMonitor
{
    private const string Root = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\";
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1.5) };
    private PrivacyActivity current = PrivacyActivity.None;

    public event Action<PrivacyActivity>? Changed;

    public PrivacyMonitor()
    {
        timer.Tick += (_, _) => Poll();
    }

    public bool IsEnabled
    {
        get => timer.IsEnabled;
        set
        {
            if (value == timer.IsEnabled) return;
            if (value) { timer.Start(); Poll(); }
            else { timer.Stop(); Publish(PrivacyActivity.None); }
        }
    }

    private void Poll() => Publish(new PrivacyActivity(InUse("microphone"), InUse("webcam")));

    private void Publish(PrivacyActivity activity)
    {
        if (activity == current) return;
        current = activity;
        Changed?.Invoke(activity);
    }

    private static readonly string OwnExe = (Environment.ProcessPath ?? "").Replace('\\', '#');

    private static bool InUse(string capability)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(Root + capability);
            if (key == null) return false;
            return AnyActive(key) || (key.OpenSubKey("NonPackaged") is { } desktop && Using(desktop, AnyActive));
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static bool Using(RegistryKey key, Func<RegistryKey, bool> body)
    {
        using (key) return body(key);
    }

    /// An app whose last use started but hasn't stopped is using the device now.
    private static bool AnyActive(RegistryKey parent)
    {
        foreach (var name in parent.GetSubKeyNames())
        {
            if (name == "NonPackaged" || (OwnExe.Length > 0 && name.Equals(OwnExe, StringComparison.OrdinalIgnoreCase))) continue;
            using var app = parent.OpenSubKey(name);
            if (app?.GetValue("LastUsedTimeStop") is long stop && stop == 0
                && app.GetValue("LastUsedTimeStart") is long start && start > 0) return true;
        }
        return false;
    }
}

/// A countdown started from the notch. It keeps running while the notch is closed
/// and raises `Finished` when it reaches zero.
public sealed class NotchTimer
{
    private readonly DispatcherTimer finishTimer = new();

    public double Duration { get; private set; }
    public DateTime? EndDate { get; private set; }
    public double? PausedRemaining { get; private set; }
    public bool IsSilent { get; private set; }
    /// Whether the timer that last finished was silent.
    public bool LastWasSilent { get; private set; }

    public event Action? Changed;
    public event Action? Finished;

    public bool IsActive => EndDate != null || PausedRemaining != null;
    public bool IsPaused => PausedRemaining != null;

    public NotchTimer()
    {
        finishTimer.Tick += (_, _) =>
        {
            if (EndDate is { } end && DateTime.UtcNow < end)
            {
                finishTimer.Interval = end - DateTime.UtcNow;
                return;
            }
            LastWasSilent = IsSilent;
            Cancel();
            Finished?.Invoke();
        };
    }

    public double Remaining(DateTime now)
    {
        if (PausedRemaining is { } paused) return paused;
        return EndDate is { } end ? Math.Max((end - now).TotalSeconds, 0) : 0;
    }

    /// 1 when just started, 0 when done.
    public double Fraction(DateTime now) => Duration > 0 ? Remaining(now) / Duration : 0;

    public void Start(double seconds, bool silent)
    {
        Duration = seconds;
        IsSilent = silent;
        PausedRemaining = null;
        Schedule(DateTime.UtcNow.AddSeconds(seconds));
    }

    public void Pause()
    {
        if (EndDate is not { } end) return;
        PausedRemaining = Math.Max((end - DateTime.UtcNow).TotalSeconds, 0);
        EndDate = null;
        finishTimer.Stop();
        Changed?.Invoke();
    }

    public void Resume()
    {
        if (PausedRemaining is not { } remaining) return;
        PausedRemaining = null;
        Schedule(DateTime.UtcNow.AddSeconds(remaining));
    }

    public void Add(double seconds)
    {
        Duration += seconds;
        if (PausedRemaining is { } paused) { PausedRemaining = paused + seconds; Changed?.Invoke(); }
        else if (EndDate is { } end) Schedule(end.AddSeconds(seconds));
    }

    public void Cancel()
    {
        finishTimer.Stop();
        EndDate = null;
        PausedRemaining = null;
        Duration = 0;
        Changed?.Invoke();
    }

    private void Schedule(DateTime end)
    {
        EndDate = end;
        finishTimer.Stop();
        finishTimer.Interval = end - DateTime.UtcNow > TimeSpan.Zero ? end - DateTime.UtcNow : TimeSpan.FromMilliseconds(1);
        finishTimer.Start();
        Changed?.Invoke();
    }

    /// "4:59", "1:02:03".
    public static string Format(double seconds)
    {
        var total = (int)Math.Ceiling(seconds);
        int h = total / 3600, m = total / 60 % 60, s = total % 60;
        return h > 0 ? $"{h}:{m:00}:{s:00}" : $"{m}:{s:00}";
    }
}

/// Start with Windows, through the current user's Run key (no admin rights or installer).
public static class LaunchAtLogin
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    /// Where Task Manager's Startup apps page records entries the user switched off.
    private const string ApprovedKey = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            if (key?.GetValue("Lenotch") is not string) return false;
            // An odd first byte means it was disabled in Task Manager.
            using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey);
            return approved?.GetValue("Lenotch") is not byte[] { Length: > 0 } state || state[0] % 2 == 0;
        }
        set
        {
            try
            {
                using (var key = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (value && Environment.ProcessPath is { } path) key.SetValue("Lenotch", $"\"{path}\"");
                    else key.DeleteValue("Lenotch", false);
                }
                // Turning it on here also lifts a block set in Task Manager.
                using var approved = Registry.CurrentUser.OpenSubKey(ApprovedKey, writable: true);
                approved?.DeleteValue("Lenotch", false);
            }
            catch (Exception error)
            {
                App.Log($"Couldn't change Start with Windows: {error.Message}");
            }
        }
    }

    /// Keeps the entry pointing at this exe after it was moved or updated.
    public static void Refresh()
    {
        if (IsEnabled) IsEnabled = true;
    }
}
