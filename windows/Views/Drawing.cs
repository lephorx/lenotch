using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Lenotch.Core;
using Lenotch.Notch;
using Lenotch.Services;

namespace Lenotch.Views;

/// Bars that follow the real audio when the visualizer has a signal, and otherwise
/// bounce with a stand-in animation while playing; they settle when paused.
public sealed class EqualizerBars : FrameworkElement
{
    private static readonly double[] Speeds = { 5.1, 7.3, 4.2, 6.4 };
    private static readonly double[] Phases = { 0, 1.7, 3.1, 0.8 };

    private readonly NotchModel model;
    private readonly FrameTicker ticker;
    private readonly double[] shown = { 0.2, 0.2, 0.2, 0.2 };
    private double time;

    public EqualizerBars(NotchModel model)
    {
        this.model = model;
        IsHitTestVisible = false;
        ticker = Motion.OnFrame(this, t =>
        {
            time = t;
            InvalidateVisual();
            // Settle, then stop rendering while paused.
            if (!model.Media.IsPlaying && Array.TrueForAll(shown, l => Math.Abs(l - 0.2) < 0.01)) ticker!.Enabled = false;
        });
        Refresh();
    }

    public void Refresh()
    {
        ticker.Enabled = true;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        var count = Speeds.Length;
        var spacing = ActualWidth * 0.12;
        var barWidth = (ActualWidth - spacing * (count - 1)) / count;
        if (barWidth <= 0) return;
        var visualizer = model.EqualizerSource;
        var real = visualizer is { HasSignal: true } ? visualizer.Levels : null;
        var brush = new SolidColorBrush(model.EqualizerColor);
        for (var i = 0; i < count; i++)
        {
            double target = !model.Media.IsPlaying ? 0.2
                : real != null && i < real.Length ? 0.15 + 0.85 * real[i]
                : 0.3 + 0.7 * Math.Abs(Math.Sin(time * Speeds[i] + Phases[i]));
            shown[i] += (target - shown[i]) * 0.45;
            var height = Math.Max(barWidth, ActualHeight * shown[i]);
            var rect = new Rect(i * (barWidth + spacing), (ActualHeight - height) / 2, barWidth, height);
            dc.DrawRoundedRectangle(brush, null, rect, barWidth / 2, barWidth / 2);
        }
    }
}

/// Thin scrubbable progress bar with elapsed and total time underneath.
public sealed class ProgressBar : Grid
{
    private readonly NotchModel model;
    private readonly BarTrack track;
    private readonly TextBlock elapsedText;
    private readonly TextBlock durationText;
    private readonly FrameTicker ticker;
    private double? dragProgress;
    private bool pressed;

    public ProgressBar(NotchModel model)
    {
        this.model = model;
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(18) });
        RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        track = new BarTrack { Cursor = Cursors.Hand };
        Children.Add(track);
        elapsedText = Ui.Text("0:00", 11, FontWeights.Medium, Ui.White(0.5), monospacedDigits: true);
        durationText = Ui.Text("0:00", 11, FontWeights.Medium, Ui.White(0.5), monospacedDigits: true);
        durationText.HorizontalAlignment = HorizontalAlignment.Right;
        var labels = new Grid { Margin = new Thickness(0, 4, 0, 0) };
        labels.Children.Add(elapsedText);
        labels.Children.Add(durationText);
        SetRow(labels, 1);
        Children.Add(labels);

        track.MouseLeftButtonDown += (_, e) =>
        {
            if (Duration <= 0) return;
            pressed = true;
            track.CaptureMouse();
            model.IsInteracting = true;
            dragProgress = ProgressAt(e.GetPosition(track));
            Update();
            e.Handled = true;
        };
        track.MouseMove += (_, e) =>
        {
            if (!pressed) return;
            dragProgress = ProgressAt(e.GetPosition(track));
            Update();
        };
        track.MouseLeftButtonUp += (_, e) =>
        {
            if (!pressed) return;
            pressed = false;
            track.ReleaseMouseCapture();
            if (dragProgress is { } progress) model.Media.Seek(progress * Duration);
            dragProgress = null;
            model.IsInteracting = false;
            Update();
            e.Handled = true;
        };
        ticker = Motion.OnFrame(this, _ => Update());
        Refresh();
    }

    private double Duration => model.Media.Track?.Duration ?? 0;

    private double ProgressAt(Point point) => Math.Clamp(point.X / Math.Max(track.ActualWidth, 1), 0, 1);

    public void Refresh()
    {
        // Redraw every frame while playing so the bar glides instead of stepping.
        ticker.Enabled = model.Media.IsPlaying || pressed;
        Update();
    }

    private void Update()
    {
        var duration = Duration;
        var elapsed = model.Media.Elapsed(DateTime.UtcNow);
        var progress = dragProgress ?? (duration > 0 ? elapsed / duration : 0);
        elapsedText.Text = Ui.FormatTime(dragProgress is { } p ? p * duration : elapsed);
        durationText.Text = Ui.FormatTime(duration);
        track.Set(progress, dragProgress != null, model.ProgressColor ?? Colors.White);
    }

    private sealed class BarTrack : FrameworkElement
    {
        private double progress;
        private bool dragging;
        private Color fill = Colors.White;

        public void Set(double newProgress, bool isDragging, Color color)
        {
            progress = Math.Clamp(newProgress, 0, 1);
            dragging = isDragging;
            fill = color;
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext dc)
        {
            // A clear background takes clicks above and below the thin bar.
            dc.DrawRectangle(Brushes.Transparent, null, new Rect(RenderSize));
            var height = dragging ? 7 : 4;
            var y = (ActualHeight - height) / 2;
            dc.DrawRoundedRectangle(Ui.White(0.18), null, new Rect(0, y, ActualWidth, height), height / 2.0, height / 2.0);
            var width = ActualWidth * progress;
            if (width <= 0) return;
            width = Math.Max(width, height);
            var brush = new SolidColorBrush(fill);
            // Soft glow under the fill.
            var glow = new SolidColorBrush(Color.FromArgb(70, fill.R, fill.G, fill.B));
            dc.DrawRoundedRectangle(glow, null, new Rect(0, y - 2, width + 2, height + 4), height, height);
            dc.DrawRoundedRectangle(brush, null, new Rect(0, y, width, height), height / 2.0, height / 2.0);
        }
    }
}

