using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Lenotch.AI;
using Lenotch.Core;
using Lenotch.Notch;

namespace Lenotch.Views;

/// codenotch's bands: green, then yellow from 50%, then orange-red from 70%.
public static class UsageColor
{
    public static Brush Of(double used) => used switch
    {
        < 0.5 => Ui.Frozen(Color.FromRgb(33, 224, 138)),
        < 0.7 => Ui.Frozen(Color.FromRgb(242, 242, 13)),
        _ => Ui.Frozen(Color.FromRgb(255, 61, 15)),
    };
}

/// Usage limits of the enabled coding assistants as rings: the provider's mark
/// inside, the headline window as the arc, the percentage underneath. Eight per
/// row, at most two rows. Hovering a ring shows its windows in a bubble below.
public sealed class AIUsageView : NotchContentView
{
    private const int RingsPerRow = 8, MaxRows = 2;
    private readonly NotchModel model;
    private readonly DispatcherTimer poll = new() { Interval = TimeSpan.FromSeconds(120) };
    private string key = "";
    private bool first = true;
    private bool refreshing;

    public AIUsageView(NotchModel model)
    {
        this.model = model;
        // Poll only while the widget is on screen.
        poll.Tick += async (_, _) => await model.Services.AIUsage.Refresh(model.Settings.UsageSources);
        Loaded += async (_, _) =>
        {
            poll.Start();
            await model.Services.AIUsage.Refresh(model.Settings.UsageSources);
        };
        Unloaded += (_, _) =>
        {
            poll.Stop();
            model.SetUsageHover(null);
        };
        // Right-click fetches fresh readings (dimmed while they load).
        Background = Brushes.Transparent;
        MouseRightButtonUp += async (_, e) =>
        {
            e.Handled = true;
            if (refreshing) return;
            refreshing = true;
            this.Animate(OpacityProperty, 0.45, 0.2);
            await model.Services.AIUsage.Refresh(model.Settings.UsageSources, force: true);
            this.Animate(OpacityProperty, 1, 0.2);
            refreshing = false;
        };
        Refresh();
    }

    private List<(UsageSource source, ProviderUsage usage)> Visible =>
        model.Settings.UsageSources
            .Select(s => (s, model.Services.AIUsage.UsageOf(s.Id)))
            .Where(item => item.Item2 is not ProviderUsage.NotSetUp)
            .Take(RingsPerRow * MaxRows)
            .ToList();

