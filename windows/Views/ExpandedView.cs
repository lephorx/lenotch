using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Lenotch.Core;
using Lenotch.Notch;
using Lenotch.Services;

namespace Lenotch.Views;

/// The open notch: tabs and buttons in the header, the selected tab underneath.
public sealed class ExpandedView : NotchContentView
{
    private readonly NotchModel model;
    private readonly Grid header = new();
    private readonly Grid body = new() { Margin = new Thickness(30, 0, 30, 20), ClipToBounds = true };
    private NotchContentView? page;
    private string pageKey = "";
    private string headerKey = "";
    private BatteryView? battery;

    public ExpandedView(NotchModel model)
    {
        this.model = model;
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(NotchGeometry.NotchSize.Height) });
        RowDefinitions.Add(new RowDefinition());
        header.Margin = new Thickness(30, 0, 30, 0);
        Children.Add(header);
        SetRow(body, 1);
        Children.Add(body);

        // Files dropped on the notch go on the shelf when the file shelf is on;
        // dragging files over it opens the shelf tab.
        AllowDrop = true;
        Background = Brushes.Transparent;
        DragEnter += (_, e) =>
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop) && model.Settings.ShowsShelfTab) model.Select(NotchPage.Shelf);
        };
        DragOver += (_, e) =>
        {
            e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) && model.Settings.ShowsShelfTab && model.Settings.ShowFileShelf
                ? DragDropEffects.Link
                : DragDropEffects.None;
            e.Handled = true;
        };
        Drop += (_, e) =>
        {
            if (!model.Settings.ShowsShelfTab || !model.Settings.ShowFileShelf) return;
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files) model.Services.Shelf.Add(files);
        };
        Refresh();
    }

    public override void Refresh()
    {
        RefreshHeader();
        var key = model.IsTimerPanelVisible ? "timer" : PageKey();
        if (key != pageKey)
        {
            pageKey = key;
            ShowPage(model.IsTimerPanelVisible ? new TimerPanel(model) : MakePage());
        }
        else
        {
            page?.Refresh();
        }
    }

    /// Changes here rebuild the tab (other changes just refresh it).
    private string PageKey()
    {
        var s = model.Settings;
        return model.VisiblePage switch
        {
            NotchPage.Player => $"player|{s.ShowMusic}|{model.ShowsCalendar}|{s.ExpandedCalendarStyle}|{model.Media.Track != null}",
            NotchPage.Shelf => $"shelf|{s.ShowFileShelf}|{s.ShowShare}",
            _ => "ai",
        };
    }

    private NotchContentView MakePage() => model.VisiblePage switch
    {
        NotchPage.Player => new PlayerPage(model),
        NotchPage.Shelf => new ShelfView(model) { Width = 440 },
        _ => new AIUsageView(model),
    };

    /// The new tab's items slide in one by one; the old tab just fades.
    private void ShowPage(NotchContentView next)
    {
        var old = page;
        page = next;
        body.Children.Add(next);
        if (old == null) return;
        old.IsHitTestVisible = false;
        old.FadeTo(0, 0.12, () => body.Children.Remove(old));
    }

    private void RefreshHeader()
    {
        var s = model.Settings;
        var accent = model.AccentColor?.ToString() ?? "";
        var key = string.Join("|", model.Pages) + $"|{model.VisiblePage}|{accent}|{s.ShowTimer}|{model.Timer.IsActive}"
                  + $"|{model.IsTimerPanelVisible}|{s.ShowBatteryIndicator}|{s.ShowBatteryPercentage}|{model.Services.Battery.HasBattery}";
        if (key == headerKey)
        {
            battery?.Refresh();
            return;
        }
        headerKey = key;
        header.Children.Clear();

        var tabs = TabSwitcher();
        tabs.HorizontalAlignment = HorizontalAlignment.Left;
        tabs.VerticalAlignment = VerticalAlignment.Center;
        header.Children.Add(tabs);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        // Hidden unless turned on in Settings, but a running timer stays reachable.
        if (s.ShowTimer || model.Timer.IsActive)
            buttons.Children.Add(HeaderButton(Glyphs.Timer, model.IsTimerPanelVisible || model.Timer.IsActive, model.ToggleTimerPanel));
        buttons.Children.Add(HeaderButton(Glyphs.Settings, false, () => model.OpenSettings?.Invoke()));
        battery = null;
        if (s.ShowBatteryIndicator && model.Services.Battery.HasBattery)
        {
            battery = new BatteryView(model.Services.Battery, s.ShowBatteryPercentage) { Margin = new Thickness(10, 0, 0, 0) };
            buttons.Children.Add(battery);
        }
        header.Children.Add(buttons);
    }

    private static FrameworkElement HeaderButton(string glyph, bool isOn, Action action)
    {
        var icon = Ui.Icon(glyph, 12, Brushes.White);
        var host = new Border { Width = 22, Height = 22, Child = icon, Margin = new Thickness(4, 0, 0, 0) };
        return Ui.Button(host, action, hoverOpacity: isOn ? 1 : 0.9, idleOpacity: isOn ? 1 : 0.55);
    }

    /// The tabs in a capsule; the selection pill slides between them.
    private FrameworkElement TabSwitcher()
    {
        var pages = model.Pages;
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var tab in pages)
        {
            var selected = tab == model.VisiblePage;
            FrameworkElement label = tab == NotchPage.Player
                ? Ui.LogoView(13, selected ? model.AccentColor : null, selected ? 1 : 0.5)
                : Ui.Icon(tab == NotchPage.Shelf ? Glyphs.Shelf : Glyphs.Robot, 10, Ui.White(selected ? 1 : 0.5));
            label.HorizontalAlignment = HorizontalAlignment.Center;
            label.VerticalAlignment = VerticalAlignment.Center;
            var cell = new Border
            {
                Width = 26,
                Height = 18,
                CornerRadius = new CornerRadius(9),
                Background = Brushes.Transparent,
                Child = label,
                Margin = new Thickness(row.Children.Count > 0 ? 2 : 0, 0, 0, 0),
            };
            var target = tab;
            row.Children.Add(Ui.Button(cell, () => model.Select(target)));
        }

        // The pill sits behind the cells and slides to the selected one.
        var pill = new Border
        {
            Width = 26,
            Height = 18,
            CornerRadius = new CornerRadius(9),
            Background = Ui.White(0.18),
            HorizontalAlignment = HorizontalAlignment.Left,
            IsHitTestVisible = false,
        };
        var index = Math.Max(pages.IndexOf(model.VisiblePage), 0);
        var move = new TranslateTransform(lastPillX, 0);
        pill.RenderTransform = move;
        lastPillX = index * 28;
        move.Animate(TranslateTransform.XProperty, lastPillX, Motion.PageSpring);

        var stack = new Grid { Children = { pill, row } };
        return new Border
        {
            Padding = new Thickness(2),
            CornerRadius = new CornerRadius(11),
            Background = Ui.White(0.08),
            Child = stack,
        };
    }

    private double lastPillX;
}

