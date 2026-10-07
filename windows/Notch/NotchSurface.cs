using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Lenotch.Core;

namespace Lenotch.Notch;

/// The black notch: small outward "ears" at the top that melt into the screen's
/// edge, rounded corners at the bottom. Its content is clipped to the shape; the
/// mic/camera outline is drawn on top, just below the edge.
public sealed class NotchSurface : FrameworkElement
{
    public static readonly DependencyProperty BodyWidthProperty = Register(nameof(BodyWidth), 190);
    public static readonly DependencyProperty BodyHeightProperty = Register(nameof(BodyHeight), 32);
    public static readonly DependencyProperty TopRadiusProperty = Register(nameof(TopRadius), NotchGeometry.ClosedTopRadius);
    public static readonly DependencyProperty BottomRadiusProperty = Register(nameof(BottomRadius), NotchGeometry.ClosedBottomRadius);
    /// 0 closed … 1 open: fades in the album-colour glow.
    public static readonly DependencyProperty OpennessProperty = Register(nameof(Openness), 0);

    private static DependencyProperty Register(string name, double value) =>
        DependencyProperty.Register(name, typeof(double), typeof(NotchSurface),
            new FrameworkPropertyMetadata(value, FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender));

    public double BodyWidth { get => (double)GetValue(BodyWidthProperty); set => SetValue(BodyWidthProperty, value); }
    public double BodyHeight { get => (double)GetValue(BodyHeightProperty); set => SetValue(BodyHeightProperty, value); }
    public double TopRadius { get => (double)GetValue(TopRadiusProperty); set => SetValue(TopRadiusProperty, value); }
    public double BottomRadius { get => (double)GetValue(BottomRadiusProperty); set => SetValue(BottomRadiusProperty, value); }
    public double Openness { get => (double)GetValue(OpennessProperty); set => SetValue(OpennessProperty, value); }

    /// The page shown inside the notch (clipped to the shape).
    public Grid Content { get; } = new() { ClipToBounds = false };
    public PrivacyOutline Outline { get; } = new() { IsHitTestVisible = false };

    private Color? musicColor;
    /// The current song's colour, glowing in the lower left of the open notch.
    public Color? MusicColor
    {
        get => musicColor;
        set
        {
            if (value == musicColor) return;
            musicColor = value;
            InvalidateVisual();
        }
    }

    public NotchSurface()
    {
        AddVisualChild(Content);
        AddVisualChild(Outline);
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Top;
    }

    protected override int VisualChildrenCount => 2;
    protected override Visual GetVisualChild(int index) => index == 0 ? Content : Outline;

    public Geometry Shape { get; private set; } = Geometry.Empty;

    protected override Size MeasureOverride(Size available)
    {
        Content.Measure(new Size(Math.Max(BodyWidth, 0), Math.Max(BodyHeight, 0)));
        Outline.Measure(available);
        return new Size(BodyWidth + 2 * TopRadius, BodyHeight);
    }

