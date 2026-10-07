using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace Lenotch.Core;

/// SwiftUI-style spring as a WPF easing: `response` is the period of the
/// undamped oscillation, `dampingFraction` 1 means no overshoot.
public sealed class SpringEase : EasingFunctionBase
{
    public double Response { get; init; } = 0.42;
    public double DampingFraction { get; init; } = 0.82;

    /// About how long the spring needs to settle, for the animation's duration.
    public Duration Duration
    {
        get
        {
            var omega = 2 * Math.PI / Response;
            var zeta = Math.Clamp(DampingFraction, 0.05, 1);
            // Envelope e^(-ζωt) under 0.2%.
            var seconds = Math.Min(Math.Log(500) / (zeta * omega), 2.5);
            return new Duration(TimeSpan.FromSeconds(seconds));
        }
    }

    protected override double EaseInCore(double normalizedTime)
    {
        var omega = 2 * Math.PI / Response;
        var zeta = Math.Clamp(DampingFraction, 0.05, 0.999);
        var t = normalizedTime * Duration.TimeSpan.TotalSeconds;
        var omegaD = omega * Math.Sqrt(1 - zeta * zeta);
        var envelope = Math.Exp(-zeta * omega * t);
        var value = 1 - envelope * (Math.Cos(omegaD * t) + zeta * omega / omegaD * Math.Sin(omegaD * t));
        return normalizedTime >= 1 ? 1 : value;
    }

    protected override Freezable CreateInstanceCore() => new SpringEase { Response = Response, DampingFraction = DampingFraction };

    public static SpringEase Of(double response, double damping) => new() { Response = response, DampingFraction = damping };
}

/// Small helpers for the animations used all over the notch.
public static class Motion
{
    public static readonly SpringEase NotchSpring = SpringEase.Of(0.42, 0.82);
    public static readonly SpringEase PageSpring = SpringEase.Of(0.46, 0.86);
    public static readonly SpringEase SlideSpring = SpringEase.Of(0.5, 0.78);

    public static void Animate(this IAnimatable target, DependencyProperty property, double to, SpringEase ease, double delay = 0)
    {
        var animation = new DoubleAnimation(to, ease.Duration) { EasingFunction = ease, BeginTime = TimeSpan.FromSeconds(delay) };
        target.BeginAnimation(property, animation, HandoffBehavior.SnapshotAndReplace);
    }

    public static void Animate(this IAnimatable target, DependencyProperty property, double to, double seconds,
                               IEasingFunction? ease = null, double delay = 0)
    {
        var animation = new DoubleAnimation(to, TimeSpan.FromSeconds(seconds))
        {
            EasingFunction = ease ?? new CubicEase { EasingMode = EasingMode.EaseOut },
            BeginTime = TimeSpan.FromSeconds(delay),
        };
        target.BeginAnimation(property, animation, HandoffBehavior.SnapshotAndReplace);
    }

    public static void FadeTo(this UIElement element, double opacity, double seconds = 0.2, Action? completed = null)
    {
        var animation = new DoubleAnimation(opacity, TimeSpan.FromSeconds(seconds))
        {
            EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseInOut },
        };
        if (completed != null) animation.Completed += (_, _) => completed();
        element.BeginAnimation(UIElement.OpacityProperty, animation, HandoffBehavior.SnapshotAndReplace);
    }

    /// Slides an item in (with a fade) when its tab appears, one after another by `order`.
    public static T SlideIn<T>(this T element, int order, bool forward = true) where T : UIElement
    {
        var translate = new TranslateTransform(forward ? 36 : -36, 0);
        element.RenderTransform = translate;
        element.Opacity = 0;
        var delay = order * 0.045;
        translate.Animate(TranslateTransform.XProperty, 0, SlideSpring, delay);
        element.Animate(UIElement.OpacityProperty, 1, 0.3, null, delay);
        return element;
    }

    /// Calls `tick` every frame (seconds since start) while the element is loaded,
    /// visible and the returned ticker is enabled. WPF keeps rendering every frame while
    /// anyone listens, so tickers must be switched off when nothing moves.
    public static FrameTicker OnFrame(FrameworkElement element, Action<double> tick, bool enabled = true,
                                      double minimumInterval = 1.0 / 30) =>
        new(element, tick, enabled, minimumInterval);
}

public sealed class FrameTicker
{
    private readonly FrameworkElement element;
    private readonly Action<double> tick;
    private readonly double minimumInterval;
    private readonly DateTime start = DateTime.UtcNow;
    private DateTime last = DateTime.MinValue;
    private bool attached;
    private bool enabled;

    public FrameTicker(FrameworkElement element, Action<double> tick, bool enabled, double minimumInterval)
    {
        this.element = element;
        this.tick = tick;
        this.enabled = enabled;
        this.minimumInterval = minimumInterval;
        element.Loaded += (_, _) => Update();
        element.Unloaded += (_, _) => Update();
        element.IsVisibleChanged += (_, _) => Update();
        Update();
    }

    public bool Enabled
    {
        get => enabled;
        set
        {
            if (value == enabled) return;
            enabled = value;
            Update();
        }
    }

    private void Update()
    {
        var wanted = enabled && element.IsLoaded && element.IsVisible;
        if (wanted == attached) return;
        attached = wanted;
        if (wanted) CompositionTarget.Rendering += Rendering;
        else CompositionTarget.Rendering -= Rendering;
    }

    private void Rendering(object? sender, EventArgs e)
    {
        var now = DateTime.UtcNow;
        if ((now - last).TotalSeconds < minimumInterval) return;
        last = now;
        tick((now - start).TotalSeconds);
    }
}