/// The first tab: the player (with the calendar beside it), the calendar alone, or
/// the home view with the time and weather.
public sealed class PlayerPage : NotchContentView
{
    private readonly NotchModel model;
    private readonly NotchContentView? player;
    private readonly CalendarPanel? calendar;
    private readonly HomeView? home;

    public PlayerPage(NotchModel model)
    {
        this.model = model;
        var s = model.Settings;
        var forward = model.PageMovesForward;
        if (s.ShowMusic)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            player = model.Media.Track != null ? new NowPlayingView(model) : new IdleView(model);
            player.Width = 400;
            player.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(player);
            if (model.ShowsCalendar)
            {
                calendar = new CalendarPanel(model, 200, expanded: false) { Margin = new Thickness(28, 0, 0, 0) };
                calendar.SlideIn(4, forward);
                row.Children.Add(calendar);
            }
            Children.Add(row);
        }
        else if (model.ShowsCalendar)
        {
            // Without music the calendar takes the whole tab.
            calendar = new CalendarPanel(model, model.OpenWidthNow - 60, s.ExpandedCalendarStyle == ExpandedCalendarStyle.Month);
            calendar.SlideIn(0, forward);
            Children.Add(calendar);
        }
        else
        {
            home = new HomeView(model);
            Children.Add(home);
        }
    }

    public override void Refresh()
    {
        player?.Refresh();
        calendar?.Refresh();
        home?.Refresh();
    }
}