    public override void Refresh()
    {
        var visible = Visible;
        var newKey = string.Join("|", visible.Select(v => $"{v.source.Id}:{UsageKey(v.usage)}"));
        if (newKey == key && Children.Count > 0) return;
        key = newKey;
        Children.Clear();
        if (visible.Count == 0)
        {
            var hint = model.Settings.UsageSources.Count == 0
                ? "Turn on a provider in Settings → AI Usage."
                : "Sign in to Claude Code, Codex, Cursor or another supported tool to see usage here.";
            var text = Ui.Text(hint, 11, FontWeights.Medium, Ui.White(0.5));
            text.TextWrapping = TextWrapping.Wrap;
            var empty = Ui.VStack(4, Ui.HStack(6, Ui.Icon(Glyphs.Robot, 13, Brushes.White),
                Ui.Text("AI Usage", 13, FontWeights.SemiBold, Brushes.White)), text);
            empty.VerticalAlignment = VerticalAlignment.Center;
            empty.HorizontalAlignment = HorizontalAlignment.Center;
            Children.Add(empty);
            return;
        }
        var rows = visible.Chunk(RingsPerRow).ToList();
        var compact = rows.Count > 1;
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        for (var r = 0; r < rows.Count; r++)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            if (r > 0) row.Margin = new Thickness(0, 8, 0, 0);
            for (var i = 0; i < rows[r].Length; i++)
            {
                var (source, usage) = rows[r][i];
                var cell = RingCell(source, usage, compact ? 40 : 52);
                if (i > 0) cell.Margin = new Thickness(compact ? 18 : 26, 0, 0, 0);
                if (first) cell.SlideIn(r * 8 + i, model.PageMovesForward);
                row.Children.Add(cell);
            }
            stack.Children.Add(row);
        }
        first = false;
        Children.Add(stack);
    }

    public static string UsageKey(ProviderUsage usage) => usage switch
    {
        ProviderUsage.Ok ok => "ok" + ok.Plan + string.Join(",", ok.Windows.Select(w => $"{w.Id}={w.Used:0.###}@{w.ResetsAt:O}")),
        ProviderUsage.Problem problem => "problem" + problem.Message,
        _ => usage.GetType().Name,
    };

    private FrameworkElement RingCell(UsageSource source, ProviderUsage usage, double diameter)
    {
        var lineWidth = diameter > 44 ? 5 : 4;
        var ring = new RingView(lineWidth) { Width = diameter, Height = diameter };
        if (usage.Headline is { } headline) ring.Set(headline.Used, UsageColor.Of(headline.Used), Ui.Frozen(Color.FromRgb(51, 51, 51)));
        else ring.Set(0, Brushes.Transparent, Ui.Frozen(Color.FromRgb(51, 51, 51)));
        var glyph = source.GlyphView(diameter * 0.4);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        var scale = new ScaleTransform(1, 1);
        var circle = new Grid
        {
            Width = diameter,
            Height = diameter,
            Children = { ring, glyph },
            RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = scale,
        };

        FrameworkElement label = usage switch
        {
            ProviderUsage.Ok => Ui.Text($"{Math.Round((usage.Headline?.Used ?? 0) * 100)}%", diameter > 44 ? 15 : 12, FontWeights.Medium, Brushes.White, true),
            ProviderUsage.Loading => Ui.Text("–", diameter > 44 ? 15 : 12, FontWeights.Medium, Brushes.White),
            _ => Ui.Icon(Glyphs.Warning, diameter > 44 ? 13 : 11, Ui.Orange),
        };
        label.HorizontalAlignment = HorizontalAlignment.Center;
        label.Margin = new Thickness(0, diameter > 44 ? 8 : 4, 0, 0);
        var cell = new StackPanel { Children = { circle, label }, Background = Brushes.Transparent };

        cell.MouseEnter += (_, _) =>
        {
            var spring = SpringEase.Of(0.3, 0.7);
            scale.Animate(ScaleTransform.ScaleXProperty, 1.05, spring);
            scale.Animate(ScaleTransform.ScaleYProperty, 1.05, spring);
            // Where the ring is in the notch window, so the bubble can point at it.
            if (Window.GetWindow(cell) is { } window)
            {
                var center = cell.TransformToAncestor(window).Transform(new Point(cell.ActualWidth / 2, 0));
                model.SetUsageHover(new UsageHover(source.Id, center.X));
            }
        };
        cell.MouseLeave += (_, _) =>
        {
            var spring = SpringEase.Of(0.3, 0.7);
            scale.Animate(ScaleTransform.ScaleXProperty, 1, spring);
            scale.Animate(ScaleTransform.ScaleYProperty, 1, spring);
            if (model.UsageHover?.Id == source.Id) model.SetUsageHover(null);
        };
        return cell;
    }
}

/// codenotch's hover card: a black speech bubble below the notch, pointing up at
/// the hovered ring, with each limit window's bar, percentage and reset time.
public sealed class UsageTooltip : Canvas
{
    public const double CardWidth = 300;
    private const double PointerHeight = 10;
    private readonly NotchModel model;
    private FrameworkElement? card;
    private string shownKey = "";

    public UsageTooltip(NotchModel model)
    {
        this.model = model;
        IsHitTestVisible = false;
    }

