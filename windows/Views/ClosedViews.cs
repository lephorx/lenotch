using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using Lenotch.Core;
using Lenotch.Notch;
using Lenotch.Services;

namespace Lenotch.Views;

/// A view inside the notch; `Refresh` is called when the model changes.
public abstract class NotchContentView : Grid
{
    public virtual void Refresh() { }
}

/// Collapsed notch while music plays: artwork left of the notch, equalizer right of it.
public sealed class LiveActivityView : NotchContentView
{
    private readonly NotchModel model;
    private readonly Border artworkHost = new();
    private readonly EqualizerBars bars;
    private object? shownArtwork = new();

    public LiveActivityView(NotchModel model)
    {
        this.model = model;
        var side = NotchGeometry.NotchSize.Height - 10;
        artworkHost.Width = side;
        artworkHost.Height = side;
        artworkHost.HorizontalAlignment = HorizontalAlignment.Left;
        artworkHost.Margin = new Thickness(10, 0, 0, 0);
        Children.Add(artworkHost);
        bars = new EqualizerBars(model)
        {
            Width = side * 0.8,
            Height = side * 0.6,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 0, 10 + side * 0.1, 0),
        };
        Children.Add(bars);
        Refresh();
    }

    public override void Refresh()
    {
        if (!ReferenceEquals(shownArtwork, model.Media.Artwork))
        {
            shownArtwork = model.Media.Artwork;
            artworkHost.Child = new ArtworkView(model.Media.Artwork, 6);
        }
        bars.Refresh();
    }
}

/// The current song, dropped briefly out of the closed notch.
public sealed class PeekView : NotchContentView
{
    public PeekView(NotchModel model)
    {
        var track = model.Media.Track;
        var row = new Grid
        {
            Margin = new Thickness(16, NotchGeometry.NotchSize.Height + 6, 16, 10),
            VerticalAlignment = VerticalAlignment.Top,
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var artwork = new ArtworkView(model.Media.Artwork, 8) { Width = 38, Height = 38 };
        row.Children.Add(artwork);
        var text = Ui.VStack(2,
            Ui.Text(track?.Title ?? "", 13, FontWeights.SemiBold, Brushes.White),
            Ui.Text(string.IsNullOrEmpty(track?.Artist) ? track?.Album ?? "" : track.Artist, 12, FontWeights.Medium, Ui.White(0.6)));
        text.Margin = new Thickness(10, 0, 10, 0);
        text.VerticalAlignment = VerticalAlignment.Center;
        SetColumn(text, 1);
        row.Children.Add(text);
        var bars = new EqualizerBars(model) { Width = 16, Height = 14, VerticalAlignment = VerticalAlignment.Center };
        SetColumn(bars, 2);
        row.Children.Add(bars);
        Children.Add(row);
    }
}

/// Closed notch while a timer runs: with music playing, artwork and bars left of the
/// notch; otherwise the timer symbol. The ring and time are right of it.
public sealed class TimerLiveView : NotchContentView
{
    private readonly NotchModel model;
    private readonly RingView ring = new(2.5) { Width = 15, Height = 15 };
    private readonly TextBlock time = Ui.Text("", 12, FontWeights.SemiBold, Brushes.White, monospacedDigits: true);
    private readonly StackPanel left = new() { Orientation = Orientation.Horizontal };
    private readonly DispatcherTimer tick = new() { Interval = TimeSpan.FromSeconds(0.25) };
    private bool? showedMusic;

    public TimerLiveView(NotchModel model)
    {
        this.model = model;
        left.Margin = new Thickness(10, 0, 0, 0);
        left.HorizontalAlignment = HorizontalAlignment.Left;
        left.VerticalAlignment = VerticalAlignment.Center;
        Children.Add(left);
        var right = Ui.HStack(7, ring, time);
        right.HorizontalAlignment = HorizontalAlignment.Right;
        right.VerticalAlignment = VerticalAlignment.Center;
        right.Margin = new Thickness(0, 0, 12, 0);
        Children.Add(right);
        tick.Tick += (_, _) => Update();
        Loaded += (_, _) => tick.Start();
        Unloaded += (_, _) => tick.Stop();
        Refresh();
    }

