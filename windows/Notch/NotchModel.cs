using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using Lenotch.AI;
using Lenotch.Core;
using Lenotch.Services;

namespace Lenotch.Notch;

/// The three fixed views in the open notch.
public enum NotchPage { Player, Shelf, AIUsage }

/// Sizes the notch grows to in each state (DIPs). Windows has no hardware notch,
/// so a virtual one sits at the top centre of each screen.
public sealed class NotchGeometry
{
    public static readonly Size NotchSize = new(190, 32);
    public const double OpenBodyHeight = 166;
    /// Tallest a tab can be (the expanded calendar's month grid).
    public const double MaxBodyHeight = 236;
    public const double OpenWidth = 688;
    public const double IndicatorSideWidth = 110;
    public const double TimerSideWidth = 92;
    /// Room under the open notch for the AI usage bubble.
    public const double TooltipHeight = 330;

    public const double ClosedTopRadius = 6, ClosedBottomRadius = 12;
    public const double OpenTopRadius = 22, OpenBottomRadius = 44;

    /// Width of the screen the notch is on.
    public double ScreenWidth { get; }

    public NotchGeometry(double screenWidth)
    {
        ScreenWidth = screenWidth;
    }

    public Size ClosedSize => NotchSize;
    /// Collapsed notch with artwork on the left and bars on the right.
    public Size LiveSize => new(NotchSize.Width + 2 * (NotchSize.Height + 12), NotchSize.Height);
    public Size IndicatorSize => new(NotchSize.Width + 2 * IndicatorSideWidth, NotchSize.Height);
    public Size TimerSize => new(NotchSize.Width + 2 * TimerSideWidth, NotchSize.Height);
    public Size TimerDoneSize => new(NotchSize.Width + 200, NotchSize.Height + 64);
    public Size PeekSize => new(NotchSize.Width + 240, NotchSize.Height + 58);
    public Size IntroSize => new(NotchSize.Width + 180, NotchSize.Height + 110);

    /// Largest open size (the player and calendar tab).
    public Size OpenSize => new(Math.Min(OpenWidth, ScreenWidth - 24), NotchSize.Height + OpenBodyHeight);

    /// Open size for a tab whose content needs `contentWidth` × `bodyHeight`, kept wide
    /// enough for the header and within the largest size.
    public Size OpenSizeFor(double contentWidth, double bodyHeight) =>
        new(Math.Min(Math.Max(contentWidth, NotchSize.Width + 340), OpenSize.Width),
            NotchSize.Height + Math.Min(bodyHeight, MaxBodyHeight));

    /// The window is sized for the widest page plus the bubble below; the black shape animates inside it.
    public Size WindowSize => new(OpenSize.Width + 2 * OpenTopRadius, NotchSize.Height + MaxBodyHeight + TooltipHeight);
}

/// Which ring the pointer is on, and where it is horizontally in the notch window.
public sealed record UsageHover(string Id, double AnchorX);

/// State of one screen's notch; views read it and `Changed` tells them to update.
public sealed class NotchModel
{
    public enum NotchState { Closed, Open }

    public NotchState State { get; set; } = NotchState.Closed;
    public bool IsOpen => State == NotchState.Open;
    public bool IsShowingIntro { get; set; }
    /// Briefly showing the current song under the closed notch.
    public bool IsPeeking { get; set; }
    public bool IsTimerPanelVisible { get; set; }
    /// A timer just ended: the notch folds down with a ringing bell.
    public bool IsTimerFinished { get; set; }
    /// Transfer speed while a download or upload runs (nil when quiet).
    public NetworkSpeed? Network { get; set; }
    public PrivacyActivity Privacy { get; set; } = PrivacyActivity.None;
    public NotchPage SelectedPage { get; set; } = NotchPage.Player;
    /// Set while the user drags the progress bar so the notch does not close mid-scrub.
    public bool IsInteracting { get; set; }
    public UsageHover? UsageHover { get; private set; }
    /// Whether the last page change moved right (for the slide direction).
    public bool PageMovesForward { get; private set; } = true;

    public NotchGeometry Geometry { get; set; }
    public AppServices Services { get; }
    public AppSettings Settings => Services.Settings;
    public MediaService Media => Services.Media;
    public NotchTimer Timer => Services.Timer;

    /// Something the notch shows changed.
    public event Action? Changed;
    /// The page or open size changed.
    public event Action? PageChanged;
    public event Action? UsageHoverChanged;
    public Action? StopAlarm { get; set; }
    public Action? OpenSettings { get; set; }
    public Action<IReadOnlyCollection<string>>? Share { get; set; }
    public Action? ChooseAndShare { get; set; }

    public NotchModel(NotchGeometry geometry, AppServices services)
    {
        Geometry = geometry;
        Services = services;
    }

    public void NotifyChanged() => Changed?.Invoke();

    public void SetUsageHover(UsageHover? hover)
    {
        if (hover == UsageHover) return;
        UsageHover = hover;
        UsageHoverChanged?.Invoke();
    }

    public bool ShowsNetwork => Settings.ShowNetworkSpeed && Network != null;
    public bool ShowsCrypto => Settings.ShowCrypto && Services.Crypto.Prices.Count > 0;
    public bool ShowsPrivacy => Settings.ShowPrivacyIndicator && !Privacy.IsEmpty;
    public bool ShowsLiveActivity => Media.Track != null && Media.IsPlaying;
    public bool ShowsCalendar => Settings.ShowCalendar;

