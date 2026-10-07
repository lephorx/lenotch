using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Lenotch.Core;
using Lenotch.Notch;
using Lenotch.Services;
using Lenotch.Settings;
using Microsoft.Win32;

namespace Lenotch;

/// Lenotch for Windows: a notch at the top of the screen, a tray icon, and Settings.
public sealed class App : Application
{
    private const string InstanceName = "Lenotch.Instance";
    private const string ShowSettingsSignal = "Lenotch.ShowSettings";

    private AppSettings settings = null!;
    private AppServices services = null!;
    private readonly List<NotchWindow> notches = new();
    private TrayIcon? tray;
    private HotKeys? hotKeys;
    private SettingsWindow? settingsWindow;
    private readonly DateTime launched = DateTime.UtcNow;
    private static Mutex? instance;
    private DebugHooks? debugHooks;

    [STAThread]
    public static void Main()
    {
        instance = new Mutex(true, InstanceName, out var isFirst);
        if (!isFirst)
        {
            // Opening Lenotch again shows Settings in the running copy (useful with the tray icon hidden).
            try { EventWaitHandle.OpenExisting(ShowSettingsSignal).Set(); } catch (Exception) { }
            return;
        }
        var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Run();
        GC.KeepAlive(instance);
    }

    public static readonly string LogFile = System.IO.Path.Combine(AppSettings.Folder, "lenotch.log");

    /// Appends to %APPDATA%\Lenotch\lenotch.log (kept small).
    public static void Log(string message)
    {
        try
        {
            System.IO.Directory.CreateDirectory(AppSettings.Folder);
            if (System.IO.File.Exists(LogFile) && new System.IO.FileInfo(LogFile).Length > 512 * 1024) System.IO.File.Delete(LogFile);
            System.IO.File.AppendAllText(LogFile, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}\n");
        }
        catch (Exception) { }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // A failing view shouldn't take the whole notch down: log it and carry on.
        DispatcherUnhandledException += (_, args) =>
        {
            Log($"Unhandled: {args.Exception}");
            args.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, args) => Log($"Fatal: {args.ExceptionObject}");
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            Log($"Task: {args.Exception}");
            args.SetObserved();
        };
        Log($"Lenotch {UpdateService.CurrentVersionText} starting on {Environment.OSVersion}");
        Resources.MergedDictionaries.Add(new ResourceDictionary { Source = new Uri("pack://application:,,,/Settings/Theme.xaml") });
        settings = AppSettings.Load();
        services = new AppServices(settings);
        LaunchAtLogin.Refresh();

        ListenForSecondLaunch();
        BuildNotches();
        WireServices();

        tray = new TrayIcon(services, ShowSettings, PlayIntro, Quit) { Visible = settings.ShowTrayIcon };
        hotKeys = new HotKeys();
        hotKeys.Pressed += id =>
        {
            var target = NotchUnderPointer();
            if (id == HotKeys.Toggle) target?.ToggleOpen();
            else target?.Peek();
        };
        RegisterShortcuts();

        _ = services.Media.StartAsync();
        StartFullscreenWatch();
        debugHooks = DebugHooks.Start(() => notches, () => settingsWindow, section =>
        {
            ShowSettings();
            if (section != null && Enum.TryParse<SettingsSection>(section, true, out var target)) settingsWindow?.Show(target);
        });