    /// Shows the bubble for the hovered ring, `top` DIPs from the window's top.
    public void Update(double top, double windowWidth)
    {
        var hover = model.UsageHover;
        var source = hover == null ? null : model.Settings.UsageSources.FirstOrDefault(s => s.Id == hover.Id);
        if (hover == null || source == null)
        {
            shownKey = "";
            if (card is { } old)
            {
                card = null;
                old.FadeTo(0, 0.15, () => Children.Remove(old));
            }
            return;
        }
        var usage = model.Services.AIUsage.UsageOf(source.Id);
        var key = $"{hover}|{top}|{AIUsageView.UsageKey(usage)}|{DateTime.UtcNow:yyyyMMddHHmm}";
        if (key == shownKey) return;
        var fadeIn = card == null;
        shownKey = key;
        if (card != null) Children.Remove(card);
        var x = Math.Clamp(hover.AnchorX - CardWidth / 2, 8, windowWidth - CardWidth - 8);
        card = Card(source, usage, hover.AnchorX - x);
        SetLeft(card, x);
        SetTop(card, top + 2);
        if (fadeIn)
        {
            card.Opacity = 0;
            card.Animate(OpacityProperty, 1, 0.15);
        }
        Children.Add(card);
    }

    private static FrameworkElement Card(UsageSource source, ProviderUsage usage, double pointerX)
    {
        var content = new StackPanel { Margin = new Thickness(16, 14 + PointerHeight, 16, 16) };
        var title = Ui.HStack(8, source.GlyphView(18), Ui.Text($"{source.Title} Usage", 15, FontWeights.Normal, Brushes.White));
        if (usage is ProviderUsage.Ok { Plan: { } plan })
        {
            var planText = Ui.Text(plan, 12, FontWeights.Normal, Ui.White(0.45));
            planText.VerticalAlignment = VerticalAlignment.Center;
            title.Children.Add(planText);
            planText.Margin = new Thickness(8, 0, 0, 0);
        }
        content.Children.Add(title);
        switch (usage)
        {
            case ProviderUsage.Ok ok:
                foreach (var window in ok.Windows.Take(4))
                    content.Children.Add(WindowBlock(window));
                break;
            case ProviderUsage.Loading:
                content.Children.Add(Spaced(Ui.Text("Loading…", 12, FontWeights.Normal, Ui.White(0.5))));
                break;
            case ProviderUsage.Problem problem:
                var message = Ui.Text(problem.Message, 12, FontWeights.Normal, Ui.Orange);
                message.TextWrapping = TextWrapping.Wrap;
                content.Children.Add(Spaced(message));
                break;
        }
        var grid = new Grid { Width = CardWidth };
        var bubble = new System.Windows.Shapes.Path { Fill = Brushes.Black };
        grid.SizeChanged += (_, e) => bubble.Data = BubbleShape(e.NewSize, pointerX);
        grid.Children.Add(bubble);
        grid.Children.Add(content);
        return grid;
    }

    private static FrameworkElement Spaced(FrameworkElement element)
    {
        element.Margin = new Thickness(0, 12, 0, 0);
        return element;
    }

    private static FrameworkElement WindowBlock(UsageWindow window)
    {
        var block = new StackPanel { Margin = new Thickness(0, 12, 0, 0) };
        var head = new DockPanel();
        if (ResetText(window.ResetsAt) is { } reset)
        {
            var resetText = Ui.Text(reset, 13, FontWeights.Normal, Ui.White(0.45));
            DockPanel.SetDock(resetText, Dock.Right);
            head.Children.Add(resetText);
        }
        head.Children.Add(Ui.Text(window.Label, 13, FontWeights.Normal, Brushes.White));
        block.Children.Add(head);

        var used = Math.Clamp(window.Used, 0, 1);
        var bar = new Grid { Height = 6, Margin = new Thickness(0, 6, 0, 0) };
        bar.Children.Add(new Border { CornerRadius = new CornerRadius(3), Background = Ui.Frozen(Color.FromRgb(51, 51, 51)) });
        var fill = new Border { CornerRadius = new CornerRadius(3), Background = UsageColor.Of(used), HorizontalAlignment = HorizontalAlignment.Left };
        bar.SizeChanged += (_, e) => fill.Width = Math.Max(used > 0 ? 6 : 0, e.NewSize.Width * used);
        bar.Children.Add(fill);
        block.Children.Add(bar);
        var percent = Ui.Text($"{Math.Round(used * 100)}% used", 12, FontWeights.Normal, Ui.White(0.6), true);
        percent.Margin = new Thickness(0, 6, 0, 0);
        block.Children.Add(percent);
        return block;
    }