    public Color? AccentColor => Media.AccentColor;
    public Color EqualizerColor => Settings.TintEqualizer ? AccentColor ?? Colors.White : Colors.White;
    /// `null` means the default (white) progress fill.
    public Color? ProgressColor => Settings.TintProgressBar ? AccentColor : null;

    /// Real audio levels for the equalizer, when that's turned on.
    public AudioVisualizer? EqualizerSource => Settings.RealAudioVisualizer ? Services.Visualizer : null;

    // MARK: Pages

    /// Tabs shown in the notch; AI Usage only once it's switched on in Settings.
    public List<NotchPage> Pages => Enum.GetValues<NotchPage>().Where(page => page switch
    {
        NotchPage.Shelf => Settings.ShowsShelfTab,
        NotchPage.AIUsage => Settings.AIUsageEnabled,
        _ => true,
    }).ToList();

    /// The selected tab, falling back to the player when it's been switched off.
    public NotchPage VisiblePage => Pages.Contains(SelectedPage) ? SelectedPage : NotchPage.Player;

    public double OpenWidthNow => OpenSizeFor(VisiblePage).Width;

    /// Each tab is only as big as what it shows.
    public Size OpenSizeFor(NotchPage page)
    {
        switch (page)
        {
            case NotchPage.Player:
                return (Settings.ShowMusic, ShowsCalendar) switch
                {
                    (true, true) => Geometry.OpenSize,
                    (true, false) => Geometry.OpenSizeFor(460, 166),
                    // The month grid needs the taller tab; the day strip keeps the usual height.
                    (false, true) => Settings.ExpandedCalendarStyle == ExpandedCalendarStyle.Month
                        ? Geometry.OpenSizeFor(600, NotchGeometry.MaxBodyHeight)
                        : Geometry.OpenSizeFor(580, 166),
                    // Neither: logo, name, time and the weather.
                    _ => Geometry.OpenSizeFor(540, 150),
                };
            case NotchPage.Shelf:
                // Share alone is a smaller tab, stretched across it.
                return Geometry.OpenSizeFor(Settings.ShowFileShelf ? 500 : 380, 150);
            default:
                // Rings: 8 per row at most, two rows at most.
                var count = Math.Min(Math.Max(VisibleUsageCount, 1), 16);
                var perRow = Math.Min(count, 8);
                var rowWidth = perRow * 52 + (perRow - 1) * 26;
                return Geometry.OpenSizeFor(rowWidth + 60, count > 8 ? 160 : 118);
        }
    }

    /// AI usage sources with something to show (tools that aren't set up are hidden).
    public int VisibleUsageCount =>
        Settings.UsageSources.Count(s => Services.AIUsage.UsageOf(s.Id) is not ProviderUsage.NotSetUp);

    /// Switches pages with a slide in the matching direction.
    public void Select(NotchPage page)
    {
        var changed = false;
        if (IsTimerPanelVisible)
        {
            IsTimerPanelVisible = false;
            changed = true;
        }
        if (page != VisiblePage)
        {
            PageMovesForward = page > VisiblePage;
            SelectedPage = page;
            changed = true;
        }
        if (changed) PageChanged?.Invoke();
    }

    /// Moves to the next (+1) or previous (-1) page; used by swipes.
    public void SelectPage(int offset)
    {
        var pages = Pages;
        var index = pages.IndexOf(VisiblePage) + offset;
        if (index >= 0 && index < pages.Count) Select(pages[index]);
    }

    public void ToggleTimerPanel()
    {
        IsTimerPanelVisible = !IsTimerPanelVisible;
        PageChanged?.Invoke();
    }

    /// Uses the open notch's shape and background.
    public bool IsExpanded => IsOpen || IsShowingIntro || IsTimerFinished || IsPeeking;

    public Size CurrentSize
    {
        get
        {
            if (IsShowingIntro) return Geometry.IntroSize;
            if (IsTimerFinished && !IsOpen) return Geometry.TimerDoneSize;
            if (IsPeeking && !IsOpen) return Geometry.PeekSize;
            if (IsOpen) return OpenSizeFor(VisiblePage);
            if (Timer.IsActive) return Geometry.TimerSize;
            if (ShowsLiveActivity) return Geometry.LiveSize;
            if (ShowsNetwork || ShowsCrypto) return Geometry.IndicatorSize;
            return Geometry.ClosedSize;
        }
    }
}

/// Everything shared by all screens' notches.
public sealed class AppServices
{
    public AppSettings Settings { get; }
    public MediaService Media { get; }
    public AudioVisualizer Visualizer { get; } = new();
    public BatteryMonitor Battery { get; } = new();
    public ShelfStore Shelf { get; }
    public CalendarService Calendar { get; }
    public WeatherService Weather { get; }
    public CryptoService Crypto { get; }
    public AIUsageService AIUsage { get; } = new();
    public NotchTimer Timer { get; } = new();
    public NetworkMonitor Network { get; } = new();
    public PrivacyMonitor Privacy { get; } = new();
    public UpdateService Updates { get; }

    public AppServices(AppSettings settings)
    {
        Settings = settings;
        Media = new MediaService(settings);
        Shelf = new ShelfStore(settings);
        Calendar = new CalendarService(settings);
        Weather = new WeatherService(settings);
        Crypto = new CryptoService(settings);
        Updates = new UpdateService(settings);
    }
}
