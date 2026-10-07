using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows.Threading;

namespace Lenotch.Core;

public enum OpenMode { Hover, Click }

/// How the calendar looks when it has the first tab to itself (music off).
public enum ExpandedCalendarStyle { Month, Strip }

/// Which player the notch follows.
public enum AudioSource { NowPlaying, Spotify, AppleMusic, Browser }

public static class AudioSourceInfo
{
    public static string Title(this AudioSource source) => source switch
    {
        AudioSource.NowPlaying => "Playing right now (any app)",
        AudioSource.Spotify => "Spotify",
        AudioSource.AppleMusic => "Apple Music",
        AudioSource.Browser => "Browser (YouTube Music, …)",
        _ => source.ToString(),
    };
}

public sealed record WeatherPlace(string Name, double Latitude, double Longitude);

/// An iCalendar (.ics) feed shown in the notch's calendar.
public sealed class CalendarFeed
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "Calendar";
    public string Url { get; set; } = "";
    public string Color { get; set; } = "#FF3B30";
    public bool Enabled { get; set; } = true;
}

/// A global shortcut: Win32 modifier flags (Alt 1, Ctrl 2, Shift 4, Win 8) and a virtual key.
public sealed record KeyShortcut(uint Modifiers, uint Key)
{
    public static readonly KeyShortcut ToggleDefault = new(1 | 4, 0x4E); // Alt+Shift+N
    public static readonly KeyShortcut PeekDefault = new(1 | 4, 0x50);   // Alt+Shift+P

    [JsonIgnore]
    public string Display
    {
        get
        {
            var parts = new List<string>();
            if ((Modifiers & 2) != 0) parts.Add("Ctrl");
            if ((Modifiers & 1) != 0) parts.Add("Alt");
            if ((Modifiers & 4) != 0) parts.Add("Shift");
            if ((Modifiers & 8) != 0) parts.Add("Win");
            var key = System.Windows.Input.KeyInterop.KeyFromVirtualKey((int)Key);
            parts.Add(key switch
            {
                >= System.Windows.Input.Key.D0 and <= System.Windows.Input.Key.D9 => ((int)(key - System.Windows.Input.Key.D0)).ToString(),
                _ => key.ToString(),
            });
            return string.Join("+", parts);
        }
    }
}

/// User preferences, saved as JSON in %APPDATA%\Lenotch\settings.json.
public sealed class AppSettings
{
    public static readonly string Folder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Lenotch");
    private static readonly string FilePath = Path.Combine(Folder, "settings.json");
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    /// Raised with the property name after any change.
    public event Action<string>? Changed;

    private bool loading;
    private DispatcherTimer? saveTimer;

    // MARK: Setup
    private bool hasPlayedIntro;
    public bool HasPlayedIntro { get => hasPlayedIntro; set => Set(ref hasPlayedIntro, value); }
    private string? lastSeenVersion;
    public string? LastSeenVersion { get => lastSeenVersion; set => Set(ref lastSeenVersion, value); }

    // MARK: General
    private bool showOnAllScreens = true;
    public bool ShowOnAllScreens { get => showOnAllScreens; set => Set(ref showOnAllScreens, value); }
    private OpenMode openMode = OpenMode.Hover;
    public OpenMode OpenMode { get => openMode; set => Set(ref openMode, value); }
    /// Seconds the pointer has to rest on the notch before it opens in hover mode.
    private double hoverDelay = 0.12;
    public double HoverDelay { get => hoverDelay; set => Set(ref hoverDelay, value); }
    private KeyShortcut? toggleShortcut = KeyShortcut.ToggleDefault;
    public KeyShortcut? ToggleShortcut { get => toggleShortcut; set => Set(ref toggleShortcut, value); }
    private KeyShortcut? peekShortcut = KeyShortcut.PeekDefault;
    public KeyShortcut? PeekShortcut { get => peekShortcut; set => Set(ref peekShortcut, value); }
    /// Hide the notch on a screen while an app is full screen there (games, videos).
    private bool hideInFullscreen = true;
    public bool HideInFullscreen { get => hideInFullscreen; set => Set(ref hideInFullscreen, value); }
    private bool showTrayIcon = true;
    public bool ShowTrayIcon { get => showTrayIcon; set => Set(ref showTrayIcon, value); }
    private bool checkForUpdates = true;
    public bool CheckForUpdates { get => checkForUpdates; set => Set(ref checkForUpdates, value); }
    private bool showBatteryIndicator = true;
    public bool ShowBatteryIndicator { get => showBatteryIndicator; set => Set(ref showBatteryIndicator, value); }
    private bool showBatteryPercentage = true;
    public bool ShowBatteryPercentage { get => showBatteryPercentage; set => Set(ref showBatteryPercentage, value); }