        if (!settings.HasPlayedIntro)
        {
            settings.HasPlayedIntro = true;
            After(1.0, PlayIntro);
            After(4.2, () =>
            {
                ShowSettings();
                tray?.ShowBalloon("Lenotch is running", "Hover the top of your screen to open the notch. Settings are in the tray icon's menu.");
            });
        }
        settings.LastSeenVersion = UpdateService.CurrentVersionText;
        if (settings.CheckForUpdates) After(8, async () => await services.Updates.Check());
    }

    private void ListenForSecondLaunch()
    {
        var signal = new EventWaitHandle(false, EventResetMode.AutoReset, ShowSettingsSignal);
        var thread = new Thread(() =>
        {
            while (true)
            {
                signal.WaitOne();
                Dispatcher.BeginInvoke(ShowSettings);
            }
        }) { IsBackground = true, Name = "Lenotch second launch" };
        thread.Start();
    }

    // MARK: - Notches

    private void BuildNotches()
    {
        foreach (var notch in notches) notch.Close();
        notches.Clear();
        var screens = settings.ShowOnAllScreens
            ? System.Windows.Forms.Screen.AllScreens
            : new[] { System.Windows.Forms.Screen.PrimaryScreen! };
        foreach (var screen in screens)
        {
            var notch = new NotchWindow(services, screen);
            notch.Model.OpenSettings = ShowSettings;
            notch.Model.Network = currentSpeed;
            notch.Model.Privacy = currentPrivacy;
            notch.Show();
            notches.Add(notch);
        }
    }

    private void NotifyAll()
    {
        foreach (var notch in notches) notch.Update();
    }

    /// The notch on the screen with the pointer (or the primary one).
    private NotchWindow? NotchUnderPointer()
    {
        var screen = System.Windows.Forms.Screen.FromPoint(System.Windows.Forms.Cursor.Position);
        return notches.FirstOrDefault(n => n.Screen.DeviceName == screen.DeviceName) ?? notches.FirstOrDefault();
    }

    private void PlayIntro() => (notches.FirstOrDefault(n => n.Screen.Primary) ?? notches.FirstOrDefault())?.PlayIntro();

    private NetworkSpeed? currentSpeed;
    private PrivacyActivity currentPrivacy = PrivacyActivity.None;

    private void WireServices()
    {
        var media = services.Media;
        media.Changed += () =>
        {
            services.Visualizer.IsRunning = settings.RealAudioVisualizer && media.IsPlaying;
            NotifyAll();
        };
        media.TrackChanged += () =>
        {
            // Not for the song that's already playing when Lenotch starts.
            if ((DateTime.UtcNow - launched).TotalSeconds < 3) return;
            foreach (var notch in notches) notch.PeekForTrackChange();
        };
        services.Battery.Changed += NotifyAll;
        services.Crypto.Changed += NotifyAll;
        services.Weather.Changed += NotifyAll;
        services.Calendar.Changed += NotifyAll;
        services.Shelf.Changed += NotifyAll;
        services.AIUsage.Changed += NotifyAll;
        services.Timer.Changed += NotifyAll;
        services.Timer.Finished += () =>
        {
            foreach (var notch in notches) notch.TimerFinished();
            NotchUnderPointer()?.RingAlarm();
        };
        services.Network.Changed += speed =>
        {
            currentSpeed = speed;
            foreach (var notch in notches) notch.Model.Network = speed;
            NotifyAll();
        };
        services.Privacy.Changed += activity =>
        {
            currentPrivacy = activity;
            foreach (var notch in notches) notch.Model.Privacy = activity;
            NotifyAll();
        };
        services.Network.IsEnabled = settings.ShowNetworkSpeed;
        services.Privacy.IsEnabled = settings.ShowPrivacyIndicator;

        settings.Changed += name =>
        {
            switch (name)
            {
                case nameof(AppSettings.ShowOnAllScreens):
                    BuildNotches();
                    return;
                case nameof(AppSettings.ShowTrayIcon):
                    if (tray != null) tray.Visible = settings.ShowTrayIcon;
                    return;
                case nameof(AppSettings.ToggleShortcut) or nameof(AppSettings.PeekShortcut):
                    RegisterShortcuts();
                    return;
                case nameof(AppSettings.ShowNetworkSpeed):
                    services.Network.IsEnabled = settings.ShowNetworkSpeed;
                    break;
                case nameof(AppSettings.ShowPrivacyIndicator):
                    services.Privacy.IsEnabled = settings.ShowPrivacyIndicator;
                    break;
                case nameof(AppSettings.RealAudioVisualizer):
                    services.Visualizer.IsRunning = settings.RealAudioVisualizer && media.IsPlaying;
                    break;
                case nameof(AppSettings.HideInFullscreen):
                    if (!settings.HideInFullscreen) foreach (var notch in notches) notch.SetSuppressed(false);
                    break;
            }
            NotifyAll();
        };
        SystemEvents.DisplaySettingsChanged += (_, _) => Dispatcher.BeginInvoke(() => After(0.5, BuildNotches));
    }

    private void RegisterShortcuts()
    {
        if (hotKeys == null) return;
        hotKeys.Set(HotKeys.Toggle, settings.ToggleShortcut);
        hotKeys.Set(HotKeys.Peek, settings.PeekShortcut);
    }

    // MARK: - Full screen

    /// Hides the notch on a display while a game or video is full screen there,
    /// and keeps it above other always-on-top windows otherwise.
    private void StartFullscreenWatch()
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        var ticks = 0;
        timer.Tick += (_, _) =>
        {
            var fullscreen = FullscreenMonitor();
            foreach (var notch in notches)
            {
                var hide = settings.HideInFullscreen && fullscreen is { } bounds && notch.Screen.Bounds == bounds;
                notch.SetSuppressed(hide);
                if (++ticks % 5 == 0) notch.RaiseToTop();
            }
        };
        timer.Start();
    }

    [System.Runtime.InteropServices.DllImport("shell32.dll")]
    private static extern int SHQueryUserNotificationState(out int state);

    /// The display of the full-screen app in front, if any. Maximized windows don't
    /// count (they cover the screen with an auto-hidden taskbar), so Windows' own
    /// "full-screen app running" state (the one Focus Assist uses) has to agree.
    private static System.Drawing.Rectangle? FullscreenMonitor()
    {
        // QUNS_BUSY 2, QUNS_RUNNING_D3D_FULL_SCREEN 3, QUNS_PRESENTATION_MODE 4.
        if (SHQueryUserNotificationState(out var state) != 0 || state is not (2 or 3 or 4)) return null;
        var window = Native.GetForegroundWindow();
        if (window == IntPtr.Zero) return null;
        var className = Native.ClassName(window);
        if (className is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd" or "Windows.UI.Core.CoreWindow") return null;
        Native.GetWindowThreadProcessId(window, out var process);
        if (process == Environment.ProcessId) return null;
        if (!Native.GetWindowRect(window, out var rect)) return null;
        var monitor = Native.MonitorFromWindow(window, 2);
        var info = new Native.MONITORINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.MONITORINFO>() };
        if (!Native.GetMonitorInfo(monitor, ref info)) return null;
        var m = info.rcMonitor;
        var covers = rect.Left <= m.Left && rect.Top <= m.Top && rect.Right >= m.Right && rect.Bottom >= m.Bottom;
        return covers ? new System.Drawing.Rectangle(m.Left, m.Top, m.Right - m.Left, m.Bottom - m.Top) : null;
    }

    // MARK: - Windows

    private void ShowSettings()
    {
        if (settingsWindow == null)
        {
            settingsWindow = new SettingsWindow(services, PlayIntro);
            settingsWindow.Closed += (_, _) => settingsWindow = null;
            settingsWindow.Show();
        }
        if (settingsWindow.WindowState == WindowState.Minimized) settingsWindow.WindowState = WindowState.Normal;
        settingsWindow.Activate();
    }

    private void Quit()
    {
        settings.SaveNow();
        services.Visualizer.Dispose();
        tray?.Dispose();
        hotKeys?.Dispose();
        foreach (var notch in notches) notch.Close();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        settings.SaveNow();
        tray?.Dispose();
        base.OnExit(e);
    }

    private static void After(double seconds, Action action)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) => { timer.Stop(); action(); };
        timer.Start();
    }
}

