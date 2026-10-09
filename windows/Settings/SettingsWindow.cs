using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using Lenotch.AI;
using Lenotch.Core;
using Lenotch.Notch;
using Lenotch.Services;

namespace Lenotch.Settings;

public enum SettingsSection { General, Look, Music, Calendar, Weather, Shelf, Timer, AIUsage, MicCamera, Network, Crypto, About }

/// Lenotch's settings: a sidebar of sections, each a page of grouped rows.
public sealed class SettingsWindow : Window
{
    private readonly AppServices services;
    private readonly Action playIntro;
    private readonly ListBox sidebar = new();
    private readonly ScrollViewer scroller = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(28, 22, 28, 28) };
    private SettingsSection section = SettingsSection.General;
    private Guid? editingProvider;
    private CustomProvider? draft;
    private string? draftKey;
    private string testResult = "";
    private bool editingDeepSeek;

    private AppSettings Settings => services.Settings;

    private static Brush TextBrush => (Brush)Application.Current.Resources["TextBrush"];
    private static Brush SecondaryBrush => (Brush)Application.Current.Resources["SecondaryTextBrush"];

    public SettingsWindow(AppServices services, Action playIntro)
    {
        this.services = services;
        this.playIntro = playIntro;
        Title = "Lenotch Settings";
        Width = 860;
        Height = 640;
        MinWidth = 720;
        MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = (Brush)Application.Current.Resources["WindowBrush"];
        Foreground = TextBrush;
        FontFamily = Ui.TextFont;
        FontSize = 13;
        UseLayoutRounding = true;
        var iconStream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/Lenotch.ico"))?.Stream;
        if (iconStream != null) Icon = System.Windows.Media.Imaging.BitmapFrame.Create(iconStream);

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(220) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var side = new DockPanel { Background = (Brush)Application.Current.Resources["SidebarBrush"] };
        var brand = Ui.HStack(10, Ui.LogoView(24), Ui.Text("Lenotch", 17, FontWeights.Bold, TextBrush));
        brand.Margin = new Thickness(18, 18, 18, 14);
        DockPanel.SetDock(brand, Dock.Top);
        side.Children.Add(brand);
        sidebar.Background = Brushes.Transparent;
        sidebar.BorderThickness = new Thickness(0);
        sidebar.Padding = new Thickness(10, 0, 10, 10);
        sidebar.ItemContainerStyle = (Style)Application.Current.Resources["SidebarItem"];
        ScrollViewer.SetHorizontalScrollBarVisibility(sidebar, ScrollBarVisibility.Disabled);
        BuildSidebar();
        side.Children.Add(sidebar);
        grid.Children.Add(side);
        Grid.SetColumn(scroller, 1);
        grid.Children.Add(scroller);
        Content = grid;

        SourceInitialized += (_, _) => UseDarkTitleBar();
        services.Updates.Changed += () => { if (section == SettingsSection.About) ShowPage(); };
        Settings.Changed += name =>
        {
            if (name == nameof(AppSettings.ConfigProviders) && section == SettingsSection.AIUsage) ShowPage();
        };
        ShowPage();
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    private void UseDarkTitleBar()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var on = 1;
        DwmSetWindowAttribute(hwnd, 20, ref on, sizeof(int));
    }

    // MARK: - Sidebar

    private static (string group, (SettingsSection section, string title, string glyph, Color color)[] items)[] Groups =>
        new[]
        {
            ("Notch", new[]
            {
                (SettingsSection.General, "General", Glyphs.Settings, Color.FromRgb(142, 142, 147)),
                (SettingsSection.Look, "Look", Glyphs.Paint, Color.FromRgb(94, 92, 230)),
            }),
            ("Features", new[]
            {
                (SettingsSection.Music, "Music", Glyphs.Music, Color.FromRgb(255, 55, 95)),
                (SettingsSection.Calendar, "Calendar", Glyphs.Calendar, Color.FromRgb(255, 59, 48)),
                (SettingsSection.Weather, "Weather", Glyphs.Weather, Color.FromRgb(50, 173, 230)),
                (SettingsSection.Shelf, "Shelf", Glyphs.Shelf, Color.FromRgb(10, 132, 255)),
                (SettingsSection.Timer, "Timer", Glyphs.Timer, Color.FromRgb(255, 149, 0)),
                (SettingsSection.AIUsage, "AI Usage", Glyphs.Robot, Color.FromRgb(175, 82, 222)),
            }),
            ("Beside the Notch", new[]
            {
                (SettingsSection.MicCamera, "Mic & Camera", Glyphs.Mic, Color.FromRgb(255, 149, 0)),
                (SettingsSection.Network, "Network", Glyphs.Network, Color.FromRgb(0, 199, 190)),
                (SettingsSection.Crypto, "Crypto", Glyphs.Coin, Color.FromRgb(255, 204, 0)),
            }),
            ("Lenotch", new[]
            {
                (SettingsSection.About, "About & Updates", Glyphs.Info, Color.FromRgb(142, 142, 147)),
            }),
        };

    private void BuildSidebar()
    {
        foreach (var (group, items) in Groups)
        {
            var header = new ListBoxItem
            {
                Content = Ui.Text(group, 11, FontWeights.SemiBold, SecondaryBrush),
                IsEnabled = false,
                Margin = new Thickness(8, sidebar.Items.Count > 0 ? 12 : 0, 0, 2),
                Template = null,
            };
            header.Template = new ControlTemplate(typeof(ListBoxItem)) { VisualTree = new FrameworkElementFactory(typeof(ContentPresenter)) };
            sidebar.Items.Add(header);
            foreach (var (item, title, glyph, color) in items)
            {
                var badge = new Border
                {
                    Width = 22,
                    Height = 22,
                    CornerRadius = new CornerRadius(5),
                    Background = Ui.Frozen(color),
                    Child = Ui.Icon(glyph, 12, Brushes.White),
                };
                var label = Ui.HStack(10, badge, Ui.Text(title, 13, FontWeights.Normal, TextBrush));
                ((TextBlock)label.Children[1]).VerticalAlignment = VerticalAlignment.Center;
                var entry = new ListBoxItem { Content = label, Tag = item };
                sidebar.Items.Add(entry);
                if (item == section) sidebar.SelectedItem = entry;
            }
        }
        sidebar.SelectionChanged += (_, _) =>
        {
            if (sidebar.SelectedItem is ListBoxItem { Tag: SettingsSection chosen } && chosen != section)
            {
                section = chosen;
                editingProvider = null;
                draft = null;
                ShowPage();
                scroller.ScrollToTop();
            }
        };
    }

    public void Show(SettingsSection target)
    {
        section = target;
        foreach (var item in sidebar.Items.OfType<ListBoxItem>())
            if (item.Tag is SettingsSection s && s == target) sidebar.SelectedItem = item;
        ShowPage();
    }

    // MARK: - Pages

    private void ShowPage()
    {
        var offset = scroller.VerticalOffset;
        var page = new StackPanel { MaxWidth = 640, HorizontalAlignment = HorizontalAlignment.Stretch };
        var title = Groups.SelectMany(g => g.items).First(i => i.section == section).title;
        page.Children.Add(Ui.Text(title, 22, FontWeights.Bold, TextBrush));
        foreach (var element in section switch
                 {
                     SettingsSection.General => General(),
                     SettingsSection.Look => Look(),
                     SettingsSection.Music => Music(),
                     SettingsSection.Calendar => CalendarPage(),
                     SettingsSection.Weather => WeatherPage(),
                     SettingsSection.Shelf => ShelfPage(),
                     SettingsSection.Timer => TimerPage(),
                     SettingsSection.AIUsage => AIUsagePage(),
                     SettingsSection.MicCamera => MicCameraPage(),
                     SettingsSection.Network => NetworkPage(),
                     SettingsSection.Crypto => CryptoPage(),
                     _ => AboutPage(),
                 })
            page.Children.Add(element);
        scroller.Content = page;
        scroller.UpdateLayout();
        scroller.ScrollToVerticalOffset(offset);
    }

    private IEnumerable<UIElement> General()
    {
        yield return Group("Displays",
            Toggle("Show the notch on every screen", null, () => Settings.ShowOnAllScreens, v => Settings.ShowOnAllScreens = v),
            Toggle("Hide while an app is full screen", "Games and videos keep the whole screen.",
                () => Settings.HideInFullscreen, v => Settings.HideInFullscreen = v));
        yield return Group("Opening",
            Choice("Open the notch on", new[] { (OpenMode.Hover, "Hover"), (OpenMode.Click, "Click") },
                () => Settings.OpenMode, v => Settings.OpenMode = v),
            SliderRow("Hover delay", 0, 1, 0.05, () => Settings.HoverDelay, v => Settings.HoverDelay = v, v => $"{v:0.00} s"),
            Row("Open or close the notch", null, ShortcutRecorder(() => Settings.ToggleShortcut, v => Settings.ToggleShortcut = v)),
            Row("Show the current song", null, ShortcutRecorder(() => Settings.PeekShortcut, v => Settings.PeekShortcut = v)));
        yield return Group("Tray",
            Toggle("Show the icon in the notification area", "When hidden, open Settings from the notch's gear or by starting Lenotch again.",
                () => Settings.ShowTrayIcon, v => Settings.ShowTrayIcon = v));
        yield return Group("Startup & updates",
            Toggle("Start with Windows", "Lenotch starts when you sign in.", () => LaunchAtLogin.IsEnabled, v => LaunchAtLogin.IsEnabled = v),
            Toggle("Check for updates automatically", null, () => Settings.CheckForUpdates, v => Settings.CheckForUpdates = v));
        yield return Group("Help",
            ButtonRow("Replay the intro", null, "Play", playIntro));
    }

    private IEnumerable<UIElement> Look()
    {
        yield return Note("On Windows the notch is solid black, like the hardware notch.");
        // Off removes the whole battery (icon and percentage) from the notch header.
        var percentage = Toggle("Show battery percentage", null, () => Settings.ShowBatteryPercentage, v => Settings.ShowBatteryPercentage = v);
        percentage.IsEnabled = Settings.ShowBatteryIndicator;
        percentage.Opacity = Settings.ShowBatteryIndicator ? 1 : 0.45;
        yield return Group("Notch header",
            Toggle("Show battery indicator", "Only on PCs with a battery.", () => Settings.ShowBatteryIndicator, v =>
            {
                Settings.ShowBatteryIndicator = v;
                ShowPage();
            }),
            percentage);
        yield return Group("Follow the album colour",
            Toggle("Notch background", "A soft glow of the cover's colour in the open notch.", () => Settings.BackgroundFollowsMusic, v => Settings.BackgroundFollowsMusic = v),
            Toggle("Equalizer bars", null, () => Settings.TintEqualizer, v => Settings.TintEqualizer = v),
            Toggle("Progress bar", null, () => Settings.TintProgressBar, v => Settings.TintProgressBar = v));
    }

    private IEnumerable<UIElement> Music()
    {
        yield return Group(null,
            Toggle("Show the music player", "Off leaves the calendar (or the time and weather) in the first tab.",
                () => Settings.ShowMusic, v => Settings.ShowMusic = v));
        yield return Group("Source",
            Choice("Follow", Enum.GetValues<AudioSource>().Select(s => (s, s.Title())).ToArray(),
                () => Settings.AudioSource, v => Settings.AudioSource = v));
        yield return Group("Closed notch",
            Toggle("Music in the closed notch", "Shows the cover and equalizer beside the notch while music plays.",
                () => Settings.ShowLiveActivity, v => Settings.ShowLiveActivity = v));
        yield return Group("Song changes",
            Toggle("Peek when the song changes", "Shows the new song under the notch for a moment.",
                () => Settings.PeekOnTrackChange, v => Settings.PeekOnTrackChange = v),
            SliderRow("Peek duration", 1, 8, 0.5, () => Settings.TrackPeekDuration, v => Settings.TrackPeekDuration = v, v => $"{v:0.#} s"));
        yield return Group("Player",
            Toggle("Shuffle and repeat buttons", "When the playing app supports them.", () => Settings.ShowShuffleRepeat, v => Settings.ShowShuffleRepeat = v),
            Toggle("Real audio visualizer", "The bars follow what you hear (no permission needed).",
                () => Settings.RealAudioVisualizer, v => Settings.RealAudioVisualizer = v));
    }

    private static readonly string[] FeedColors = { "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#0A84FF", "#5E5CE6", "#AF52DE", "#FF2D55" };

    private IEnumerable<UIElement> CalendarPage()
    {
        yield return Group(null,
            Toggle("Show the calendar", "Beside the music, or on its own when the music is off.", () => Settings.ShowCalendar, v => Settings.ShowCalendar = v),
            Choice("On its own, show", new[] { (ExpandedCalendarStyle.Month, "Month view"), (ExpandedCalendarStyle.Strip, "Day strip") },
                () => Settings.ExpandedCalendarStyle, v => Settings.ExpandedCalendarStyle = v),
            Toggle("Scroll to the next event", null, () => Settings.AutoScrollCalendar, v => Settings.AutoScrollCalendar = v),
            Toggle("Show full event titles", null, () => Settings.ShowFullEventTitles, v => Settings.ShowFullEventTitles = v));

        yield return Note("Windows doesn't share its calendars with other apps, so add your calendars' iCal links. "
                          + "Outlook: Settings → Calendar → Shared calendars → Publish. Google: calendar settings → "
                          + "Secret address in iCal format. iCloud: share the calendar as a public calendar.");
        var rows = new List<UIElement>();
        foreach (var feed in Settings.CalendarFeeds.ToList()) rows.Add(FeedRow(feed));
        rows.Add(ButtonRow("Add a calendar", null, "Add", () =>
        {
            var feeds = Settings.CalendarFeeds.ToList();
            feeds.Add(new CalendarFeed { Name = "Calendar", Color = FeedColors[feeds.Count % FeedColors.Length] });
            Settings.CalendarFeeds = feeds;
            ShowPage();
        }));
        yield return Group("Calendars", rows.ToArray());
    }

    private UIElement FeedRow(CalendarFeed feed)
    {
        var swatch = new Border
        {
            Width = 18,
            Height = 18,
            CornerRadius = new CornerRadius(9),
            Background = Ui.Frozen(Ui.ParseColor(feed.Color, Colors.Red)),
            Cursor = Cursors.Hand,
            VerticalAlignment = VerticalAlignment.Center,
            ToolTip = "Change colour",
        };
        swatch.MouseLeftButtonUp += (_, _) =>
        {
            var index = Array.IndexOf(FeedColors, feed.Color);
            feed.Color = FeedColors[(index + 1) % FeedColors.Length];
            swatch.Background = Ui.Frozen(Ui.ParseColor(feed.Color, Colors.Red));
            Settings.Touch(nameof(AppSettings.CalendarFeeds));
        };
        var name = TextField(feed.Name, text => { feed.Name = text; Settings.Touch(nameof(AppSettings.CalendarFeeds)); });
        name.Width = 140;
        var url = TextField(feed.Url, text => { feed.Url = text.Trim(); Settings.Touch(nameof(AppSettings.CalendarFeeds)); });
        url.Margin = new Thickness(8, 0, 8, 0);
        var enabled = Switch(feed.Enabled, v => { feed.Enabled = v; Settings.Touch(nameof(AppSettings.CalendarFeeds)); });
        var remove = SmallButton("Remove", () =>
        {
            Settings.CalendarFeeds = Settings.CalendarFeeds.Where(f => f.Id != feed.Id).ToList();
            ShowPage();
        });
        remove.Margin = new Thickness(8, 0, 0, 0);
        var row = new DockPanel { Margin = new Thickness(14, 10, 14, 10) };
        DockPanel.SetDock(swatch, Dock.Left);
        DockPanel.SetDock(name, Dock.Left);
        DockPanel.SetDock(remove, Dock.Right);
        DockPanel.SetDock(enabled, Dock.Right);
        swatch.Margin = new Thickness(0, 0, 10, 0);
        row.Children.Add(swatch);
        row.Children.Add(name);
        row.Children.Add(remove);
        row.Children.Add(enabled);
        row.Children.Add(url);
        return row;
    }

    private IEnumerable<UIElement> WeatherPage()
    {
        yield return Note("The weather shows in the first tab when both the music and the calendar are off.");
        var current = Settings.WeatherPlace?.Name ?? "Approximate location (from your internet connection)";
        var results = new StackPanel();
        var search = TextField("", _ => { });
        search.Width = 260;
        async void RunSearch()
        {
            results.Children.Clear();
            var found = await WeatherService.Search(search.Text);
            if (found.Count == 0) results.Children.Add(Row("No places found", null, new Border()));
            foreach (var result in found)
            {
                var place = result.Place;
                results.Children.Add(ButtonRow(place.Name, result.Detail, "Use", () =>
                {
                    Settings.WeatherPlace = place;
                    ShowPage();
                }));
            }
        }
        search.KeyDown += (_, e) => { if (e.Key == Key.Enter) RunSearch(); };
        var searchButton = SmallButton("Search", RunSearch);
        searchButton.Margin = new Thickness(8, 0, 0, 0);
        yield return Group("Place",
            Row("Showing", current, Settings.WeatherPlace != null
                ? SmallButton("Use approximate location", () => { Settings.WeatherPlace = null; ShowPage(); })
                : new Border()),
            Row("Find a city", null, Ui.HStack(0, search, searchButton)),
            results);
        yield return Group("Units",
            Toggle("Fahrenheit", null, () => Settings.WeatherFahrenheit, v => Settings.WeatherFahrenheit = v));
    }

    private IEnumerable<UIElement> ShelfPage()
    {
        yield return Group(null,
            Toggle("Show the shelf tab", null, () => Settings.ShowShelfTab, v => Settings.ShowShelfTab = v),
            Toggle("File shelf", "Drop files on the notch to keep them at hand, and drag them back out.",
                () => Settings.ShowFileShelf, v => Settings.ShowFileShelf = v),
            Toggle("Share", "Send files with Nearby Sharing, Mail and other apps.", () => Settings.ShowShare, v => Settings.ShowShare = v));
        yield return Group("Files",
            Toggle("Keep files after restarting", "The shelf only holds links to the files, never copies.",
                () => Settings.KeepShelfItems, v => Settings.KeepShelfItems = v),
            Toggle("Open the shelf when dragging files onto the notch", null, () => Settings.OpenShelfOnDrag, v => Settings.OpenShelfOnDrag = v),
            ButtonRow("Clear the shelf", $"{services.Shelf.Items.Count} file(s)", "Clear", () => { services.Shelf.RemoveAll(); ShowPage(); }));
    }

    private IEnumerable<UIElement> TimerPage()
    {
        yield return Group(null,
            Toggle("Timer button in the notch", "A running timer shows beside the closed notch.", () => Settings.ShowTimer, v => Settings.ShowTimer = v),
            Toggle("Silent timers", "The notch still folds down when the time is up.", () => Settings.TimerSilent, v => Settings.TimerSilent = v));
    }

    private IEnumerable<UIElement> MicCameraPage()
    {
        yield return Group(null,
            Toggle("Outline the notch while the mic or camera is on", "Orange for the microphone, green for the camera.",
                () => Settings.ShowPrivacyIndicator, v => Settings.ShowPrivacyIndicator = v),
            Toggle("Glow outside the notch", null, () => Settings.PrivacyGlow, v => Settings.PrivacyGlow = v));
    }

    private IEnumerable<UIElement> NetworkPage()
    {
        yield return Group(null,
            Toggle("Show download and upload speed", "Beside the closed notch while a big transfer runs.",
                () => Settings.ShowNetworkSpeed, v => Settings.ShowNetworkSpeed = v));
    }

    private IEnumerable<UIElement> CryptoPage()
    {
        yield return Group(null,
            Toggle("Crypto prices beside the notch", "While nothing else shows there. Prices from CoinGecko.",
                () => Settings.ShowCrypto, v => Settings.ShowCrypto = v),
            Choice("Currency", CryptoService.Currencies.Select(c => (c, c.ToUpperInvariant())).ToArray(),
                () => Settings.CryptoCurrency, v => Settings.CryptoCurrency = v));
        var coins = Coin.All.Select(coin => (UIElement)Toggle($"{coin.Name} ({coin.Symbol})", null,
            () => Settings.CryptoCoins.Contains(coin.Id),
            v =>
            {
                var chosen = Coin.All.Select(c => c.Id).Where(id => id == coin.Id ? v : Settings.CryptoCoins.Contains(id)).ToList();
                Settings.CryptoCoins = chosen;
            })).ToArray();
        yield return Group("Coins", coins);
    }

    private IEnumerable<UIElement> AboutPage()
    {
        var updates = services.Updates;
        var brand = Ui.HStack(14, Ui.LogoView(48), Ui.VStack(2,
            Ui.Text("Lenotch for Windows", 18, FontWeights.Bold, TextBrush),
            Ui.Text($"Version {UpdateService.CurrentVersionText}", 13, FontWeights.Normal, SecondaryBrush)));
        brand.Margin = new Thickness(0, 16, 0, 0);
        yield return brand;
        var status = updates.IsInstalling ? "Installing…"
            : updates.AvailableVersion is { } version ? $"Lenotch {version} is available." : "Downloads come from GitHub Releases.";
        yield return Group("Updates",
            updates.AvailableVersion != null
                ? ButtonRow("Update available", status, "Install and restart", async () => await updates.Install())
                : ButtonRow("Check for updates", status, "Check now", async () =>
                {
                    if (!await updates.Check()) MessageBox.Show(this, $"Lenotch {UpdateService.CurrentVersionText} is the latest version.", "Lenotch");
                }));
        yield return Group("More",
            ButtonRow("Lenotch on GitHub", "github.com/lephorx/lenotch", "Open", () => OpenUrl("https://github.com/lephorx/lenotch")),
            ButtonRow("Settings folder", AppSettings.Folder, "Show", () => OpenUrl(AppSettings.Folder)),
            ButtonRow("Replay the intro", null, "Play", playIntro));
    }

    // MARK: - AI usage

    private IEnumerable<UIElement> AIUsagePage()
    {
        yield return Group(null,
            Toggle("Show the AI Usage tab", "Usage limits of your coding assistants, read with the sign-in each tool already keeps on this PC.",
                () => Settings.AIUsageEnabled, v => { Settings.AIUsageEnabled = v; ShowPage(); }));
        if (!Settings.AIUsageEnabled) yield break;

        var keys = Settings.UsageSourceKeys;
        var builtIn = AIProviders.All.OrderBy(p => keys.IndexOf(p.Key()) is var i && i >= 0 ? i : 100 + (int)p).ToList();
        var rows = new List<UIElement>();
        foreach (var provider in builtIn)
        {
            var detail = provider != AIProvider.DeepSeek ? provider.Source()
                : DeepSeekUsage.IsSignedIn ? "Signed in" : DeepSeekUsage.HasSavedKey ? "API key saved" : provider.Source();
            rows.Add(SourceRow(new UsageSource(provider), detail, null));
            if (provider == AIProvider.DeepSeek && editingDeepSeek) rows.Add(DeepSeekKeyEditor());
        }
        yield return Group("Providers", rows.ToArray());

        var customs = Settings.AllCustomProviders.ToList();
        var customRows = new List<UIElement>();
        foreach (var custom in customs)
        {
            var source = new UsageSource(custom);
            customRows.Add(SourceRow(source, custom.ConfigFile != null ? $"Config file: {custom.ConfigFile}" : custom.Url, custom));
            if (editingProvider == custom.Id && draft != null) customRows.Add(ProviderEditor(draft, custom.ConfigFile != null));
        }
        if (editingProvider != null && draft != null && customs.All(c => c.Id != editingProvider))
            customRows.Add(ProviderEditor(draft, false));
        customRows.Add(ButtonRow("Add a custom provider", "Any HTTP endpoint that returns JSON.", "Add", () =>
        {
            draft = new CustomProvider();
            draftKey = "";
            editingProvider = draft.Id;
            testResult = "";
            ShowPage();
        }));
        customRows.Add(ButtonRow("Import a provider config", "A .json file (see docs/provider-config.md).", "Import…", () =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "Provider config (*.json)|*.json" };
            if (dialog.ShowDialog(this) != true) return;
            try
            {
                ProviderConfigStore.Import(dialog.FileName);
                Settings.ReloadProviderConfigs();
            }
            catch (Exception error)
            {
                MessageBox.Show(this, $"That file isn't a valid provider config.\n{error.Message}", "Lenotch");
            }
        }));
        customRows.Add(ButtonRow("Providers folder", ProviderConfigStore.ProvidersFolder, "Show", () =>
        {
            ProviderConfigStore.EnsureFolders();
            OpenUrl(ProviderConfigStore.ProvidersFolder);
        }));
        customRows.Add(ButtonRow("Reload config files", null, "Reload", Settings.ReloadProviderConfigs));
        yield return Group("Custom providers", customRows.ToArray());
    }

    private UIElement SourceRow(UsageSource source, string detail, CustomProvider? custom)
    {
        var key = source.Id;
        var keys = Settings.UsageSourceKeys;
        var enabled = keys.Contains(key);
        var controls = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (enabled)
        {
            controls.Children.Add(IconButton(Glyphs.ArrowUp, () => Move(key, -1)));
            controls.Children.Add(IconButton(Glyphs.ArrowDown, () => Move(key, 1)));
        }
        if (source.BuiltIn == AIProvider.DeepSeek)
        {
            controls.Children.Add(SmallButton("Set up…", () =>
            {
                editingDeepSeek = !editingDeepSeek;
                testResult = "";
                ShowPage();
            }, new Thickness(6, 0, 0, 0)));
        }
        if (custom != null)
        {
            if (custom.ConfigFile == null)
            {
                controls.Children.Add(SmallButton("Edit", () =>
                {
                    draft = custom.Copy();
                    draftKey = "";
                    editingProvider = custom.Id;
                    testResult = "";
                    ShowPage();
                }, new Thickness(6, 0, 0, 0)));
                controls.Children.Add(SmallButton("Delete", () =>
                {
                    custom.SaveApiKey("");
                    Settings.CustomProviders = Settings.CustomProviders.Where(c => c.Id != custom.Id).ToList();
                    Settings.UsageSourceKeys = Settings.UsageSourceKeys.Where(k => k != key).ToList();
                    editingProvider = null;
                    ShowPage();
                }, new Thickness(6, 0, 0, 0)));
            }
            else
            {
                controls.Children.Add(SmallButton("Edit file", () =>
                    OpenUrl(Path.Combine(ProviderConfigStore.ProvidersFolder, custom.ConfigFile)), new Thickness(6, 0, 0, 0)));
            }
        }
        var toggle = Switch(enabled, v =>
        {
            var list = Settings.UsageSourceKeys.Where(k => k != key).ToList();
            if (v) list.Add(key);
            Settings.UsageSourceKeys = list;
            ShowPage();
        });
        toggle.Margin = new Thickness(12, 0, 0, 0);
        controls.Children.Add(toggle);

        var glyph = source.GlyphView(18, TextBrush);
        glyph.Margin = new Thickness(0, 0, 12, 0);
        glyph.VerticalAlignment = VerticalAlignment.Center;
        var text = TitleBlock(source.Title, detail);
        var row = new DockPanel { Margin = new Thickness(14, 10, 14, 10) };
        DockPanel.SetDock(glyph, Dock.Left);
        DockPanel.SetDock(controls, Dock.Right);
        row.Children.Add(glyph);
        row.Children.Add(controls);
        row.Children.Add(text);
        return row;
    }

    private void Move(string key, int offset)
    {
        var list = Settings.UsageSourceKeys.ToList();
        var index = list.IndexOf(key);
        var target = index + offset;
        if (index < 0 || target < 0 || target >= list.Count) return;
        (list[index], list[target]) = (list[target], list[index]);
        Settings.UsageSourceKeys = list;
        ShowPage();
    }

    /// DeepSeek: sign in to the account (balance, spend and the last 30 days), or an
    /// API key (balance only). Both are encrypted for this Windows user.
    private UIElement DeepSeekKeyEditor()
    {
        var form = new StackPanel { Margin = new Thickness(14, 4, 14, 14) };
        var signedIn = DeepSeekUsage.IsSignedIn;
        var accountHint = Ui.Text("Sign in to the DeepSeek Platform to see your balance, total spend, and the last 30 days of tokens, requests and cost.",
            12, FontWeights.Normal, SecondaryBrush);
        accountHint.TextWrapping = TextWrapping.Wrap;
        form.Children.Add(accountHint);
        form.Children.Add(Row("Account", signedIn ? "Signed in." : null, SmallButton(signedIn ? "Sign out" : "Sign in…", () =>
        {
            if (signedIn)
            {
                DeepSeekUsage.SaveSessionToken("");
            }
            else
            {
                var window = new DeepSeekSignIn { Owner = this };
                window.ShowDialog();
                if (!window.SignedIn) return;
                if (!Settings.UsageSourceKeys.Contains(AIProvider.DeepSeek.Key()))
                    Settings.UsageSourceKeys = Settings.UsageSourceKeys.Append(AIProvider.DeepSeek.Key()).ToList();
            }
            testResult = "";
            _ = services.AIUsage.Refresh(Settings.UsageSources, force: true);
            ShowPage();
        })));
        var hint = Ui.Text(signedIn ? "An API key isn't needed while you're signed in."
                : "Or create a key at platform.deepseek.com → API keys. With a key Lenotch can only read your balance.",
            12, FontWeights.Normal, SecondaryBrush);
        hint.TextWrapping = TextWrapping.Wrap;
        hint.Margin = new Thickness(0, 10, 0, 0);
        form.Children.Add(hint);
        var key = new PasswordBox { Style = (Style)Application.Current.Resources["LenotchPasswordBox"], MinWidth = 260 };
        form.Children.Add(Row("API key", DeepSeekUsage.HasSavedKey ? "Saved. Type to replace." : null, key, stretchControl: true));
        var result = Ui.Text(testResult, 12, FontWeights.Normal, SecondaryBrush);
        result.TextWrapping = TextWrapping.Wrap;
        form.Children.Add(result);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 10, 0, 0) };
        if (DeepSeekUsage.HasSavedKey)
            buttons.Children.Add(SmallButton("Remove key", () =>
            {
                DeepSeekUsage.SaveApiKey("");
                editingDeepSeek = false;
                ShowPage();
            }));
        buttons.Children.Add(SmallButton("Test", async () =>
        {
            if (key.Password.Length > 0) DeepSeekUsage.SaveApiKey(key.Password);
            result.Text = "Testing…";
            try
            {
                var usage = await DeepSeekUsage.Fetch();
                testResult = usage is ProviderUsage.Ok ok && ok.Windows.FirstOrDefault()?.Amount is { } balance
                    ? $"Works: balance {balance}." : "No reading.";
            }
            catch (Exception error)
            {
                testResult = error.Message is { Length: > 0 } message ? message : "Sign in or enter a key first.";
            }
            result.Text = testResult;
        }, new Thickness(8, 0, 0, 0)));
        buttons.Children.Add(SmallButton("Cancel", () => { editingDeepSeek = false; ShowPage(); }, new Thickness(8, 0, 0, 0)));
        var save = SmallButton("Save", () =>
        {
            if (key.Password.Length > 0) DeepSeekUsage.SaveApiKey(key.Password);
            if (!Settings.UsageSourceKeys.Contains(AIProvider.DeepSeek.Key()))
                Settings.UsageSourceKeys = Settings.UsageSourceKeys.Append(AIProvider.DeepSeek.Key()).ToList();
            editingDeepSeek = false;
            _ = services.AIUsage.Refresh(Settings.UsageSources, force: true);
            ShowPage();
        }, new Thickness(8, 0, 0, 0));
        save.Style = (Style)Application.Current.Resources["AccentButton"];
        buttons.Children.Add(save);
        form.Children.Add(buttons);
        return new Border { Background = Ui.Frozen(Color.FromRgb(0x23, 0x23, 0x26)), Child = form };
    }

    private UIElement ProviderEditor(CustomProvider provider, bool readOnly)
    {
        var form = new StackPanel { Margin = new Thickness(14, 4, 14, 14) };
        UIElement Field(string label, string value, Action<string> changed, string? hint = null)
        {
            var box = TextField(value, changed);
            box.IsEnabled = !readOnly;
            return Row(label, hint, box, stretchControl: true);
        }
        form.Children.Add(Field("Name", provider.Name, v => provider.Name = v));
        form.Children.Add(Field("URL", provider.Url, v => provider.Url = v.Trim()));
        form.Children.Add(Field("Auth header", provider.AuthHeader, v => provider.AuthHeader = v));
        form.Children.Add(Field("Auth prefix", provider.AuthPrefix, v => provider.AuthPrefix = v));
        var key = new PasswordBox { Style = (Style)Application.Current.Resources["LenotchPasswordBox"], MinWidth = 260 };
        key.PasswordChanged += (_, _) => draftKey = key.Password;
        form.Children.Add(Row("API key", provider.ApiKey != null ? "Saved (encrypted for your Windows account). Type to replace." : "Encrypted for your Windows account.", key, stretchControl: true));
        form.Children.Add(Field("…or read the key from a file", provider.ApiKeyFile ?? "", v => provider.ApiKeyFile = v.Length > 0 ? v : null));
        form.Children.Add(Choice("Response holds", new[]
        {
            (CustomMode.Percent, "Used % (0–100)"),
            (CustomMode.UsedAndLimit, "Used and limit"),
            (CustomMode.RemainingAndLimit, "Remaining and limit"),
        }, () => provider.Mode, v => provider.Mode = v));
        form.Children.Add(Field("Value path", provider.ValuePath, v => provider.ValuePath = v, "Dot path, e.g. data.usage.percent"));
        form.Children.Add(Field("Limit path", provider.LimitPath, v => provider.LimitPath = v));
        form.Children.Add(Field("Reset path", provider.ResetPath, v => provider.ResetPath = v, "Optional: ISO date or Unix seconds"));
        form.Children.Add(Field("Label", provider.Label, v => provider.Label = v));
        form.Children.Add(ButtonRow("Logo", provider.LogoPath ?? "PNG or JPG, tinted white", "Choose…", () =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog { Filter = "Images (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg" };
            if (dialog.ShowDialog(this) != true) return;
            try { provider.LogoPath = ProviderConfigStore.StoreLogo(dialog.FileName); } catch (Exception) { }
            ShowPage();
        }));
        form.Children.Add(Toggle("Tint the logo white", null, () => provider.TintLogo ?? true, v => provider.TintLogo = v));

        var result = Ui.Text(testResult, 12, FontWeights.Normal, SecondaryBrush);
        result.TextWrapping = TextWrapping.Wrap;
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 10, 0, 0) };
        buttons.Children.Add(SmallButton("Test", async () =>
        {
            if (!string.IsNullOrEmpty(draftKey)) provider.SaveApiKey(draftKey);
            result.Text = "Testing…";
            var usage = await AIUsageService.Test(provider);
            testResult = usage switch
            {
                ProviderUsage.Ok ok when ok.Windows.Count > 0 => $"Works: {Math.Round(ok.Windows[0].Used * 100)}% used.",
                ProviderUsage.Problem problem => problem.Message,
                _ => "No reading.",
            };
            result.Text = testResult;
        }));
        buttons.Children.Add(SmallButton("Export…", () =>
        {
            var dialog = new Microsoft.Win32.SaveFileDialog { Filter = "Provider config (*.json)|*.json", FileName = $"{provider.Name}.json" };
            if (dialog.ShowDialog(this) == true) ProviderConfigStore.Export(provider, dialog.FileName);
        }, new Thickness(8, 0, 0, 0)));
        buttons.Children.Add(SmallButton("Cancel", () => { editingProvider = null; draft = null; ShowPage(); }, new Thickness(8, 0, 0, 0)));
        if (!readOnly)
        {
            var save = SmallButton("Save", () =>
            {
                if (!string.IsNullOrEmpty(draftKey)) provider.SaveApiKey(draftKey);
                var list = Settings.CustomProviders.Where(c => c.Id != provider.Id).ToList();
                var index = Settings.CustomProviders.FindIndex(c => c.Id == provider.Id);
                list.Insert(index >= 0 ? index : list.Count, provider);
                Settings.CustomProviders = list;
                if (!Settings.UsageSourceKeys.Contains(provider.Key))
                    Settings.UsageSourceKeys = Settings.UsageSourceKeys.Append(provider.Key).ToList();
                editingProvider = null;
                draft = null;
                ShowPage();
            }, new Thickness(8, 0, 0, 0));
            save.Style = (Style)Application.Current.Resources["AccentButton"];
            buttons.Children.Add(save);
        }
        form.Children.Add(result);
        form.Children.Add(buttons);
        return new Border { Background = Ui.Frozen(Color.FromRgb(0x23, 0x23, 0x26)), Child = form };
    }

    // MARK: - Building blocks

    private static UIElement Note(string text)
    {
        var block = Ui.Text(text, 12, FontWeights.Normal, SecondaryBrush);
        block.TextWrapping = TextWrapping.Wrap;
        block.TextTrimming = TextTrimming.None;
        block.Margin = new Thickness(2, 14, 2, 0);
        return block;
    }

    /// A titled card of rows with hairlines between them.
    private static UIElement Group(string? title, params UIElement[] rows)
    {
        var stack = new StackPanel { Margin = new Thickness(0, 18, 0, 0) };
        if (title != null)
        {
            var header = Ui.Text(title, 13, FontWeights.SemiBold, SecondaryBrush);
            header.Margin = new Thickness(4, 0, 0, 8);
            stack.Children.Add(header);
        }
        var inner = new StackPanel();
        for (var i = 0; i < rows.Length; i++)
        {
            if (i > 0) inner.Children.Add(new Border { Height = 1, Background = (Brush)Application.Current.Resources["CardBorderBrush"], Margin = new Thickness(14, 0, 0, 0) });
            inner.Children.Add(rows[i]);
        }
        stack.Children.Add(new Border
        {
            Background = (Brush)Application.Current.Resources["CardBrush"],
            BorderBrush = (Brush)Application.Current.Resources["CardBorderBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Child = inner,
            ClipToBounds = true,
        });
        return stack;
    }

    private static FrameworkElement TitleBlock(string title, string? detail)
    {
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        var titleText = Ui.Text(title, 13, FontWeights.Normal, TextBrush);
        titleText.TextTrimming = TextTrimming.None;
        titleText.TextWrapping = TextWrapping.Wrap;
        text.Children.Add(titleText);
        if (!string.IsNullOrEmpty(detail))
        {
            var detailText = Ui.Text(detail, 11.5, FontWeights.Normal, SecondaryBrush);
            detailText.TextWrapping = TextWrapping.Wrap;
            detailText.Margin = new Thickness(0, 2, 0, 0);
            text.Children.Add(detailText);
        }
        return text;
    }

    private static UIElement Row(string title, string? detail, FrameworkElement control, bool stretchControl = false)
    {
        var row = new DockPanel { Margin = new Thickness(14, 10, 14, 10), LastChildFill = true };
        control.VerticalAlignment = VerticalAlignment.Center;
        var text = TitleBlock(title, detail);
        text.Margin = new Thickness(0, 0, 16, 0);
        if (stretchControl)
        {
            text.Width = 170;
            DockPanel.SetDock(text, Dock.Left);
            row.Children.Add(text);
            row.Children.Add(control);
        }
        else
        {
            DockPanel.SetDock(control, Dock.Right);
            row.Children.Add(control);
            row.Children.Add(text);
        }
        return row;
    }

    private static CheckBox Switch(bool value, Action<bool> changed)
    {
        var box = new CheckBox { Style = (Style)Application.Current.Resources["Switch"], IsChecked = value };
        box.Checked += (_, _) => changed(true);
        box.Unchecked += (_, _) => changed(false);
        return box;
    }

    private static UIElement Toggle(string title, string? detail, Func<bool> get, Action<bool> set) =>
        Row(title, detail, Switch(get(), set));

    private static UIElement Choice<T>(string title, (T value, string label)[] options, Func<T> get, Action<T> set)
    {
        var combo = new ComboBox { Style = (Style)Application.Current.Resources["LenotchComboBox"] };
        var current = get();
        foreach (var (value, label) in options)
        {
            var item = new ComboBoxItem { Content = label, Tag = value };
            combo.Items.Add(item);
            if (EqualityComparer<T>.Default.Equals(value, current)) combo.SelectedItem = item;
        }
        combo.SelectionChanged += (_, _) =>
        {
            if (combo.SelectedItem is ComboBoxItem { Tag: T value }) set(value);
        };
        return Row(title, null, combo);
    }

    private static UIElement SliderRow(string title, double min, double max, double step, Func<double> get, Action<double> set, Func<double, string> format)
    {
        var label = Ui.Text(format(get()), 12, FontWeights.Normal, SecondaryBrush, true);
        label.Width = 52;
        label.TextAlignment = TextAlignment.Right;
        var slider = new Slider
        {
            Style = (Style)Application.Current.Resources["LenotchSlider"],
            Minimum = min,
            Maximum = max,
            Value = get(),
            Width = 180,
            TickFrequency = step,
            IsSnapToTickEnabled = true,
            VerticalAlignment = VerticalAlignment.Center,
        };
        slider.ValueChanged += (_, e) =>
        {
            set(e.NewValue);
            label.Text = format(e.NewValue);
        };
        return Row(title, null, Ui.HStack(8, slider, label));
    }

    private static UIElement ButtonRow(string title, string? detail, string button, Action action) =>
        Row(title, detail, SmallButton(button, action));

    private static Button SmallButton(string title, Action action, Thickness? margin = null)
    {
        var button = new Button
        {
            Content = title,
            Style = (Style)Application.Current.Resources["LenotchButton"],
            Margin = margin ?? new Thickness(0),
        };
        button.Click += (_, _) => action();
        return button;
    }

    private static FrameworkElement IconButton(string glyph, Action action)
    {
        var button = SmallButton("", action, new Thickness(4, 0, 0, 0));
        button.Content = Ui.Icon(glyph, 11, TextBrush);
        button.Padding = new Thickness(7, 5, 7, 5);
        return button;
    }

    private static TextBox TextField(string value, Action<string> changed)
    {
        var box = new TextBox { Text = value, Style = (Style)Application.Current.Resources["LenotchTextBox"], MinWidth = 120 };
        box.TextChanged += (_, _) => changed(box.Text);
        return box;
    }

    /// Click, then press the new shortcut (with Ctrl, Alt or Win). Backspace turns it off.
    private FrameworkElement ShortcutRecorder(Func<KeyShortcut?> get, Action<KeyShortcut?> set)
    {
        var button = SmallButton(get()?.Display ?? "Off", () => { });
        button.MinWidth = 140;
        var recording = false;
        button.Click += (_, _) =>
        {
            recording = true;
            button.Content = "Press keys…";
            button.Focus();
        };
        button.LostKeyboardFocus += (_, _) =>
        {
            if (!recording) return;
            recording = false;
            button.Content = get()?.Display ?? "Off";
        };
        button.PreviewKeyDown += (_, e) =>
        {
            if (!recording) return;
            e.Handled = true;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin)
                return;
            recording = false;
            if (key == Key.Escape)
            {
                button.Content = get()?.Display ?? "Off";
                return;
            }
            if (key is Key.Back or Key.Delete)
            {
                set(null);
                button.Content = "Off";
                return;
            }
            uint modifiers = 0;
            var held = Keyboard.Modifiers;
            if (held.HasFlag(ModifierKeys.Alt)) modifiers |= 1;
            if (held.HasFlag(ModifierKeys.Control)) modifiers |= 2;
            if (held.HasFlag(ModifierKeys.Shift)) modifiers |= 4;
            if (held.HasFlag(ModifierKeys.Windows)) modifiers |= 8;
            if ((modifiers & (1 | 2 | 8)) == 0)
            {
                button.Content = "Add Ctrl, Alt or Win";
                recording = true;
                return;
            }
            var shortcut = new KeyShortcut(modifiers, (uint)KeyInterop.VirtualKeyFromKey(key));
            set(shortcut);
            button.Content = shortcut.Display;
        };
        return button;
    }

    private static void OpenUrl(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); }
        catch (Exception) { }
    }
}
