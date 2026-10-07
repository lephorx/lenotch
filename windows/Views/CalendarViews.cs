using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using Lenotch.Core;
using Lenotch.Notch;
using Lenotch.Services;

namespace Lenotch.Views;

/// The calendar: a scrollable day strip with the selected day's events underneath
/// (beside the music), or a month grid with the day's events beside it (on its own).
/// Scrolling over it scrolls the calendar and never switches tabs.
public sealed class CalendarPanel : NotchContentView
{
    private readonly NotchModel model;
    private readonly double width;
    private readonly bool expanded;
    private readonly TextBlock heading;
    private readonly Border events = new();
    private readonly DayStrip? strip;
    private readonly MonthGrid? grid;
    private readonly System.Windows.Threading.DispatcherTimer minute = new() { Interval = TimeSpan.FromMinutes(1) };
    private string eventsKey = "";

    private CalendarService Calendar => model.Services.Calendar;

    public CalendarPanel(NotchModel model, double width, bool expanded)
    {
        this.model = model;
        this.width = width;
        this.expanded = expanded;
        Width = width;
        VerticalAlignment = VerticalAlignment.Top;
        HorizontalAlignment = HorizontalAlignment.Left;
        Background = Brushes.Transparent;

        if (expanded)
        {
            heading = Ui.Text("", 13, FontWeights.SemiBold, Ui.White(0.85));
            grid = new MonthGrid(Calendar) { Width = 250, VerticalAlignment = VerticalAlignment.Top };
            var side = new DockPanel { Margin = new Thickness(26, 0, 0, 0) };
            DockPanel.SetDock(heading, Dock.Top);
            heading.Margin = new Thickness(0, 0, 0, 8);
            side.Children.Add(heading);
            side.Children.Add(events);
            var row = new DockPanel();
            DockPanel.SetDock(grid, Dock.Left);
            row.Children.Add(grid);
            row.Children.Add(side);
            Children.Add(row);
        }
        else
        {
            heading = Ui.Text("", 12, FontWeights.SemiBold, Ui.White(0.75));
            strip = new DayStrip(Calendar, width) { Margin = new Thickness(0, 6, 0, 6) };
            var stack = new DockPanel();
            DockPanel.SetDock(heading, Dock.Top);
            DockPanel.SetDock(strip, Dock.Top);
            stack.Children.Add(heading);
            stack.Children.Add(strip);
            stack.Children.Add(events);
            Children.Add(stack);
        }

        minute.Tick += (_, _) => _ = Calendar.Refresh();
        // Reload while visible only; the notch closing stops it.
        Loaded += (_, _) =>
        {
            Calendar.Select(DateTime.Today);
            _ = Calendar.Refresh();
            minute.Start();
        };
        Unloaded += (_, _) => minute.Stop();
        Refresh();
    }

    public override void Refresh()
    {
        heading.Text = expanded
            ? Calendar.SelectedDay.ToString("dddd, d MMMM")
            : Calendar.SelectedDay.ToString("MMMM yyyy");
        strip?.Refresh();
        grid?.Refresh();
        var key = $"{Calendar.SelectedDay:d}|{Calendar.HasFeeds}|{model.Settings.ShowFullEventTitles}|"
                  + string.Join(",", Calendar.Events.Select(e => e.Id + e.Title));
        if (key == eventsKey) return;
        eventsKey = key;
        events.Child = EventList();
    }