    /// "Resets in 2h 14m", "Resets in 3 days".
    private static string? ResetText(DateTime? resetsAt)
    {
        if (resetsAt is not { } reset) return null;
        var left = reset - DateTime.UtcNow;
        if (left <= TimeSpan.Zero) return "Resets soon";
        if (left.TotalDays >= 2) return $"Resets in {(int)left.TotalDays} days";
        if (left.TotalHours >= 1) return $"Resets in {(int)left.TotalHours}h {left.Minutes}m";
        return $"Resets in {Math.Max(left.Minutes, 1)}m";
    }

    private static Geometry BubbleShape(Size size, double pointerX)
    {
        var body = new RectangleGeometry(new Rect(0, PointerHeight, size.Width, Math.Max(size.Height - PointerHeight, 0)), 16, 16);
        var x = Math.Clamp(pointerX, 24, size.Width - 24);
        var pointer = new PathGeometry(new[]
        {
            new PathFigure(new Point(x - 11, PointerHeight + 1), new PathSegment[]
            {
                new LineSegment(new Point(x, 0), true),
                new LineSegment(new Point(x + 11, PointerHeight + 1), true),
            }, true),
        });
        return new CombinedGeometry(GeometryCombineMode.Union, body, pointer);
    }
}

/// In the open notch: presets to start a timer, or the running timer's controls.
public sealed class TimerPanel : NotchContentView
{
    private static readonly int[] Presets = { 1, 3, 5, 10, 15, 25, 30, 45, 60 };
    private static int customMinutes = 20;
    private readonly NotchModel model;
    private readonly DispatcherTimer tick = new() { Interval = TimeSpan.FromSeconds(0.25) };
    private bool? showedRunning;
    private RingView? ring;
    private TextBlock? remaining;
    private TextBlock? pauseIcon;

    public TimerPanel(NotchModel model)
    {
        this.model = model;
        tick.Tick += (_, _) => Update();
        Loaded += (_, _) => tick.Start();
        Unloaded += (_, _) => tick.Stop();
        Refresh();
    }

    public override void Refresh()
    {
        var running = model.Timer.IsActive;
        if (running != showedRunning)
        {
            showedRunning = running;
            Children.Clear();
            var view = running ? Running() : Picker();
            view.SlideIn(0, model.PageMovesForward);
            Children.Add(view);
        }
        Update();
    }

