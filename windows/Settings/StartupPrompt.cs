using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using Lenotch.Core;

namespace Lenotch.Settings;

/// The first-launch question: start Lenotch with Windows?
public sealed class StartupPrompt : Window
{
    private bool accepted;

    /// Shows the question and returns true for "Start with Windows".
    public static bool Ask()
    {
        var prompt = new StartupPrompt();
        prompt.ShowDialog();
        return prompt.accepted;
    }

    private StartupPrompt()
    {
        Title = "Lenotch";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;
        ShowInTaskbar = true;
        FontFamily = Ui.TextFont;
        UseLayoutRounding = true;

        var text = (Brush)Application.Current.Resources["TextBrush"];
        var secondary = (Brush)Application.Current.Resources["SecondaryTextBrush"];
        var title = Ui.Text("Start Lenotch with Windows?", 17, FontWeights.SemiBold, text);
        var body = Ui.Text("Lenotch opens when you sign in, so the notch is always there. "
                           + "You can change this any time in Settings → General.", 13, FontWeights.Normal, secondary);
        body.TextWrapping = TextWrapping.Wrap;
        body.TextTrimming = TextTrimming.None;
        body.Margin = new Thickness(0, 6, 0, 0);

        var later = new Button { Content = "Not now", Style = (Style)Application.Current.Resources["LenotchButton"], MinWidth = 96, IsCancel = true };
        later.Click += (_, _) => Close();
        var start = new Button
        {
            Content = "Start with Windows",
            Style = (Style)Application.Current.Resources["AccentButton"],
            Margin = new Thickness(8, 0, 0, 0),
            IsDefault = true,
        };
        start.Click += (_, _) => { accepted = true; Close(); };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 20, 0, 0), Children = { later, start } };

        var logo = Ui.LogoView(40);
        logo.VerticalAlignment = VerticalAlignment.Top;
        logo.Margin = new Thickness(0, 2, 16, 0);
        var column = new StackPanel { Width = 320, Children = { title, body, buttons } };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Children = { logo, column } };

        var card = new Border
        {
            Background = (Brush)Application.Current.Resources["WindowBrush"],
            BorderBrush = (Brush)Application.Current.Resources["CardBorderBrush"],
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(22, 20, 22, 18),
            Margin = new Thickness(16),
            Child = row,
            Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 4, Opacity = 0.5 },
        };
        card.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        Content = card;
    }
}