/// A ring: track plus an arc from the top, clockwise.
public sealed class RingView : FrameworkElement
{
    private double fraction;
    private Brush arc = Ui.Orange;
    private Brush trackBrush = Ui.White(0.15);
    private double lineWidth;

    public RingView(double lineWidth)
    {
        this.lineWidth = lineWidth;
        IsHitTestVisible = false;
    }

    public void Set(double newFraction, Brush arcBrush, Brush? track = null)
    {
        fraction = Math.Clamp(newFraction, 0, 1);
        arc = arcBrush;
        if (track != null) trackBrush = track;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        var radius = Math.Min(ActualWidth, ActualHeight) / 2 - lineWidth / 2;
        if (radius <= 0) return;
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        dc.DrawEllipse(null, new Pen(trackBrush, lineWidth), center, radius, radius);
        if (fraction <= 0.001) return;
        var pen = new Pen(arc, lineWidth) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        if (fraction >= 0.999)
        {
            dc.DrawEllipse(null, pen, center, radius, radius);
            return;
        }
        var angle = fraction * 2 * Math.PI;
        var start = new Point(center.X, center.Y - radius);
        var end = new Point(center.X + radius * Math.Sin(angle), center.Y - radius * Math.Cos(angle));
        var figure = new PathFigure { StartPoint = start };
        figure.Segments.Add(new ArcSegment(end, new Size(radius, radius), 0, fraction > 0.5, SweepDirection.Clockwise, true));
        dc.DrawGeometry(null, pen, new PathGeometry { Figures = { figure } });
    }
}

/// Battery glyph with optional percentage (yellow with Battery saver).
public sealed class BatteryView : StackPanel
{
    private readonly BatteryMonitor battery;
    private readonly TextBlock percentage;
    private readonly Glyph glyph = new();

    public BatteryView(BatteryMonitor battery, bool showsPercentage)
    {
        this.battery = battery;
        Orientation = Orientation.Horizontal;
        VerticalAlignment = VerticalAlignment.Center;
        percentage = Ui.Text("", 11, FontWeights.Medium, Ui.White(0.55), monospacedDigits: true);
        percentage.VerticalAlignment = VerticalAlignment.Center;
        percentage.Margin = new Thickness(0, 0, 5, 0);
        if (showsPercentage) Children.Add(percentage);
        glyph.Width = 25;
        glyph.Height = 11;
        Children.Add(glyph);
        Refresh();
    }

    public void Refresh()
    {
        percentage.Text = $"{Math.Round(battery.Level * 100)}%";
        percentage.Foreground = battery.IsSaver ? Ui.Yellow : Ui.White(0.55);
        glyph.Set(battery);
    }

    private sealed class Glyph : FrameworkElement
    {
        private double level = 1;
        private Brush fill = Brushes.White;
        private bool bolt;

