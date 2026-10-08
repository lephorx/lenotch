using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Lenotch.Notch;

namespace Lenotch;

/// Drives the notch from the command line while testing (also in CI), like the macOS
/// debug hooks. Only active when LENOTCH_DEBUG_DIR is set. Write a command into
/// $LENOTCH_DEBUG_DIR/lenotch-cmd.txt:
///   open | hold (open and stay open) | release | close | toggle | peek | intro
///   page N | timer SECONDS | timerpanel | settings [section] | ai on|off
///   snap NAME (renders every notch window, and Settings if open, to snap-NAME*.png)
/// The state is written to lenotch-debug.txt next to it.
public sealed class DebugHooks
{
    private readonly string folder;
    private readonly Func<IReadOnlyList<NotchWindow>> notches;
    private readonly Func<Window?> settingsWindow;
    private readonly Action<string?> openSettings;

    public static DebugHooks? Start(Func<IReadOnlyList<NotchWindow>> notches, Func<Window?> settingsWindow, Action<string?> openSettings)
    {
        var folder = Environment.GetEnvironmentVariable("LENOTCH_DEBUG_DIR");
        if (string.IsNullOrEmpty(folder)) return null;
        Directory.CreateDirectory(folder);
        return new DebugHooks(folder, notches, settingsWindow, openSettings);
    }

    private DebugHooks(string folder, Func<IReadOnlyList<NotchWindow>> notches, Func<Window?> settingsWindow, Action<string?> openSettings)
    {
        this.folder = folder;
        this.notches = notches;
        this.settingsWindow = settingsWindow;
        this.openSettings = openSettings;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        timer.Tick += (_, _) => Tick();
        timer.Start();
    }

    private void Tick()
    {
        var file = Path.Combine(folder, "lenotch-cmd.txt");
        if (File.Exists(file))
        {
            string text;
            try
            {
                text = File.ReadAllText(file);
                File.Delete(file);
            }
            catch (IOException) { return; }
            foreach (var line in text.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0))
            {
                try { Run(line.Split(' ', StringSplitOptions.RemoveEmptyEntries)); }
                catch (Exception error) { App.Log($"debug command '{line}' failed: {error}"); }
            }
        }
        var first = notches().FirstOrDefault();
        if (first == null) return;
        var model = first.Model;
        var status = $"state={model.State} intro={model.IsShowingIntro} page={model.VisiblePage}/{model.Pages.Count} "
                     + $"size={model.CurrentSize} track={model.Media.Track?.Title ?? "-"} playing={model.Media.IsPlaying} "
                     + $"screens={notches().Count} settings={(settingsWindow() != null)}\n";
        try { File.WriteAllText(Path.Combine(folder, "lenotch-debug.txt"), status); } catch (IOException) { }
    }

    private void Run(string[] parts)
    {
        var all = notches();
        var notch = all.FirstOrDefault(n => n.Screen.Primary) ?? all.FirstOrDefault();
        if (notch == null) return;
        switch (parts[0])
        {
            case "open": notch.SetState(NotchModel.NotchState.Open); break;
            case "hold": notch.DebugHold = true; notch.SetState(NotchModel.NotchState.Open); break;
            case "release": notch.DebugHold = false; break;
            case "close": notch.SetState(NotchModel.NotchState.Closed); break;
            case "toggle": notch.ToggleOpen(); break;
            case "peek": notch.Peek(); break;
            case "intro": notch.PlayIntro(); break;
            case "page" when parts.Length == 2 && int.TryParse(parts[1], out var index):
                var pages = notch.Model.Pages;
                if (index >= 0 && index < pages.Count) notch.Model.Select(pages[index]);
                break;
            case "timer" when parts.Length == 2 && double.TryParse(parts[1], out var seconds):
                notch.Model.Timer.Start(seconds, notch.Model.Settings.TimerSilent);
                break;
            case "timerpanel": notch.Model.ToggleTimerPanel(); break;
            case "ai" when parts.Length == 2: notch.Model.Settings.AIUsageEnabled = parts[1] == "on"; break;
            case "settings": openSettings(parts.Length > 1 ? parts[1] : null); break;
            case "snap":
                var name = parts.Length > 1 ? parts[1] : "notch";
                for (var i = 0; i < all.Count; i++)
                    Snap(all[i].Content as FrameworkElement, $"snap-{name}{(i == 0 ? "" : $"-{i}")}.png", black: false);
                if (settingsWindow() is { Content: FrameworkElement settings }) Snap(settings, $"snap-{name}-settings.png", black: true);
                // Anything else that's open, like the start-with-Windows question.
                var others = Application.Current.Windows.OfType<Window>()
                    .Where(w => w is not NotchWindow && w != settingsWindow() && w.IsVisible).ToList();
                for (var i = 0; i < others.Count; i++)
                    Snap(others[i].Content as FrameworkElement, $"snap-{name}-window{i}.png", black: true);
                break;
        }
    }

    /// Renders a window's content offscreen (works without a visible desktop). The notch
    /// is drawn over grey so its transparent surroundings show.
    private void Snap(FrameworkElement? element, string fileName, bool black)
    {
        if (element == null || element.ActualWidth <= 0 || element.ActualHeight <= 0) return;
        const double scale = 2;
        var width = (int)Math.Ceiling(element.ActualWidth * scale);
        var height = (int)Math.Ceiling(element.ActualHeight * scale);
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            var bounds = new Rect(0, 0, element.ActualWidth, element.ActualHeight);
            context.PushTransform(new ScaleTransform(scale, scale));
            context.DrawRectangle(black ? Brushes.Black : new SolidColorBrush(Color.FromRgb(120, 128, 140)), null, bounds);
            // Framed to the element's own bounds, not its content's (which would push narrow notches left).
            context.DrawRectangle(new VisualBrush(element) { Viewbox = bounds, ViewboxUnits = BrushMappingMode.Absolute, Stretch = Stretch.Fill }, null, bounds);
            context.Pop();
        }
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(Path.Combine(folder, fileName));
        encoder.Save(stream);
    }
}