    private UIElement EventList()
    {
        if (!Calendar.HasFeeds)
        {
            // Windows doesn't share its calendars; feeds are added in Settings.
            var text = Ui.HStack(6, Ui.Icon(Glyphs.Calendar, 11, Ui.White(0.85)),
                Ui.Text("Add a calendar", 12, FontWeights.SemiBold, Ui.White(0.85)));
            text.Margin = new Thickness(0, 4, 0, 0);
            text.HorizontalAlignment = HorizontalAlignment.Left;
            text.VerticalAlignment = VerticalAlignment.Top;
            return Ui.Button(text, () => model.OpenSettings?.Invoke());
        }
        if (Calendar.Events.Count == 0)
        {
            var empty = Ui.Text(Calendar.SelectedDay == DateTime.Today ? "No more events today" : "No events",
                12, FontWeights.Medium, Ui.White(0.5));
            empty.Margin = new Thickness(0, 4, 0, 0);
            empty.VerticalAlignment = VerticalAlignment.Top;
            return empty;
        }
        var list = new StackPanel();
        FrameworkElement? next = null;
        var now = DateTime.Now;
        foreach (var item in Calendar.Events)
        {
            var row = EventRow(item, now);
            row.Margin = new Thickness(0, list.Children.Count > 0 ? 8 : 0, 0, 0);
            list.Children.Add(row);
            if (next == null && !item.IsAllDay) next = row;
        }
        var scroll = new ScrollViewer
        {
            Content = list,
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            PanningMode = PanningMode.VerticalOnly,
        };
        // Scroll to the next event today.
        if (model.Settings.AutoScrollCalendar && Calendar.SelectedDay == DateTime.Today && next != null)
            scroll.Loaded += (_, _) => next.BringIntoView(new Rect(0, 0, 1, scroll.ActualHeight));
        return scroll;
    }

    private FrameworkElement EventRow(CalendarEvent item, DateTime now)
    {
        var color = Ui.Frozen(item.Color);
        var bar = new Border { Width = 3, Height = 26, CornerRadius = new CornerRadius(1.5), Background = color, VerticalAlignment = VerticalAlignment.Center };
        var title = Ui.Text(item.Title, 12, FontWeights.SemiBold, Brushes.White);
        if (model.Settings.ShowFullEventTitles) { title.TextWrapping = TextWrapping.Wrap; title.TextTrimming = TextTrimming.None; }
        var time = item.IsAllDay ? "All day" : $"{item.Start:t} – {item.End:t}";
        var detail = new StackPanel { Orientation = Orientation.Horizontal };
        if (item.IsHappening(now) && !item.IsAllDay)
            detail.Children.Add(new TextBlock { Text = "Now ", FontSize = 10, FontWeight = FontWeights.Bold, Foreground = color, VerticalAlignment = VerticalAlignment.Center });
        detail.Children.Add(Ui.Text(time, 11, FontWeights.Medium, Ui.White(0.5), true));
        var text = Ui.VStack(1, title, detail);
        text.Margin = new Thickness(8, 0, 0, 0);
        var row = new DockPanel { Background = Brushes.Transparent };
        DockPanel.SetDock(bar, Dock.Left);
        row.Children.Add(bar);
        row.Children.Add(text);
        return row;
    }
}

/// Days that scroll sideways and snap the selected one to the centre. The mouse
/// wheel, a drag or a click moves through them.
public sealed class DayStrip : Grid
{
    private const double CellWidth = 30, Spacing = 6;
    private readonly CalendarService calendar;
    private readonly double width;
    private readonly Canvas canvas = new() { ClipToBounds = true };
    private readonly TranslateTransform offset = new();
    private readonly List<DateTime> days;
    private readonly List<Border> cells = new();
    private DateTime shownSelection;
    private Point? dragStart;
    private int dragSteps;