        public void Set(BatteryMonitor battery)
        {
            level = battery.Level;
            // Yellow with Battery saver, green while charging, red when low.
            fill = battery.IsSaver ? Ui.Yellow : battery.IsCharging ? Ui.Green : battery.Level <= 0.2 ? Ui.Red : Brushes.White;
            bolt = battery.IsCharging || battery.IsPluggedIn;
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext dc)
        {
            var body = new Rect(0.5, 0.5, 22, 10);
            dc.DrawRoundedRectangle(null, new Pen(Ui.White(0.45), 1), body, 3, 3);
            dc.DrawRoundedRectangle(fill, null, new Rect(2, 2, Math.Max(2, 19 * level), 7), 1.5, 1.5);
            dc.DrawRoundedRectangle(Ui.White(0.45), null, new Rect(23.5, 3.5, 1.5, 4), 0.75, 0.75);
            if (!bolt) return;
            var text = new FormattedText(Glyphs.Bolt, System.Globalization.CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
                new Typeface(Ui.IconFont, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal), 8, Brushes.White, 1.0);
            dc.DrawText(text, new Point(11.5 - text.Width / 2, 5.5 - text.Height / 2));
        }
    }
}

/// Album art, falling back to a music note.
public sealed class ArtworkView : Border
{
    public ArtworkView(BitmapSource? artwork, double cornerRadius)
    {
        CornerRadius = new CornerRadius(cornerRadius);
        ClipToBounds = true;
        if (artwork != null)
        {
            Background = new ImageBrush(artwork) { Stretch = Stretch.UniformToFill };
        }
        else
        {
            Background = Ui.White(0.08);
            Child = new Viewbox { Child = Ui.Icon(Glyphs.Music, 20, Ui.White(0.4)), Margin = new Thickness(cornerRadius > 10 ? 36 : 4) };
        }
    }
}

/// A small animated picture of the weather: sun rays turning, clouds drifting,
/// rain and snow falling, lightning flashing, stars twinkling at night.
public sealed class WeatherScene : FrameworkElement
{
    private readonly WeatherKind kind;
    private readonly bool isDay;
    private double time;

    public WeatherScene(WeatherKind kind, bool isDay)
    {
        this.kind = kind;
        this.isDay = isDay;
        IsHitTestVisible = false;
        Motion.OnFrame(this, t => { time = t; InvalidateVisual(); });
    }