    // MARK: Look (Windows has the black style only)
    private bool tintEqualizer = true;
    public bool TintEqualizer { get => tintEqualizer; set => Set(ref tintEqualizer, value); }
    private bool tintProgressBar = true;
    public bool TintProgressBar { get => tintProgressBar; set => Set(ref tintProgressBar, value); }
    /// The album colour glows in the open notch's lower left.
    private bool backgroundFollowsMusic = true;
    public bool BackgroundFollowsMusic { get => backgroundFollowsMusic; set => Set(ref backgroundFollowsMusic, value); }

    // MARK: Music
    private bool showMusic = true;
    public bool ShowMusic { get => showMusic; set => Set(ref showMusic, value); }
    private AudioSource audioSource = AudioSource.NowPlaying;
    public AudioSource AudioSource { get => audioSource; set => Set(ref audioSource, value); }
    private bool peekOnTrackChange = true;
    public bool PeekOnTrackChange { get => peekOnTrackChange; set => Set(ref peekOnTrackChange, value); }
    private double trackPeekDuration = 3;
    public double TrackPeekDuration { get => trackPeekDuration; set => Set(ref trackPeekDuration, value); }
    private bool showShuffleRepeat = true;
    public bool ShowShuffleRepeat { get => showShuffleRepeat; set => Set(ref showShuffleRepeat, value); }
    /// Drive the equalizer bars from the actual system audio.
    private bool realAudioVisualizer = true;
    public bool RealAudioVisualizer { get => realAudioVisualizer; set => Set(ref realAudioVisualizer, value); }

    // MARK: Calendar
    private bool showCalendar = true;
    public bool ShowCalendar { get => showCalendar; set => Set(ref showCalendar, value); }
    private ExpandedCalendarStyle expandedCalendarStyle = ExpandedCalendarStyle.Month;
    public ExpandedCalendarStyle ExpandedCalendarStyle { get => expandedCalendarStyle; set => Set(ref expandedCalendarStyle, value); }
    private List<CalendarFeed> calendarFeeds = new();
    public List<CalendarFeed> CalendarFeeds { get => calendarFeeds; set => Set(ref calendarFeeds, value); }
    private bool autoScrollCalendar = true;
    public bool AutoScrollCalendar { get => autoScrollCalendar; set => Set(ref autoScrollCalendar, value); }
    private bool showFullEventTitles;
    public bool ShowFullEventTitles { get => showFullEventTitles; set => Set(ref showFullEventTitles, value); }

    // MARK: Weather
    private WeatherPlace? weatherPlace;
    public WeatherPlace? WeatherPlace { get => weatherPlace; set => Set(ref weatherPlace, value); }
    private bool weatherFahrenheit = RegionInfo.CurrentRegion.IsMetric == false;
    public bool WeatherFahrenheit { get => weatherFahrenheit; set => Set(ref weatherFahrenheit, value); }

    // MARK: Shelf
    private bool showShelfTab = true;
    public bool ShowShelfTab { get => showShelfTab; set => Set(ref showShelfTab, value); }
    /// The "Drop files here" shelf inside the tab; without it Share fills the tab.
    private bool showFileShelf = true;
    public bool ShowFileShelf { get => showFileShelf; set => Set(ref showFileShelf, value); }
    /// The Windows Share target (Nearby Sharing, mail, …), in place of AirDrop.
    private bool showShare = true;
    public bool ShowShare { get => showShare; set => Set(ref showShare, value); }
    private bool keepShelfItems = true;
    public bool KeepShelfItems { get => keepShelfItems; set => Set(ref keepShelfItems, value); }
    private bool openShelfOnDrag = true;
    public bool OpenShelfOnDrag { get => openShelfOnDrag; set => Set(ref openShelfOnDrag, value); }
    private List<string> shelfItems = new();
    public List<string> ShelfItems { get => shelfItems; set => Set(ref shelfItems, value); }

    [JsonIgnore] public bool HasShelfContent => ShowFileShelf || ShowShare;
    [JsonIgnore] public bool ShowsShelfTab => ShowShelfTab && HasShelfContent;

    // MARK: Timer
    private bool showTimer;
    public bool ShowTimer { get => showTimer; set => Set(ref showTimer, value); }
    private bool timerSilent;
    public bool TimerSilent { get => timerSilent; set => Set(ref timerSilent, value); }