/// Nothing playing: a placeholder and a hint where to start music.
public sealed class IdleView : NotchContentView
{
    public IdleView(NotchModel model)
    {
        var square = new Border
        {
            Width = 120,
            Height = 120,
            CornerRadius = new CornerRadius(24),
            Background = Ui.White(0.08),
            Child = Ui.Icon(Glyphs.Music, 40, Ui.White(0.4)),
        };
        var hint = model.Settings.AudioSource switch
        {
            AudioSource.Spotify => "Play something in Spotify.",
            AudioSource.AppleMusic => "Play something in Apple Music.",
            AudioSource.Browser => "Play something in your browser.",
            _ => "Play something in any app or browser.",
        };
        var hintText = Ui.Text(hint, 14, FontWeights.Medium, Ui.White(0.5));
        hintText.TextWrapping = TextWrapping.Wrap;
        var text = Ui.VStack(4, Ui.Text("Not Playing", 16, FontWeights.Bold, Brushes.White), hintText);
        text.VerticalAlignment = VerticalAlignment.Center;
        text.Margin = new Thickness(24, 0, 0, 0);
        var row = new DockPanel();
        DockPanel.SetDock(square, Dock.Left);
        row.Children.Add(square);
        row.Children.Add(text);
        row.SlideIn(0, model.PageMovesForward);
        Children.Add(row);
    }
}

/// The first tab when both music and calendar are off: the Lenotch logo and name
/// with the time, and the current weather with a small animated scene.
public sealed class HomeView : NotchContentView
{
    private readonly NotchModel model;
    private readonly TextBlock time = Ui.Text("", 15, FontWeights.SemiBold, Ui.White(0.55), monospacedDigits: true);
    private readonly TextBlock date = Ui.Text("", 12, FontWeights.Medium, Ui.White(0.55));
    private readonly Border weatherHost = new() { HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
    private readonly System.Windows.Threading.DispatcherTimer clock = new() { Interval = TimeSpan.FromSeconds(15) };
    private string weatherKey = "";

    public HomeView(NotchModel model)
    {
        this.model = model;
        var forward = model.PageMovesForward;
        var name = Ui.VStack(2, Ui.Text("Lenotch", 20, FontWeights.Bold, Brushes.White), Ui.VStack(1, time, date));
        name.VerticalAlignment = VerticalAlignment.Center;
        name.Margin = new Thickness(14, 0, 0, 0);
        var brand = Ui.HStack(0, Ui.LogoView(46, model.AccentColor), name);
        brand.HorizontalAlignment = HorizontalAlignment.Left;
        brand.VerticalAlignment = VerticalAlignment.Center;
        brand.SlideIn(0, forward);
        Children.Add(brand);
        weatherHost.SlideIn(1, forward);
        Children.Add(weatherHost);

        clock.Tick += (_, _) => UpdateClock();
        Loaded += async (_, _) =>
        {
            clock.Start();
            // Fetch while visible only (the service itself waits 15 minutes between readings).
            await model.Services.Weather.RefreshIfNeeded();
            Refresh();
        };
        Unloaded += (_, _) => clock.Stop();
        UpdateClock();
        Refresh();
    }

    private void UpdateClock()
    {
        var now = DateTime.Now;
        time.Text = now.ToString("t");
        date.Text = now.ToString("dddd, d MMMM");
    }

    public override void Refresh()
    {
        var weather = model.Services.Weather;
        var reading = weather.Reading;
        var key = reading == null ? "" : $"{reading}{weather.PlaceName}";
        if (key == weatherKey && weatherHost.Child != null) return;
        weatherKey = key;
        if (reading == null)
        {
            weatherHost.Child = new Border { Width = 88, Height = 88 };
            return;
        }
        var details = Ui.VStack(2,
            Ui.Text($"{Math.Round(reading.Temperature)}°", 34, FontWeights.SemiBold, Brushes.White, monospacedDigits: true),
            Ui.Text(reading.Kind.Title(), 13, FontWeights.SemiBold, Ui.White(0.8)),
            Ui.Text($"H {Math.Round(reading.High)}°  L {Math.Round(reading.Low)}°", 11, FontWeights.Medium, Ui.White(0.5), true));
        if (weather.PlaceName is { } place)
        {
            var label = Ui.HStack(4, Ui.Icon(Glyphs.Location, 10, Ui.White(0.45)), Ui.Text(place, 11, FontWeights.Medium, Ui.White(0.45)));
            details.Children.Add(label);
        }
        details.VerticalAlignment = VerticalAlignment.Center;
        details.Margin = new Thickness(12, 0, 0, 0);
        weatherHost.Child = Ui.HStack(0, new WeatherScene(reading.Kind, reading.IsDay) { Width = 88, Height = 88 }, details);
    }
}

/// Artwork, title, progress and controls for the playing song.
public sealed class NowPlayingView : NotchContentView
{
    private readonly NotchModel model;
    private readonly Grid artworkHost = new() { Width = 120, Height = 120, ClipToBounds = true };
    private readonly ScaleTransform artworkScale = new(1, 1);
    private readonly TextBlock title = Ui.Text("", 16, FontWeights.Bold, Brushes.White);
    private readonly TextBlock artist = Ui.Text("", 15, FontWeights.Medium, Ui.White(0.5));
    private readonly ProgressBar progress;
    private readonly TextBlock playIcon = Ui.Icon(Glyphs.Play, 24, Brushes.White);
    private readonly Border shuffleHost = new() { Width = 28, HorizontalAlignment = HorizontalAlignment.Left };
    private readonly Border repeatHost = new() { Width = 28, HorizontalAlignment = HorizontalAlignment.Right };
    private readonly Border capsule;
    private string trackKey = "";
    private object? shownArtwork;
    private string extrasKey = "";
    private bool? shownPlaying;