    public override void Refresh()
    {
        var music = model.ShowsLiveActivity;
        if (music != showedMusic)
        {
            showedMusic = music;
            left.Children.Clear();
            var side = NotchGeometry.NotchSize.Height - 10;
            if (music)
            {
                left.Children.Add(new ArtworkView(model.Media.Artwork, 6) { Width = side, Height = side });
                left.Children.Add(new EqualizerBars(model) { Width = side * 0.7, Height = side * 0.55, Margin = new Thickness(8, 0, 0, 0) });
            }
            else
            {
                left.Children.Add(Ui.Icon(model.Timer.IsPaused ? Glyphs.Pause : Glyphs.Timer, 13, Ui.Orange));
            }
        }
        Update();
    }

    private void Update()
    {
        var now = DateTime.UtcNow;
        ring.Set(model.Timer.Fraction(now), Ui.Orange);
        time.Text = NotchTimer.Format(model.Timer.Remaining(now));
        time.Foreground = model.Timer.IsPaused ? Ui.White(0.5) : Brushes.White;
    }
}

/// The card the notch folds down into when a timer ends: the timer symbol,
/// 0:00 and an X to stop the alarm.
public sealed class TimerDoneView : NotchContentView
{
    public TimerDoneView(NotchModel model)
    {
        var row = new Grid
        {
            Margin = new Thickness(20, NotchGeometry.NotchSize.Height + 8, 20, 12),
            VerticalAlignment = VerticalAlignment.Top,
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var bell = Ui.Icon(Glyphs.Timer, 24, Ui.Orange);
        var shake = new RotateTransform();
        bell.RenderTransformOrigin = new Point(0.5, 0.5);
        bell.RenderTransform = shake;
        shake.BeginAnimation(RotateTransform.AngleProperty,
            new DoubleAnimation(-10, 10, TimeSpan.FromSeconds(0.1)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        bell.Effect = new DropShadowEffect { Color = Colors.Orange, BlurRadius = 16, ShadowDepth = 0, Opacity = 0.8 };
        row.Children.Add(bell);

        var zero = Ui.Text("0:00", 30, FontWeights.SemiBold, Ui.Orange, monospacedDigits: true);
        zero.VerticalAlignment = VerticalAlignment.Center;
        zero.Margin = new Thickness(0, 0, 14, 0);
        zero.BeginAnimation(OpacityProperty,
            new DoubleAnimation(0.55, 1, TimeSpan.FromSeconds(0.6)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        SetColumn(zero, 2);
        row.Children.Add(zero);

        var stop = Ui.Button(new Border
        {
            Width = 38,
            Height = 38,
            CornerRadius = new CornerRadius(19),
            Background = Ui.Orange,
            Child = Ui.Icon(Glyphs.Close, 14, Brushes.White),
        }, () => model.StopAlarm?.Invoke());
        SetColumn(stop, 3);
        row.Children.Add(stop);
        Children.Add(row);
    }
}

/// Closed notch during a download or upload: download speed left of the notch, upload right.
public sealed class NetworkSpeedView : NotchContentView
{
    private readonly NotchModel model;
    private readonly (TextBlock icon, TextBlock text) down, up;

    public NetworkSpeedView(NotchModel model)
    {
        this.model = model;
        down = Side(Glyphs.ArrowDown, HorizontalAlignment.Left, new Thickness(12, 0, 0, 0));
        up = Side(Glyphs.ArrowUp, HorizontalAlignment.Right, new Thickness(0, 0, 12, 0));
        Refresh();
    }

    private (TextBlock, TextBlock) Side(string glyph, HorizontalAlignment alignment, Thickness margin)
    {
        var icon = Ui.Icon(glyph, 10, Ui.White(0.5));
        var text = Ui.Text("", 11, FontWeights.SemiBold, Brushes.White, monospacedDigits: true);
        var stack = Ui.HStack(4, icon, text);
        stack.HorizontalAlignment = alignment;
        stack.VerticalAlignment = VerticalAlignment.Center;
        stack.Margin = margin;
        Children.Add(stack);
        return (icon, text);
    }

    public override void Refresh()
    {
        if (model.Network is not { } speed) return;
        Apply(down, speed.Down, speed.Down >= speed.Up);
        Apply(up, speed.Up, speed.Up > speed.Down);
    }

    private static void Apply((TextBlock icon, TextBlock text) side, double rate, bool highlighted)
    {
        side.icon.Foreground = highlighted ? Ui.Cyan : Ui.White(0.5);
        side.text.Text = NetworkMonitor.Format(rate);
        side.text.Foreground = Ui.White(highlighted ? 1 : 0.6);
    }
}

/// Closed notch while nothing else shows: a coin left of the notch, its price and
/// 24-hour change right of it, cycling through the chosen coins every 5 seconds.
public sealed class CryptoTickerView : NotchContentView
{
    private readonly NotchModel model;
    private readonly DispatcherTimer cycle = new() { Interval = TimeSpan.FromSeconds(5) };
    private int index;
    private Grid? row;

    public CryptoTickerView(NotchModel model)
    {
        this.model = model;
        ClipToBounds = true;
        cycle.Tick += (_, _) => { index++; Show(true); };
        Loaded += (_, _) => cycle.Start();
        Unloaded += (_, _) => cycle.Stop();
        Show(false);
    }

    public override void Refresh() => Show(false);

    private void Show(bool animated)
    {
        var prices = model.Services.Crypto.Prices;
        if (prices.Count == 0) return;
        var price = prices[index % prices.Count];
        var next = Row(price);
        var old = row;
        row = next;
        Children.Add(next);
        if (old == null || !animated)
        {
            if (old != null) Children.Remove(old);
            return;
        }
        // The new coin rises in from below while the old one leaves upwards.
        var enter = new TranslateTransform(0, 16);
        next.RenderTransform = enter;
        next.Opacity = 0;
        enter.Animate(TranslateTransform.YProperty, 0, SpringEase.Of(0.45, 0.85));
        next.Animate(OpacityProperty, 1, 0.3);
        var leave = new TranslateTransform();
        old.RenderTransform = leave;
        leave.Animate(TranslateTransform.YProperty, -16, 0.3);
        old.FadeTo(0, 0.25, () => Children.Remove(old));
    }

    private Grid Row(CoinPrice price)
    {
        var grid = new Grid();
        var badge = new Border
        {
            Width = 18,
            Height = 18,
            CornerRadius = new CornerRadius(9),
            Background = new LinearGradientBrush(Lighter(price.Coin.Color), price.Coin.Color, 90),
            Child = new TextBlock
            {
                Text = price.Coin.Symbol[..1],
                FontSize = 10,
                FontWeight = FontWeights.Black,
                Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
            },
        };
        var left = Ui.HStack(6, badge, Ui.Text(price.Coin.Symbol, 11, FontWeights.Bold, Brushes.White));
        left.Margin = new Thickness(12, 0, 0, 0);
        left.HorizontalAlignment = HorizontalAlignment.Left;
        left.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(left);

        var priceText = Ui.Text(CryptoService.Format(price.Price, model.Settings.CryptoCurrency), 11, FontWeights.SemiBold, Brushes.White, true);
        priceText.HorizontalAlignment = HorizontalAlignment.Right;
        var change = Ui.Text($"{(price.Change >= 0 ? "▲" : "▼")}{Math.Abs(price.Change):0.0}%", 9, FontWeights.SemiBold,
            price.Change >= 0 ? Ui.Green : Ui.Red, true);
        change.HorizontalAlignment = HorizontalAlignment.Right;
        var right = new StackPanel
        {
            Margin = new Thickness(0, 0, 12, 0),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
            Width = NotchGeometry.IndicatorSideWidth - 12,
            Children = { priceText, change },
        };
        grid.Children.Add(right);
        return grid;
    }

    private static Color Lighter(Color color) =>
        Color.FromRgb((byte)Math.Min(255, color.R + 40), (byte)Math.Min(255, color.G + 40), (byte)Math.Min(255, color.B + 40));
}

/// First-launch intro inside the notch: the logo drops down, the name slides in,
/// a shine sweeps across, then it all shrinks away and `finished` closes the notch.
public sealed class IntroView : NotchContentView
{
    public IntroView(Action finished)
    {
        const double logoHeight = 54;
        var logo = new Grid { Width = logoHeight * Ui.LogoAspect, Height = logoHeight };
        logo.Children.Add(new Image { Source = Ui.Logo });
        // Shine band sweeping across, limited to the logo's shape.
        var shineMove = new TranslateTransform(-logoHeight, 0);
        var shine = new Border
        {
            Width = logoHeight * 0.5,
            Background = new LinearGradientBrush
            {
                StartPoint = new Point(0, 0.5),
                EndPoint = new Point(1, 0.5),
                GradientStops =
                {
                    new GradientStop(Colors.Transparent, 0),
                    new GradientStop(Color.FromArgb(190, 255, 255, 255), 0.5),
                    new GradientStop(Colors.Transparent, 1),
                },
            },
            HorizontalAlignment = HorizontalAlignment.Left,
            RenderTransform = new TransformGroup { Children = { new RotateTransform(20), shineMove } },
        };
        var shineHost = new Grid { OpacityMask = new ImageBrush(Ui.Logo), ClipToBounds = true, Children = { shine } };
        logo.Children.Add(shineHost);
        var glow = new DropShadowEffect { Color = Colors.White, ShadowDepth = 0, BlurRadius = 8, Opacity = 0 };
        logo.Effect = glow;
        // Starts hidden above, behind the top of the screen, tilted.
        var drop = new TranslateTransform(0, -(NotchGeometry.NotchSize.Height + logoHeight + 20));
        var tilt = new RotateTransform(-14, logo.Width / 2, logoHeight / 2);
        logo.RenderTransform = new TransformGroup { Children = { tilt, drop } };

        var title = new TextBlock
        {
            Text = "Lenotch",
            FontSize = 30,
            FontWeight = FontWeights.Bold,
            FontFamily = Ui.DisplayFont,
            Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(14, 0, 0, 0),
            Opacity = 0,
        };
        var titleMove = new TranslateTransform(-14, 0);
        title.RenderTransform = titleMove;
        var titleBlur = new BlurEffect { Radius = 8 };
        title.Effect = titleBlur;

        var row = Ui.HStack(0, logo, title);
        row.HorizontalAlignment = HorizontalAlignment.Center;
        row.VerticalAlignment = VerticalAlignment.Center;
        row.Margin = new Thickness(0, NotchGeometry.NotchSize.Height, 0, 0);
        row.RenderTransformOrigin = new Point(0.5, 0.5);
        var rowScale = new ScaleTransform(1, 1);
        row.RenderTransform = rowScale;
        Children.Add(row);

        void After(double seconds, Action action)
        {
            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
            timer.Tick += (_, _) => { timer.Stop(); action(); };
            timer.Start();
        }

        After(0.38, () =>
        {
            var spring = SpringEase.Of(0.55, 0.55);
            drop.Animate(TranslateTransform.YProperty, 0, spring);
            tilt.Animate(RotateTransform.AngleProperty, 0, spring);
        });
        After(0.70, () =>
        {
            glow.Animate(DropShadowEffect.OpacityProperty, 0.6, 0.6);
            glow.Animate(DropShadowEffect.BlurRadiusProperty, 32, 0.6);
        });
        After(0.90, () =>
        {
            var spring = SpringEase.Of(0.5, 0.8);
            title.Animate(OpacityProperty, 1, 0.4);
            titleMove.Animate(TranslateTransform.XProperty, 0, spring);
            titleBlur.Animate(BlurEffect.RadiusProperty, 0, 0.4);
            shineMove.Animate(TranslateTransform.XProperty, logoHeight * 1.2, 0.9, new SineEase { EasingMode = EasingMode.EaseInOut }, 0.25);
        });
        After(2.50, () =>
        {
            var ease = new QuadraticEase { EasingMode = EasingMode.EaseIn };
            rowScale.Animate(ScaleTransform.ScaleXProperty, 0.7, 0.3, ease);
            rowScale.Animate(ScaleTransform.ScaleYProperty, 0.7, 0.3, ease);
            row.Animate(OpacityProperty, 0, 0.3, ease);
            glow.Animate(DropShadowEffect.OpacityProperty, 0, 0.3);
        });
        After(2.76, finished);
    }
}