    private FrameworkElement Picker()
    {
        var grid = new System.Windows.Controls.Primitives.UniformGrid { Columns = 5, HorizontalAlignment = HorizontalAlignment.Center };
        foreach (var minutes in Presets)
        {
            var m = minutes;
            grid.Children.Add(Chip(minutes < 60 ? $"{minutes} min" : "1 h", false, () => Start(m)));
        }
        grid.Children.Add(Chip("Custom", true, () => Start(customMinutes)));

        var customText = Ui.Text($"{customMinutes} min", 13, FontWeights.SemiBold, Brushes.White, true);
        customText.Width = 70;
        customText.TextAlignment = TextAlignment.Center;
        customText.VerticalAlignment = VerticalAlignment.Center;
        var silent = model.Settings.TimerSilent;
        var stepper = Ui.HStack(10,
            RoundButton(Glyphs.Remove, 28, Ui.White(0.12), () =>
            {
                customMinutes = Math.Max(1, customMinutes - (customMinutes > 10 ? 5 : 1));
                customText.Text = $"{customMinutes} min";
            }),
            customText,
            RoundButton(Glyphs.Add, 28, Ui.White(0.12), () =>
            {
                customMinutes = Math.Min(600, customMinutes + (customMinutes >= 10 ? 5 : 1));
                customText.Text = $"{customMinutes} min";
            }));
        // Silent timers still fold the notch down, just without the alarm.
        var bell = RoundButton(silent ? Glyphs.BellOff : Glyphs.Bell, 28,
            silent ? Ui.White(0.12) : Ui.Brush(Colors.Orange, 0.35), () =>
            {
                model.Settings.TimerSilent = !model.Settings.TimerSilent;
                showedRunning = null;
                Refresh();
            });
        bell.Margin = new Thickness(24, 0, 0, 0);
        stepper.Children.Add(bell);
        stepper.HorizontalAlignment = HorizontalAlignment.Center;
        stepper.Margin = new Thickness(0, 14, 0, 0);
        var stack = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Children = { grid, stepper } };
        return stack;
    }

    private FrameworkElement Running()
    {
        ring = new RingView(6) { Width = 110, Height = 110 };
        remaining = Ui.Text("", 22, FontWeights.Bold, Brushes.White, true);
        remaining.HorizontalAlignment = HorizontalAlignment.Center;
        remaining.VerticalAlignment = VerticalAlignment.Center;
        var dial = new Grid { Width = 110, Height = 110, Children = { ring, remaining } };

        pauseIcon = Ui.Icon(Glyphs.Pause, 15, Brushes.White);
        var controls = Ui.HStack(10,
            RoundButton(pauseIcon, 40, Ui.White(0.12), () =>
            {
                if (model.Timer.IsPaused) model.Timer.Resume(); else model.Timer.Pause();
                Update();
            }),
            RoundButton(Glyphs.Close, 40, Ui.White(0.12), () => model.Timer.Cancel()));
        controls.HorizontalAlignment = HorizontalAlignment.Center;
        var column = Ui.VStack(10, controls, Chip("+1 min", false, () => model.Timer.Add(60)));
        if (model.Timer.IsSilent)
            column.Children.Add(Ui.HStack(4, Ui.Icon(Glyphs.BellOff, 11, Ui.White(0.5)), Ui.Text("Silent", 11, FontWeights.Medium, Ui.White(0.5))));
        column.VerticalAlignment = VerticalAlignment.Center;
        column.Margin = new Thickness(28, 0, 0, 0);
        var row = Ui.HStack(0, dial, column);
        row.HorizontalAlignment = HorizontalAlignment.Center;
        row.VerticalAlignment = VerticalAlignment.Center;
        return row;
    }

    private void Update()
    {
        if (ring == null || remaining == null || !model.Timer.IsActive) return;
        var now = DateTime.UtcNow;
        ring.Set(model.Timer.Fraction(now), Ui.Orange);
        remaining.Text = Services.NotchTimer.Format(model.Timer.Remaining(now));
        remaining.Foreground = model.Timer.IsPaused ? Ui.White(0.5) : Brushes.White;
        if (pauseIcon != null) pauseIcon.Text = model.Timer.IsPaused ? Glyphs.Play : Glyphs.Pause;
    }

    private void Start(int minutes) => model.Timer.Start(minutes * 60, model.Settings.TimerSilent);

    private static FrameworkElement Chip(string title, bool highlighted, Action action)
    {
        var text = Ui.Text(title, 12, FontWeights.SemiBold, highlighted ? Brushes.Black : Brushes.White);
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.VerticalAlignment = VerticalAlignment.Center;
        var chip = new Border
        {
            Width = 62,
            Height = 28,
            CornerRadius = new CornerRadius(14),
            Background = highlighted ? Ui.Orange : Ui.White(0.1),
            Child = text,
            Margin = new Thickness(4),
        };
        return Ui.Button(chip, action);
    }

    private static FrameworkElement RoundButton(string glyph, double size, Brush tint, Action action) =>
        RoundButton(Ui.Icon(glyph, size * 0.38, Brushes.White), size, tint, action);

    private static FrameworkElement RoundButton(TextBlock icon, double size, Brush tint, Action action)
    {
        var circle = new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size / 2),
            Background = tint,
            Child = icon,
        };
        return Ui.Button(circle, action);
    }
}