    private static Brush Fill(Color color, double opacity) => Ui.Brush(color, opacity);

    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight;
        switch (kind)
        {
            case WeatherKind.Clear:
                if (isDay) Sun(dc, new Point(w * 0.5, h * 0.5), w * 0.2);
                else Night(dc, new Point(w * 0.5, h * 0.48));
                break;
            case WeatherKind.PartlyCloudy:
                if (isDay) Sun(dc, new Point(w * 0.36, h * 0.36), w * 0.16);
                else Night(dc, new Point(w * 0.36, h * 0.34));
                Cloud(dc, new Point(w * 0.58 + Drift(0.35, w * 0.05), h * 0.6), w * 0.3, 0.95);
                break;
            case WeatherKind.Cloudy:
                Cloud(dc, new Point(w * 0.38 + Drift(0.25, w * 0.06), h * 0.42), w * 0.26, 0.6);
                Cloud(dc, new Point(w * 0.58 + Drift(0.3, w * 0.05, 2), h * 0.6), w * 0.32, 0.95);
                break;
            case WeatherKind.Fog:
                for (var band = 0; band < 4; band++)
                {
                    var y = h * (0.3 + band * 0.14);
                    var x = Drift(0.4, w * 0.08, band);
                    dc.DrawRoundedRectangle(Fill(Colors.White, 0.35 + band % 2 * 0.2), null,
                        new Rect(w * 0.12 + x, y, w * 0.76, h * 0.06), h * 0.03, h * 0.03);
                }
                break;
            case WeatherKind.Drizzle or WeatherKind.Rain or WeatherKind.Thunderstorm:
                var heavy = kind != WeatherKind.Drizzle;
                Rain(dc, heavy ? 14 : 7, heavy ? 1.6 : 1.0);
                Cloud(dc, new Point(w * 0.5 + Drift(0.3, w * 0.03), h * 0.36), w * 0.34, kind == WeatherKind.Thunderstorm ? 0.7 : 0.9);
                if (kind == WeatherKind.Thunderstorm) Lightning(dc);
                break;
            case WeatherKind.Snow:
                Snow(dc);
                Cloud(dc, new Point(w * 0.5 + Drift(0.3, w * 0.03), h * 0.36), w * 0.34, 0.95);
                break;
        }
    }

    /// Gentle side-to-side movement.
    private double Drift(double speed, double amount, double offset = 0) => Math.Sin((time + offset) * speed) * amount;

    private void Sun(DrawingContext dc, Point center, double radius)
    {
        var glow = 1 + 0.08 * Math.Sin(time * 2);
        dc.DrawEllipse(new RadialGradientBrush(Color.FromArgb(90, 255, 214, 10), Colors.Transparent), null,
            center, radius * 1.9 * glow, radius * 1.9 * glow);
        var pen = new Pen(Fill(Color.FromRgb(255, 214, 10), 0.9), radius * 0.16) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        for (var ray = 0; ray < 10; ray++)
        {
            var angle = ray / 10.0 * Math.PI * 2 + time * 0.4;
            dc.DrawLine(pen,
                new Point(center.X + Math.Cos(angle) * radius * 1.35, center.Y + Math.Sin(angle) * radius * 1.35),
                new Point(center.X + Math.Cos(angle) * radius * 1.75, center.Y + Math.Sin(angle) * radius * 1.75));
        }
        dc.DrawEllipse(new LinearGradientBrush(Color.FromRgb(255, 230, 89), Colors.Orange, 90), null, center, radius, radius);
    }

    private void Night(DrawingContext dc, Point center)
    {
        double[,] stars = { { 0.18, 0.2, 0 }, { 0.8, 0.18, 1.3 }, { 0.72, 0.72, 2.1 }, { 0.2, 0.7, 3.4 }, { 0.88, 0.45, 4.2 }, { 0.1, 0.45, 5.1 } };
        for (var i = 0; i < stars.GetLength(0); i++)
        {
            var twinkle = 0.3 + 0.7 * Math.Abs(Math.Sin(time * 1.5 + stars[i, 2]));
            var r = ActualWidth * 0.018;
            dc.DrawEllipse(Fill(Colors.White, twinkle), null, new Point(ActualWidth * stars[i, 0], ActualHeight * stars[i, 1]), r, r);
        }
        var radius = ActualWidth * 0.2;
        var moon = new CombinedGeometry(GeometryCombineMode.Exclude,
            new EllipseGeometry(center, radius, radius),
            new EllipseGeometry(new Point(center.X + radius * 0.55, center.Y - radius * 0.25), radius, radius));
        dc.DrawGeometry(Fill(Color.FromRgb(242, 237, 204), 1), null, moon);
    }

    private static void Cloud(DrawingContext dc, Point center, double scale, double opacity)
    {
        double[,] puffs = { { -0.55, 0.15, 0.42 }, { -0.1, -0.2, 0.58 }, { 0.45, 0.05, 0.48 }, { 0, 0.25, 0.45 } };
        var group = new GeometryGroup { FillRule = FillRule.Nonzero };
        for (var i = 0; i < puffs.GetLength(0); i++)
            group.Children.Add(new EllipseGeometry(new Point(center.X + puffs[i, 0] * scale, center.Y + puffs[i, 1] * scale),
                puffs[i, 2] * scale, puffs[i, 2] * scale));
        dc.DrawGeometry(Fill(Colors.White, opacity), null, group.GetOutlinedPathGeometry());
    }

    private void Rain(DrawingContext dc, int count, double speed)
    {
        for (var drop = 0; drop < count; drop++)
        {
            var x = ActualWidth * (0.25 + 0.5 * drop / Math.Max(count - 1, 1));
            var progress = (time * speed + drop * 0.37) % 1;
            var y = ActualHeight * (0.45 + progress * 0.5);
            var pen = new Pen(Fill(Color.FromRgb(140, 191, 255), 1 - progress * 0.6), ActualWidth * 0.02)
            {
                StartLineCap = PenLineCap.Round,
                EndLineCap = PenLineCap.Round,
            };
            dc.DrawLine(pen, new Point(x, y), new Point(x - ActualWidth * 0.02, y + ActualHeight * 0.08));
        }
    }

    private void Snow(DrawingContext dc)
    {
        for (var flake = 0; flake < 10; flake++)
        {
            var progress = (time * 0.35 + flake * 0.29) % 1;
            var x = ActualWidth * (0.22 + 0.56 * flake / 9) + Math.Sin(time * 1.5 + flake) * ActualWidth * 0.03;
            var y = ActualHeight * (0.45 + progress * 0.5);
            var r = ActualWidth * 0.022;
            dc.DrawEllipse(Fill(Colors.White, 1 - progress * 0.5), null, new Point(x, y), r, r);
        }
    }

    private void Lightning(DrawingContext dc)
    {
        // A short double flash every few seconds.
        var phase = time % 4;
        if (!(phase < 0.12 || (phase > 0.22 && phase < 0.3))) return;
        double w = ActualWidth, h = ActualHeight;
        var figure = new PathFigure { StartPoint = new Point(w * 0.52, h * 0.48), IsClosed = true };
        foreach (var (x, y) in new[] { (0.44, 0.68), (0.52, 0.68), (0.46, 0.88), (0.6, 0.62), (0.52, 0.62), (0.58, 0.48) })
            figure.Segments.Add(new LineSegment(new Point(w * x, h * y), true));
        dc.DrawGeometry(Brushes.Gold, null, new PathGeometry { Figures = { figure } });
    }
}