/// System-wide shortcuts through RegisterHotKey on a message-only window.
public sealed class HotKeys : IDisposable
{
    public const int Toggle = 1, Peek = 2;
    private const uint ModNoRepeat = 0x4000;
    private readonly HwndSource source;
    private readonly HashSet<int> registered = new();

    public event Action<int>? Pressed;

    public HotKeys()
    {
        source = new HwndSource(new HwndSourceParameters("Lenotch shortcuts") { WindowStyle = 0, Width = 0, Height = 0, ParentWindow = new IntPtr(-3) });
        source.AddHook((IntPtr _, int message, IntPtr wParam, IntPtr _, ref bool handled) =>
        {
            if (message == Native.WM_HOTKEY)
            {
                Pressed?.Invoke(wParam.ToInt32());
                handled = true;
            }
            return IntPtr.Zero;
        });
    }

    /// Registers `shortcut` under `id`, or clears it for nil. Returns false if another app has it.
    public bool Set(int id, KeyShortcut? shortcut)
    {
        if (registered.Remove(id)) Native.UnregisterHotKey(source.Handle, id);
        if (shortcut == null) return true;
        var ok = Native.RegisterHotKey(source.Handle, id, shortcut.Modifiers | ModNoRepeat, shortcut.Key);
        if (ok) registered.Add(id);
        return ok;
    }