    public DayStrip(CalendarService calendar, double width)
    {
        this.calendar = calendar;
        this.width = width;
        Width = width;
        Height = 40;
        Background = Brushes.Transparent;
        var today = DateTime.Today;
        days = Enumerable.Range(-7, 22).Select(i => today.AddDays(i)).ToList();
        var row = new StackPanel { Orientation = Orientation.Horizontal, RenderTransform = offset };
        foreach (var day in days)
        {
            var cell = new Border { Width = CellWidth, Height = 38, CornerRadius = new CornerRadius(10), Margin = new Thickness(0, 0, Spacing, 0) };
            var target = day;
            cell.MouseLeftButtonUp += (_, e) =>
            {
                if (dragSteps != 0) return;
                calendar.Select(target);
                e.Handled = true;
            };
            cells.Add(cell);
            row.Children.Add(cell);
        }
        canvas.Children.Add(row);
        Children.Add(canvas);
        // Fade the days out towards the edges.
        OpacityMask = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0.5),
            EndPoint = new Point(1, 0.5),
            GradientStops =
            {
                new GradientStop(Colors.Transparent, 0), new GradientStop(Colors.Black, 0.18),
                new GradientStop(Colors.Black, 0.82), new GradientStop(Colors.Transparent, 1),
            },
        };

        MouseWheel += (_, e) =>
        {
            Step(e.Delta > 0 ? -1 : 1);
            e.Handled = true;
        };
        MouseLeftButtonDown += (_, e) => { dragStart = e.GetPosition(this); dragSteps = 0; CaptureMouse(); };
        MouseMove += (_, e) =>
        {
            if (dragStart is not { } start) return;
            var steps = (int)Math.Round((start.X - e.GetPosition(this).X) / (CellWidth + Spacing));
            if (steps == dragSteps) return;
            Step(steps - dragSteps);
            dragSteps = steps;
        };
        MouseLeftButtonUp += (_, _) => { dragStart = null; ReleaseMouseCapture(); };
        Refresh();
    }

    private void Step(int by)
    {
        var index = days.IndexOf(calendar.SelectedDay);
        if (index < 0) index = 7;
        calendar.Select(days[Math.Clamp(index + by, 0, days.Count - 1)]);
    }

    private DateTime shownToday;

    public void Refresh()
    {
        var selected = calendar.SelectedDay;
        if (selected == shownSelection && shownToday == DateTime.Today) return;
        shownToday = DateTime.Today;
        for (var i = 0; i < days.Count; i++)
        {
            var day = days[i];
            var isSelected = day == selected;
            var isToday = day == DateTime.Today;
            cells[i].Background = isSelected ? (isToday ? Ui.Red : Ui.White(0.18)) : Brushes.Transparent;
            var weekday = CultureInfo.CurrentCulture.DateTimeFormat.GetShortestDayName(day.DayOfWeek)[..1].ToUpperInvariant();
            cells[i].Child = Ui.VStack(0,
                Center(Ui.Text(weekday, 9, FontWeights.SemiBold, Ui.White(isSelected ? 0.85 : 0.45))),
                Center(Ui.Text(day.Day.ToString(), 14, FontWeights.Bold,
                    isSelected ? Brushes.White : isToday ? Ui.Red : Ui.White(0.75), true)));
            ((StackPanel)cells[i].Child).VerticalAlignment = VerticalAlignment.Center;
        }
        var index = Math.Max(days.IndexOf(selected), 0);
        var x = width / 2 - CellWidth / 2 - index * (CellWidth + Spacing);
        if (shownSelection == default) offset.X = x;
        else offset.Animate(TranslateTransform.XProperty, x, SpringEase.Of(0.35, 0.85));
        shownSelection = selected;
    }

    private static TextBlock Center(TextBlock text)
    {
        text.HorizontalAlignment = HorizontalAlignment.Center;
        return text;
    }
}

/// A month at a glance: weekday letters, six weeks of days with the neighbouring
/// months dimmed, today filled, the selected day ringed and up to three event dots
/// per day. Clicking a day selects it; the wheel or a drag changes the month.
public sealed class MonthGrid : StackPanel
{
    private readonly CalendarService calendar;
    private readonly TextBlock month = Ui.Text("", 15, FontWeights.Bold, Brushes.White);
    private readonly TextBlock year = Ui.Text("", 11, FontWeights.SemiBold, Ui.White(0.75), true);
    private readonly UniformGrid days = new() { Columns = 7, Rows = 6 };
    private string shownKey = "";
    private DateTime lastWheel = DateTime.MinValue;
    private double wheelTravel;
    private Point? dragStart;

