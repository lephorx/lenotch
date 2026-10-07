using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Lenotch.Core;

/// Segoe Fluent Icons (Windows 11) / Segoe MDL2 Assets (Windows 10) code points.
public static class Glyphs
{
    public const string Play = "";
    public const string Pause = "";
    public const string Previous = "";
    public const string Next = "";
    public const string Shuffle = "";
    public const string Repeat = "";
    public const string RepeatOne = "";
    public const string Settings = "";
    public const string Timer = "";
    public const string Music = "";
    public const string Shelf = "";
    public const string Sparkle = "";
    public const string Bolt = "";
    public const string Close = "";
    public const string Add = "";
    public const string Remove = "";
    public const string Bell = "";
    public const string BellOff = "";
    public const string Share = "";
    public const string Download = "";
    public const string Upload = "";
    public const string ArrowDown = "";
    public const string ArrowUp = "";
    public const string ChevronLeft = "";
    public const string ChevronRight = "";
    public const string Warning = "";
    public const string Location = "";
    public const string Calendar = "";
    public const string Drop = "";
    public const string Robot = "";
    public const string Mic = "";
    public const string Camera = "";
    public const string Network = "";
    public const string Coin = "";
    public const string Paint = "";
    public const string Weather = "";
    public const string Info = "";
    public const string Refresh = "";
}

public static class Ui
{
    public static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    public static readonly FontFamily TextFont = new("Segoe UI Variable Text, Segoe UI");
    public static readonly FontFamily DisplayFont = new("Segoe UI Variable Display, Segoe UI");

    public static SolidColorBrush White(double opacity) => Frozen(Color.FromArgb((byte)Math.Round(opacity * 255), 255, 255, 255));
    public static readonly SolidColorBrush Orange = Frozen(Color.FromRgb(255, 149, 0));
    public static readonly SolidColorBrush Green = Frozen(Color.FromRgb(52, 199, 89));
    public static readonly SolidColorBrush Red = Frozen(Color.FromRgb(255, 59, 48));
    public static readonly SolidColorBrush Yellow = Frozen(Color.FromRgb(255, 204, 0));
    public static readonly SolidColorBrush Blue = Frozen(Color.FromRgb(10, 132, 255));
    public static readonly SolidColorBrush Cyan = Frozen(Color.FromRgb(100, 210, 255));
    public static readonly SolidColorBrush Black = Frozen(Colors.Black);

    public static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    public static SolidColorBrush Brush(Color color, double opacity = 1) =>
        Frozen(Color.FromArgb((byte)Math.Round(opacity * color.A), color.R, color.G, color.B));

    public static Color ParseColor(string text, Color fallback)
    {
        try { return (Color)ColorConverter.ConvertFromString(text); }
        catch (FormatException) { return fallback; }
        catch (NullReferenceException) { return fallback; }
    }

    public static TextBlock Text(string text, double size, FontWeight weight, Brush brush, bool monospacedDigits = false)
    {
        var block = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = weight,
            Foreground = brush,
            FontFamily = TextFont,
            TextTrimming = TextTrimming.CharacterEllipsis,
        };
        if (monospacedDigits) Typography.SetNumeralAlignment(block, FontNumeralAlignment.Tabular);
        return block;
    }

    public static TextBlock Icon(string glyph, double size, Brush brush) => new()
    {
        Text = glyph,
        FontFamily = IconFont,
        FontSize = size,
        Foreground = brush,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static StackPanel HStack(double spacing, params UIElement[] children) => Stack(Orientation.Horizontal, spacing, children);
    public static StackPanel VStack(double spacing, params UIElement[] children) => Stack(Orientation.Vertical, spacing, children);

    private static StackPanel Stack(Orientation orientation, double spacing, UIElement[] children)
    {
        var panel = new StackPanel { Orientation = orientation };
        for (var i = 0; i < children.Length; i++)
        {
            if (i > 0 && children[i] is FrameworkElement element)
            {
                var margin = element.Margin;
                element.Margin = orientation == Orientation.Horizontal
                    ? new Thickness(margin.Left + spacing, margin.Top, margin.Right, margin.Bottom)
                    : new Thickness(margin.Left, margin.Top + spacing, margin.Right, margin.Bottom);
            }
            panel.Children.Add(children[i]);
        }
        return panel;
    }

    /// A plain clickable area around `content`, dimming on press like the macOS buttons.
    public static Border Button(UIElement content, Action action, double hoverOpacity = 1, double idleOpacity = 1)
    {
        var border = new Border
        {
            Child = content,
            Background = Brushes.Transparent,
            Cursor = Cursors.Hand,
            Opacity = idleOpacity,
            RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = new ScaleTransform(1, 1),
        };
        var pressed = false;
        border.MouseEnter += (_, _) => border.FadeTo(hoverOpacity, 0.15);
        border.MouseLeave += (_, _) => { pressed = false; border.FadeTo(idleOpacity, 0.15); SetScale(border, 1); };
        border.MouseLeftButtonDown += (_, e) => { pressed = true; SetScale(border, 0.88); e.Handled = true; };
        border.MouseLeftButtonUp += (_, e) =>
        {
            SetScale(border, 1);
            if (!pressed) return;
            pressed = false;
            e.Handled = true;
            action();
        };
        return border;
    }

    private static void SetScale(FrameworkElement element, double scale)
    {
        if (element.RenderTransform is not ScaleTransform transform) return;
        var ease = SpringEase.Of(0.25, 0.7);
        transform.Animate(ScaleTransform.ScaleXProperty, scale, ease);
        transform.Animate(ScaleTransform.ScaleYProperty, scale, ease);
    }

    private static BitmapImage? logo;

    /// The white Lenotch logo (Assets/logo-white.png).
    public static BitmapImage Logo
    {
        get
        {
            if (logo != null) return logo;
            logo = new BitmapImage(new Uri("pack://application:,,,/Assets/logo-white.png"));
            logo.Freeze();
            return logo;
        }
    }

    public const double LogoAspect = 223.0 / 256.0;

    /// The logo, tinted with `color` (the song's colour) when given, keeping its facet shading.
    public static FrameworkElement LogoView(double height, Color? color = null, double opacity = 1)
    {
        var size = new Size(height * LogoAspect, height);
        if (color is not { } tint || tint == Colors.White)
            return new Image { Source = Logo, Width = size.Width, Height = size.Height, Opacity = opacity };
        // Multiply: the logo's alpha as a mask over the colour, plus its grey facets.
        var grid = new Grid { Width = size.Width, Height = size.Height, Opacity = opacity };
        grid.Children.Add(new Border
        {
            Background = Frozen(tint),
            OpacityMask = new ImageBrush(Logo),
        });
        grid.Children.Add(new Image { Source = Logo, Opacity = 0.25 });
        return grid;
    }

    public static string FormatTime(double seconds)
    {
        if (!double.IsFinite(seconds) || seconds < 0) return "0:00";
        var total = (int)Math.Floor(seconds);
        return total >= 3600 ? $"{total / 3600}:{total / 60 % 60:00}:{total % 60:00}" : $"{total / 60}:{total % 60:00}";
    }
}