    // MARK: Beside the notch
    private bool showPrivacyIndicator = true;
    public bool ShowPrivacyIndicator { get => showPrivacyIndicator; set => Set(ref showPrivacyIndicator, value); }
    private bool privacyGlow;
    public bool PrivacyGlow { get => privacyGlow; set => Set(ref privacyGlow, value); }
    private bool showNetworkSpeed;
    public bool ShowNetworkSpeed { get => showNetworkSpeed; set => Set(ref showNetworkSpeed, value); }
    private bool showCrypto;
    public bool ShowCrypto { get => showCrypto; set => Set(ref showCrypto, value); }
    private List<string> cryptoCoins = new() { "bitcoin", "ethereum" };
    public List<string> CryptoCoins { get => cryptoCoins; set => Set(ref cryptoCoins, value); }
    private string cryptoCurrency = DefaultCurrency();
    public string CryptoCurrency { get => cryptoCurrency; set => Set(ref cryptoCurrency, value); }

    // MARK: AI usage
    /// Off by default: the AI Usage tab only appears once switched on.
    private bool aiUsageEnabled;
    public bool AIUsageEnabled { get => aiUsageEnabled; set => Set(ref aiUsageEnabled, value); }
    /// Enabled usage sources in display order: built-in provider names or `custom:<uuid>`.
    private List<string> usageSourceKeys = new(AI.AIProviders.AllKeys);
    public List<string> UsageSourceKeys { get => usageSourceKeys; set => Set(ref usageSourceKeys, value); }
    private List<AI.CustomProvider> customProviders = new();
    public List<AI.CustomProvider> CustomProviders { get => customProviders; set => Set(ref customProviders, value); }
    private List<string> knownProviderConfigs = new();
    public List<string> KnownProviderConfigs { get => knownProviderConfigs; set => Set(ref knownProviderConfigs, value); }

    /// Providers loaded from config files in the Providers folder (not saved here).
    [JsonIgnore] public List<AI.CustomProvider> ConfigProviders { get; private set; } = new();
    [JsonIgnore] public IEnumerable<AI.CustomProvider> AllCustomProviders
    {
        get { foreach (var p in CustomProviders) yield return p; foreach (var p in ConfigProviders) yield return p; }
    }

    /// The enabled sources, resolved, in order.
    [JsonIgnore] public List<AI.UsageSource> UsageSources
    {
        get
        {
            var list = new List<AI.UsageSource>();
            foreach (var key in UsageSourceKeys)
                if (AI.UsageSource.Resolve(key, AllCustomProviders) is { } source) list.Add(source);
            return list;
        }
    }

    /// Re-reads the Providers folder. Configs seen for the first time are switched on.
    public void ReloadProviderConfigs()
    {
        ConfigProviders = AI.ProviderConfigStore.LoadAll();
        var known = new HashSet<string>(KnownProviderConfigs);
        var keys = new List<string>(UsageSourceKeys);
        foreach (var provider in ConfigProviders)
        {
            if (!known.Add(provider.Key)) continue;
            if (!keys.Contains(provider.Key)) keys.Add(provider.Key);
        }
        KnownProviderConfigs = new List<string>(known);
        UsageSourceKeys = keys;
        Changed?.Invoke(nameof(ConfigProviders));
    }

    private static string DefaultCurrency()
    {
        try
        {
            var code = new RegionInfo(CultureInfo.CurrentCulture.Name).ISOCurrencySymbol;
            return code is "EUR" or "CHF" or "GBP" or "JPY" ? code.ToLowerInvariant() : "usd";
        }
        catch (ArgumentException) { return "usd"; }
    }

    // MARK: Loading and saving

    public static AppSettings Load()
    {
        AppSettings settings;
        try
        {
            settings = File.Exists(FilePath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOptions) ?? new AppSettings()
                : new AppSettings();
        }
        catch (Exception)
        {
            settings = new AppSettings();
        }
        settings.loading = false;
        settings.ReloadProviderConfigs();
        return settings;
    }

    public AppSettings() { loading = true; }

    /// Tells listeners a list setting changed in place.
    public void Touch(string name)
    {
        Changed?.Invoke(name);
        ScheduleSave();
    }

    private void Set<T>(ref T field, T value, [CallerMemberName] string name = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value) && field is not System.Collections.IList) return;
        field = value;
        if (loading) return;
        Changed?.Invoke(name);
        ScheduleSave();
    }

    private void ScheduleSave()
    {
        if (saveTimer == null)
        {
            saveTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
            saveTimer.Tick += (_, _) => { saveTimer.Stop(); SaveNow(); };
        }
        saveTimer.Stop();
        saveTimer.Start();
    }

    public void SaveNow()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(this, JsonOptions));
            File.Move(temp, FilePath, overwrite: true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