    public NowPlayingView(NotchModel model)
    {
        this.model = model;
        var forward = model.PageMovesForward;
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        ColumnDefinitions.Add(new ColumnDefinition());

        var artworkFrame = new Border
        {
            Width = 120,
            Height = 120,
            CornerRadius = new CornerRadius(24),
            Child = artworkHost,
            RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = artworkScale,
            VerticalAlignment = VerticalAlignment.Center,
        };
        artworkHost.Clip = new RectangleGeometry(new Rect(0, 0, 120, 120), 24, 24);
        var artworkButton = Ui.Button(artworkFrame, model.Media.OpenSourceApp);
        artworkButton.SlideIn(0, forward);
        Children.Add(artworkButton);

        var column = new Grid { Height = 138 };
        SetColumn(column, 2);
        column.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        column.RowDefinitions.Add(new RowDefinition());
        column.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        column.RowDefinitions.Add(new RowDefinition());
        column.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var titles = Ui.VStack(3, title, artist);
        titles.SlideIn(1, forward);
        column.Children.Add(titles);

        progress = new ProgressBar(model);
        progress.SlideIn(2, forward);
        SetRow(progress, 2);
        column.Children.Add(progress);

        var controls = new Grid { Height = 42 };
        controls.Children.Add(shuffleHost);
        controls.Children.Add(repeatHost);
        var buttons = Ui.HStack(4,
            ControlButton(Glyphs.Previous, 15, model.Media.Previous),
            ControlButton(playIcon, 24, model.Media.TogglePlayPause),
            ControlButton(Glyphs.Next, 15, model.Media.Next));
        buttons.VerticalAlignment = VerticalAlignment.Center;
        capsule = new Border
        {
            Height = 42,
            Padding = new Thickness(14, 0, 14, 0),
            CornerRadius = new CornerRadius(21),
            HorizontalAlignment = HorizontalAlignment.Center,
            Child = buttons,
        };
        controls.Children.Add(capsule);
        controls.SlideIn(3, forward);
        SetRow(controls, 4);
        column.Children.Add(controls);
        Children.Add(column);
        Refresh();
    }

    private static FrameworkElement ControlButton(string glyph, double size, Action action) =>
        ControlButton(Ui.Icon(glyph, size, Brushes.White), size, action);

    private static FrameworkElement ControlButton(TextBlock icon, double size, Action action)
    {
        var host = new Border { Width = size + 20, Height = 36, Child = icon };
        return Ui.Button(host, action, hoverOpacity: 1, idleOpacity: 0.92);
    }