    public void Dispose()
    {
        foreach (var id in registered) Native.UnregisterHotKey(source.Handle, id);
        registered.Clear();
        source.Dispose();
    }
}

/// The notification-area icon and its menu.
public sealed class TrayIcon : IDisposable
{
    private readonly System.Windows.Forms.NotifyIcon icon;
    private readonly AppServices services;
    private readonly System.Windows.Forms.ToolStripMenuItem updateItem;

    public TrayIcon(AppServices services, Action showSettings, Action playIntro, Action quit)
    {
        this.services = services;
        var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/Tray.ico"))?.Stream;
        icon = new System.Windows.Forms.NotifyIcon
        {
            Text = "Lenotch",
            Icon = stream != null ? new System.Drawing.Icon(stream) : System.Drawing.SystemIcons.Application,
        };
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("Settings…", null, (_, _) => showSettings());
        updateItem = new System.Windows.Forms.ToolStripMenuItem("Check for Updates…", null, async (_, _) => await CheckOrInstall());
        menu.Items.Add(updateItem);
        menu.Items.Add("Play Intro", null, (_, _) => playIntro());
        menu.Items.Add(new System.Windows.Forms.ToolStripSeparator());
        menu.Items.Add("Hide Tray Icon", null, (_, _) => services.Settings.ShowTrayIcon = false);
        menu.Items.Add("Quit Lenotch", null, (_, _) => quit());
        icon.ContextMenuStrip = menu;
        icon.DoubleClick += (_, _) => showSettings();
        icon.MouseClick += (_, e) => { if (e.Button == System.Windows.Forms.MouseButtons.Left) showSettings(); };
        services.Updates.Changed += () =>
        {
            updateItem.Text = services.Updates.IsInstalling ? "Installing Update…"
                : services.Updates.AvailableVersion is { } version ? $"Install Lenotch {version}…" : "Check for Updates…";
            if (services.Updates.AvailableVersion is { } available && !services.Updates.IsInstalling)
                ShowBalloon("Update available", $"Lenotch {available} is ready. Choose Install from the tray icon's menu.");
        };
    }

    private async System.Threading.Tasks.Task CheckOrInstall()
    {
        if (services.Updates.AvailableVersion != null)
        {
            await services.Updates.Install();
            return;
        }
        if (!await services.Updates.Check())
            ShowBalloon("You're up to date", $"Lenotch {UpdateService.CurrentVersionText} is the latest version.");
    }

    public bool Visible
    {
        get => icon.Visible;
        set => icon.Visible = value;
    }

    public void ShowBalloon(string title, string text)
    {
        if (!icon.Visible) return;
        icon.ShowBalloonTip(5000, title, text, System.Windows.Forms.ToolTipIcon.None);
    }

    public void Dispose()
    {
        icon.Visible = false;
        icon.Dispose();
    }
}