    protected override Size ArrangeOverride(Size final)
    {
        Shape = MakeShape(new Rect(0, 0, BodyWidth + 2 * TopRadius, BodyHeight), TopRadius, BottomRadius);
        Content.Arrange(new Rect(TopRadius, 0, Math.Max(BodyWidth, 0), Math.Max(BodyHeight, 0)));
        var clip = Shape.Clone();
        clip.Transform = new TranslateTransform(-TopRadius, 0);
        Content.Clip = clip;
        Outline.Shape = Shape;
        Outline.Arrange(new Rect(0, 0, final.Width, final.Height));
        return final;
    }

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawGeometry(Brushes.Black, null, Shape);
        if (MusicColor is not { } color || Openness <= 0.01) return;
        var size = new Size(BodyWidth + 2 * TopRadius, BodyHeight);
        var notchFraction = NotchGeometry.NotchSize.Height / Math.Max(size.Height, 1);
        dc.PushClip(Shape);
        dc.PushOpacity(Openness);
        // Keep the album colour near the cover in the lower left; the top stays black.
        var glow = new RadialGradientBrush
        {
            Center = new Point(size.Width * 0.12, size.Height * 0.98),
            GradientOrigin = new Point(size.Width * 0.12, size.Height * 0.98),
            RadiusX = size.Width * 0.58,
            RadiusY = size.Width * 0.58,
            MappingMode = BrushMappingMode.Absolute,
            GradientStops =
            {
                new GradientStop(WithAlpha(color, 0.42), 0),
                new GradientStop(WithAlpha(color, 0.13), 0.5),
                new GradientStop(WithAlpha(color, 0), 1),
            },
        };
        var fade = new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1),
            GradientStops =
            {
                new GradientStop(Colors.Transparent, 0),
                new GradientStop(Colors.Transparent, notchFraction),
                new GradientStop(Colors.White, Math.Min(notchFraction + 0.48, 1)),
                new GradientStop(Colors.White, 1),
            },
        };
        dc.PushOpacityMask(fade);
        dc.DrawRectangle(glow, null, new Rect(size));
        dc.Pop();
        // A narrow rim carries that colour along the bottom edge.
        var rim = new LinearGradientBrush(WithAlpha(color, 0.8), WithAlpha(color, 0.28), 0);
        dc.PushOpacityMask(new LinearGradientBrush
        {
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 1),
            GradientStops =
            {
                new GradientStop(Colors.Transparent, 0),
                new GradientStop(Colors.Transparent, 0.55),
                new GradientStop(Colors.White, 0.9),
                new GradientStop(Colors.White, 1),
            },
        });
        dc.DrawGeometry(null, new Pen(rim, 2), Shape);
        dc.Pop();
        dc.Pop();
        dc.Pop();
    }

    private static Color WithAlpha(Color color, double alpha) => Color.FromArgb((byte)(alpha * 255), color.R, color.G, color.B);

    /// The notch outline: the ears extend `top` beyond the body on each side.
    public static Geometry MakeShape(Rect rect, double top, double bottom)
    {
        bottom = Math.Max(Math.Min(bottom, rect.Height - top), 0);
        const double k = 0.5523;
        var figure = new PathFigure { StartPoint = new Point(rect.Left, rect.Top), IsClosed = true, IsFilled = true };
        var segments = new List<PathSegment>
        {
            // Left ear: curves from the top edge of the screen down into the side.
            new BezierSegment(new Point(rect.Left + top * k, rect.Top), new Point(rect.Left + top, rect.Top + top * (1 - k)),
                new Point(rect.Left + top, rect.Top + top), true),
            new LineSegment(new Point(rect.Left + top, rect.Bottom - bottom), true),
            new BezierSegment(new Point(rect.Left + top, rect.Bottom - bottom * (1 - k)),
                new Point(rect.Left + top + bottom * (1 - k), rect.Bottom), new Point(rect.Left + top + bottom, rect.Bottom), true),
            new LineSegment(new Point(rect.Right - top - bottom, rect.Bottom), true),
            new BezierSegment(new Point(rect.Right - top - bottom * (1 - k), rect.Bottom),
                new Point(rect.Right - top, rect.Bottom - bottom * (1 - k)), new Point(rect.Right - top, rect.Bottom - bottom), true),
            new LineSegment(new Point(rect.Right - top, rect.Top + top), true),
            // Right ear.
            new BezierSegment(new Point(rect.Right - top, rect.Top + top * (1 - k)), new Point(rect.Right - top * k, rect.Top),
                new Point(rect.Right, rect.Top), true),
        };
        foreach (var segment in segments) figure.Segments.Add(segment);
        var geometry = new PathGeometry { Figures = { figure } };
        geometry.Freeze();
        return geometry;
    }
}

/// The outline shown while the microphone (orange) or camera (green) is in use,
/// gently pulsing; with `Glow` a soft halo around the notch instead.
public sealed class PrivacyOutline : FrameworkElement
{
    private List<Color> colors = new();
    private bool glow;
    private double pulse;
    private readonly FrameTicker ticker;

    public Geometry Shape { get; set; } = Geometry.Empty;

    public PrivacyOutline()
    {
        ticker = Motion.OnFrame(this, time =>
        {
            pulse = (Math.Sin(time * Math.PI / 1.4) + 1) / 2;
            InvalidateVisual();
        }, enabled: false, minimumInterval: 1.0 / 20);
    }

    public void Set(List<Color> newColors, bool newGlow)
    {
        colors = newColors;
        glow = newGlow;
        Effect = glow ? new System.Windows.Media.Effects.BlurEffect { Radius = 7 } : null;
        ticker.Enabled = colors.Count > 0;
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        if (colors.Count == 0) return;
        var brush = colors.Count == 1
            ? (Brush)new SolidColorBrush(colors[0])
            : new LinearGradientBrush(colors[0], colors[1], 0);
        var opacity = glow ? 0.45 + 0.55 * pulse : 0.6 + 0.4 * pulse;
        // Moved down a little so the line shows just below the notch's edge, and faded
        // out over the top 14 DIP so no colour runs along the screen's top edge.
        dc.PushTransform(new TranslateTransform(0, 2.5));
        dc.PushOpacityMask(new LinearGradientBrush
        {
            MappingMode = BrushMappingMode.Absolute,
            StartPoint = new Point(0, 0),
            EndPoint = new Point(0, 14),
            GradientStops = { new GradientStop(Colors.Transparent, 0), new GradientStop(Colors.White, 1) },
        });
        dc.PushOpacity(opacity);
        dc.DrawGeometry(null, new Pen(brush, glow ? 5 : 3), Shape);
        dc.Pop();
        dc.Pop();
        dc.Pop();
    }
}