    public override void Refresh()
    {
        var media = model.Media;
        if (media.Track is not { } track) return;
        var key = track.Title + "\u0001" + track.Artist;
        if (key != trackKey)
        {
            trackKey = key;
            title.Text = track.Title;
            artist.Text = string.IsNullOrEmpty(track.Artist) ? track.Album : track.Artist;
        }
        if (!ReferenceEquals(shownArtwork, media.Artwork) || artworkHost.Children.Count == 0)
        {
            var animated = artworkHost.Children.Count > 0;
            shownArtwork = media.Artwork;
            ShowArtwork(new ArtworkView(media.Artwork, 0) { Width = 120, Height = 120 }, animated, media.SkippedForward);
        }
        playIcon.Text = media.IsPlaying ? Glyphs.Pause : Glyphs.Play;
        if (media.IsPlaying != shownPlaying)
        {
            shownPlaying = media.IsPlaying;
            var scale = media.IsPlaying ? 1 : 0.94;
            artworkScale.Animate(ScaleTransform.ScaleXProperty, scale, SpringEase.Of(0.35, 0.7));
            artworkScale.Animate(ScaleTransform.ScaleYProperty, scale, SpringEase.Of(0.35, 0.7));
        }

        var pill = model.Settings.BackgroundFollowsMusic && model.AccentColor is { } accent
            ? Blend(Color.FromArgb(20, 255, 255, 255), Color.FromArgb(31, accent.R, accent.G, accent.B))
            : Color.FromArgb(20, 255, 255, 255);
        capsule.Background = Ui.Frozen(pill);

        var extras = $"{model.Settings.ShowShuffleRepeat}|{media.Shuffle}|{media.Repeat}|{model.AccentColor}";
        if (extras != extrasKey)
        {
            extrasKey = extras;
            var active = model.AccentColor is { } a ? Ui.Frozen(a) : Brushes.White;
            shuffleHost.Child = model.Settings.ShowShuffleRepeat && media.Shuffle is { } shuffle
                ? ToggleButton(Glyphs.Shuffle, shuffle, active, media.ToggleShuffle) : null;
            repeatHost.Child = model.Settings.ShowShuffleRepeat && media.Repeat is { } repeat
                ? ToggleButton(repeat == RepeatMode.One ? Glyphs.RepeatOne : Glyphs.Repeat, repeat != RepeatMode.Off,
                    active, media.CycleRepeat)
                : null;
        }
        progress.Refresh();
    }

    private static Color Blend(Color under, Color over)
    {
        double a = over.A / 255.0, b = under.A / 255.0;
        var alpha = a + b * (1 - a);
        byte Mix(byte o, byte u) => (byte)((o * a + u * b * (1 - a)) / Math.Max(alpha, 0.001));
        return Color.FromArgb((byte)(alpha * 255), Mix(over.R, under.R), Mix(over.G, under.G), Mix(over.B, under.B));
    }

    /// Small on/off control (shuffle, repeat): coloured when on, dim when off.
    private static FrameworkElement ToggleButton(string glyph, bool isOn, Brush color, Action action)
    {
        var icon = Ui.Icon(glyph, 13, isOn ? color : Ui.White(0.45));
        var host = new Border { Width = 26, Height = 24, Child = icon, VerticalAlignment = VerticalAlignment.Center };
        var button = Ui.Button(host, action);
        button.MouseEnter += (_, _) => { if (!isOn) icon.Foreground = Ui.White(0.8); };
        button.MouseLeave += (_, _) => { if (!isOn) icon.Foreground = Ui.White(0.45); };
        return button;
    }

    /// New songs slide in from the side they were skipped towards.
    private void ShowArtwork(FrameworkElement view, bool animated, bool forward)
    {
        var old = artworkHost.Children.OfType<FrameworkElement>().LastOrDefault();
        artworkHost.Children.Add(view);
        if (!animated || old == null)
        {
            if (old != null) artworkHost.Children.Remove(old);
            return;
        }
        var spring = SpringEase.Of(0.5, 0.78);
        var direction = forward ? 1 : -1;
        var enter = new TranslateTransform(120 * direction, 0);
        view.RenderTransform = enter;
        enter.Animate(TranslateTransform.XProperty, 0, spring);
        var leave = new TranslateTransform();
        old.RenderTransform = leave;
        leave.Animate(TranslateTransform.XProperty, -120 * direction, spring);
        old.FadeTo(0, 0.35, () => artworkHost.Children.Remove(old));
    }
}