    public MonthGrid(CalendarService calendar)
    {
        this.calendar = calendar;
        Background = Brushes.Transparent;
        var header = new DockPanel { Margin = new Thickness(0, 0, 0, 4) };
        var chevrons = Ui.HStack(0, MonthButton(Glyphs.ChevronLeft, -1), MonthButton(Glyphs.ChevronRight, 1));
        DockPanel.SetDock(chevrons, Dock.Right);
        header.Children.Add(chevrons);
        var yearPill = new Border
        {
            Child = year,
            Padding = new Thickness(7, 2, 7, 2),
            CornerRadius = new CornerRadius(8),
            Background = Ui.White(0.14),
            Margin = new Thickness(6, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        header.Children.Add(Ui.HStack(0, month, yearPill));
        Children.Add(header);

        var weekdays = new UniformGrid { Columns = 7, Margin = new Thickness(0, 0, 0, 4) };
        var names = CultureInfo.CurrentCulture.DateTimeFormat.ShortestDayNames;
        var first = (int)CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek;
        for (var i = 0; i < 7; i++)
        {
            var text = Ui.Text(names[(first + i) % 7][..1].ToUpperInvariant(), 10, FontWeights.SemiBold, Ui.White(0.4));
            text.HorizontalAlignment = HorizontalAlignment.Center;
            weekdays.Children.Add(text);
        }
        Children.Add(weekdays);
        Children.Add(days);

        // One month per wheel gesture, like a page turn.
        MouseWheel += (_, e) =>
        {
            var now = DateTime.UtcNow;
            if ((now - lastWheel).TotalSeconds > 0.35) wheelTravel = 0;
            lastWheel = now;
            var before = Math.Abs(wheelTravel) >= 60;
            wheelTravel += e.Delta;
            if (!before && Math.Abs(wheelTravel) >= 60) calendar.ShowMonth(e.Delta > 0 ? -1 : 1);
            e.Handled = true;
        };
        PreviewMouseLeftButtonDown += (_, e) => dragStart = e.GetPosition(this);
        PreviewMouseMove += (_, e) =>
        {
            if (dragStart is not { } start || e.LeftButton != MouseButtonState.Pressed) return;
            var delta = e.GetPosition(this) - start;
            var travel = Math.Abs(delta.X) > Math.Abs(delta.Y) ? delta.X : delta.Y;
            if (Math.Abs(travel) < 60) return;
            calendar.ShowMonth(travel > 0 ? -1 : 1);
            dragStart = null;
        };
        PreviewMouseLeftButtonUp += (_, _) => dragStart = null;
        Refresh();
    }

    private FrameworkElement MonthButton(string glyph, int offset)
    {
        var host = new Border { Width = 22, Height = 20, Child = Ui.Icon(glyph, 10, Ui.White(0.6)) };
        return Ui.Button(host, () => calendar.ShowMonth(offset));
    }

    public void Refresh()
    {
        var shown = calendar.DisplayedMonth;
        var key = $"{shown:d}|{calendar.SelectedDay:d}|" + string.Join(";", calendar.MonthDots.Select(d => $"{d.Key:d}{d.Value.Count}"));
        if (key == shownKey) return;
        var monthChanged = !shownKey.StartsWith($"{shown:d}|");
        shownKey = key;
        month.Text = shown.ToString("MMMM");
        year.Text = shown.Year.ToString();
        days.Children.Clear();
        foreach (var day in CalendarService.GridDays(shown))
        {
            var inMonth = day.Month == shown.Month && day.Year == shown.Year;
            var isToday = day == DateTime.Today;
            var isSelected = day == calendar.SelectedDay;
            var number = new Border
            {
                Width = 22,
                Height = 22,
                CornerRadius = new CornerRadius(11),
                Background = isToday ? Ui.Blue : Brushes.Transparent,
                BorderBrush = !isToday && isSelected ? Ui.Blue : null,
                BorderThickness = new Thickness(!isToday && isSelected ? 1.5 : 0),
                Child = new TextBlock
                {
                    Text = day.Day.ToString(),
                    FontSize = 12,
                    FontWeight = FontWeights.SemiBold,
                    FontFamily = Ui.TextFont,
                    Foreground = isToday ? Brushes.White : Ui.White(inMonth ? 0.9 : 0.3),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                },
            };
            var dots = new StackPanel { Orientation = Orientation.Horizontal, Height = 4, HorizontalAlignment = HorizontalAlignment.Center, Opacity = inMonth ? 1 : 0.4 };
            if (calendar.MonthDots.TryGetValue(day, out var colors))
                foreach (var color in colors)
                    dots.Children.Add(new Border { Width = 4, Height = 4, CornerRadius = new CornerRadius(2), Background = Ui.Frozen(color), Margin = new Thickness(1, 0, 1, 0) });
            var cell = Ui.VStack(1, number, dots);
            cell.Background = Brushes.Transparent;
            cell.Margin = new Thickness(0, 0, 0, 1);
            var target = day;
            cell.MouseLeftButtonUp += (_, e) => { calendar.Select(target); e.Handled = true; };
            days.Children.Add(cell);
        }
        if (monthChanged)
        {
            days.Opacity = 0;
            days.Animate(OpacityProperty, 1, 0.2);
        }
    }
}
