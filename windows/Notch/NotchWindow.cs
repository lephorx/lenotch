using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Lenotch.Core;
using Lenotch.Services;
using Lenotch.Views;

namespace Lenotch.Notch;

/// One screen's notch: a transparent, click-through, always-on-top window at the
/// top centre of the screen with the black notch inside. Opens on hover or click,
/// and when files are dragged onto it.
public sealed class NotchWindow : Window
{
    private const double CloseDelay = 0.2;
    private const double PeekDuration = 3;
    private const double AlarmDuration = 10;

    private readonly NotchModel model;
    private readonly Grid root = new();
    private readonly NotchSurface surface = new();
    private readonly UsageTooltip tooltip;
    private readonly DispatcherTimer poll = new() { Interval = TimeSpan.FromMilliseconds(30) };
    private readonly DispatcherTimer pending = new();
    private readonly DispatcherTimer peekEnd = new();
    private readonly DispatcherTimer alarmEnd = new() { Interval = TimeSpan.FromSeconds(AlarmDuration) };
    private Action? pendingAction;
    private NotchContentView? content;
    private string contentKey = "";
    private Size shownSize;
    private bool shownExpanded;
    private double shownOpenness;
    private string privacyKey = "";
    private IntPtr hwnd;
    private System.Windows.Forms.Screen screen;
    private double scale = 1;
    private (int x, int y) originPixels;
    /// Shared, so the X on any screen silences it.
    private static MediaPlayer? alarm;

    /// Opened with the keyboard shortcut: stays open until the shortcut, a click
    /// elsewhere, or the pointer entering and then leaving the notch.
    private bool openedByKeyboard;
    /// After the notch was closed under the pointer, hovering doesn't reopen it until
    /// the pointer has left the notch once.
    private bool hoverOpenBlocked;
    private bool wasButtonDown;
    private bool suppressed;
    private double wheelTravel;
    private DateTime lastWheel = DateTime.MinValue;
    private bool wheelHandled;

    public NotchModel Model => model;
    /// Debug builds' "hold": stays open whatever the pointer does.
    public bool DebugHold { get; set; }
    public System.Windows.Forms.Screen Screen => screen;

    public NotchWindow(AppServices services, System.Windows.Forms.Screen screen)
    {
        this.screen = screen;
        model = new NotchModel(new NotchGeometry(ScreenWidthDip(screen)), services);
        tooltip = new UsageTooltip(model);

        Title = "Lenotch";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        SizeToContent = SizeToContent.Manual;
        Left = -30000;
        Top = -30000;
        UseLayoutRounding = true;
        TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
        TextOptions.SetTextRenderingMode(this, TextRenderingMode.ClearType);

        root.HorizontalAlignment = HorizontalAlignment.Left;
        root.VerticalAlignment = VerticalAlignment.Top;
        root.Children.Add(tooltip);
        root.Children.Add(surface);
        Content = root;
        surface.AllowDrop = true;
        ApplyGeometry();

        surface.MouseLeftButtonDown += (_, e) =>
        {
            if (model.IsOpen || model.IsShowingIntro || model.IsTimerFinished) return;
            CancelPending();
            SetState(NotchModel.NotchState.Open);
            e.Handled = true;
        };
        // Dragging files onto the closed notch opens the shelf.
        surface.DragEnter += (_, e) =>
        {
            if (model.IsOpen || !e.Data.GetDataPresent(DataFormats.FileDrop)) return;
            if (!model.Settings.OpenShelfOnDrag || !model.Settings.ShowsShelfTab) return;
            CancelPending();
            model.Select(NotchPage.Shelf);
            SetState(NotchModel.NotchState.Open);
        };

        pending.Tick += (_, _) =>
        {
            pending.Stop();
            var action = pendingAction;
            pendingAction = null;
            action?.Invoke();
        };
        peekEnd.Tick += (_, _) => { peekEnd.Stop(); model.IsPeeking = false; Update(); };
        alarmEnd.Tick += (_, _) => StopAlarm();
        poll.Tick += (_, _) => Poll();

        model.Changed += Update;
        model.PageChanged += Update;
        model.UsageHoverChanged += PositionTooltip;
        model.StopAlarm = StopAlarm;
        model.Share = paths => ShareSheet.Share(hwnd, paths);
        model.ChooseAndShare = () => ShareSheet.ChooseAndShare(hwnd);

        SourceInitialized += (_, _) =>
        {
            hwnd = new WindowInteropHelper(this).Handle;
            Native.MakeToolWindow(hwnd);
            HwndSource.FromHwnd(hwnd)?.AddHook(WndProc);
            Place();
        };
        DpiChanged += (_, _) => Dispatcher.BeginInvoke(Place);
        Loaded += (_, _) => poll.Start();
        Closed += (_, _) =>
        {
            poll.Stop();
            alarm?.Stop();
        };
        Update();
    }

    private static double ScreenWidthDip(System.Windows.Forms.Screen screen)
    {
        var monitor = Native.MonitorFromPoint(new Native.POINT { X = screen.Bounds.Left + screen.Bounds.Width / 2, Y = screen.Bounds.Top + 1 }, 2);
        return screen.Bounds.Width / Native.ScaleOf(monitor);
    }

    /// Moves the window to the top centre of its screen (in physical pixels).
    public void Place(System.Windows.Forms.Screen? newScreen = null)
    {
        if (newScreen != null) screen = newScreen;
        var bounds = screen.Bounds;
        var monitor = Native.MonitorFromPoint(new Native.POINT { X = bounds.Left + bounds.Width / 2, Y = bounds.Top + 1 }, 2);
        scale = Native.ScaleOf(monitor);
        var widthDip = bounds.Width / scale;
        if (Math.Abs(widthDip - model.Geometry.ScreenWidth) > 0.5)
        {
            model.Geometry = new NotchGeometry(widthDip);
            ApplyGeometry();
        }
        var size = model.Geometry.WindowSize;
        var widthPx = (int)Math.Ceiling(size.Width * scale);
        var heightPx = (int)Math.Ceiling(size.Height * scale);
        originPixels = (bounds.Left + (bounds.Width - widthPx) / 2, bounds.Top);
        if (hwnd != IntPtr.Zero)
            Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, originPixels.x, originPixels.y, widthPx, heightPx,
                Native.SWP_NOACTIVATE | Native.SWP_SHOWWINDOW);
        Update();
    }

    private void ApplyGeometry()
    {
        var size = model.Geometry.WindowSize;
        root.Width = size.Width;
        root.Height = size.Height;
        Width = size.Width;
        Height = size.Height;
    }

    /// Keeps the notch above other always-on-top windows.
    public void RaiseToTop()
    {
        if (hwnd == IntPtr.Zero || suppressed) return;
        Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
    }

    /// Hidden while an app is full screen on this display.
    public void SetSuppressed(bool value)
    {
        if (value == suppressed) return;
        suppressed = value;
        if (value)
        {
            CancelPending();
            if (model.IsOpen) SetState(NotchModel.NotchState.Closed);
            Hide();
        }
        else
        {
            Show();
            Place();
        }
    }

    // MARK: - Rendering the model

    /// Brings the notch's size, shape and content in line with the model.
    public void Update()
    {
        var size = model.CurrentSize;
        var expanded = model.IsExpanded;
        if (size != shownSize || expanded != shownExpanded)
        {
            var spring = SpringFor();
            shownSize = size;
            shownExpanded = expanded;
            surface.Animate(NotchSurface.BodyWidthProperty, size.Width, spring);
            surface.Animate(NotchSurface.BodyHeightProperty, size.Height, spring);
            surface.Animate(NotchSurface.TopRadiusProperty, expanded ? NotchGeometry.OpenTopRadius : NotchGeometry.ClosedTopRadius, spring);
            surface.Animate(NotchSurface.BottomRadiusProperty, expanded ? NotchGeometry.OpenBottomRadius : NotchGeometry.ClosedBottomRadius, spring);
        }

        var glowing = model.IsOpen && model.VisiblePage == NotchPage.Player && model.Settings.ShowMusic
                      && model.Settings.BackgroundFollowsMusic;
        surface.MusicColor = model.AccentColor;
        var openness = glowing && model.AccentColor != null ? 1 : 0;
        if (openness != shownOpenness)
        {
            shownOpenness = openness;
            surface.Animate(NotchSurface.OpennessProperty, openness, 0.6);
        }

        UpdatePrivacy();

        var key = ContentKey();
        if (key != contentKey)
        {
            contentKey = key;
            SwapContent(MakeContent(key), key);
        }
        else
        {
            content?.Refresh();
        }
        if (content is ExpandedView open)
        {
            var openSize = model.OpenSizeFor(model.VisiblePage);
            open.Width = openSize.Width;
            open.Height = openSize.Height;
        }
        PositionTooltip();
    }

    /// The bounce that matches what changed, like the macOS notch.
    private SpringEase SpringFor()
    {
        if (model.IsShowingIntro) return SpringEase.Of(0.5, 0.78);
        if (model.IsTimerFinished && !model.IsOpen) return SpringEase.Of(0.5, 0.62);
        if (model.IsPeeking && !model.IsOpen) return SpringEase.Of(0.45, 0.8);
        return model.IsOpen ? Motion.PageSpring : Motion.NotchSpring;
    }

    private string ContentKey()
    {
        if (model.IsShowingIntro) return "intro";
        if (model.IsOpen) return "open";
        if (model.IsTimerFinished) return "timerDone";
        if (model.IsPeeking && model.Media.Track != null) return "peek";
        if (model.Timer.IsActive) return "timer";
        if (model.ShowsLiveActivity) return "live";
        if (model.ShowsNetwork) return "network";
        if (model.ShowsCrypto) return "crypto";
        return "none";
    }

    private NotchContentView? MakeContent(string key) => key switch
    {
        "intro" => new IntroView(() => { model.IsShowingIntro = false; Update(); }),
        "open" => new ExpandedView(model) { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top },
        "timerDone" => new TimerDoneView(model),
        "peek" => new PeekView(model),
        "timer" => new TimerLiveView(model),
        "live" => new LiveActivityView(model),
        "network" => new NetworkSpeedView(model),
        "crypto" => new CryptoTickerView(model),
        _ => null,
    };

    private void SwapContent(NotchContentView? next, string key)
    {
        var old = content;
        content = next;
        if (old != null)
        {
            old.IsHitTestVisible = false;
            old.FadeTo(0, key == "open" ? 0.1 : 0.18, () => surface.Content.Children.Remove(old));
        }
        if (next == null) return;
        surface.Content.Children.Add(next);
        next.Opacity = 0;
        next.Animate(OpacityProperty, 1, 0.25, null, old != null ? 0.06 : 0);
        if (key is "open" or "peek" or "timerDone")
        {
            // Grows out of the notch, anchored at the top.
            var grow = new ScaleTransform(key == "open" ? 0.92 : 0.95, key == "open" ? 0.92 : 0.95);
            next.RenderTransformOrigin = new Point(0.5, 0);
            next.RenderTransform = grow;
            grow.Animate(ScaleTransform.ScaleXProperty, 1, SpringFor());
            grow.Animate(ScaleTransform.ScaleYProperty, 1, SpringFor());
        }
    }

    /// Orange for the microphone, green for the camera, both (left to right) for a video call.
    private void UpdatePrivacy()
    {
        var colors = new List<Color>();
        if (model.ShowsPrivacy)
        {
            if (model.Privacy.IsMicOn) colors.Add(Colors.Orange);
            if (model.Privacy.IsCameraOn) colors.Add(Color.FromRgb(52, 199, 89));
        }
        var key = string.Join(",", colors) + model.Settings.PrivacyGlow;
        if (key == privacyKey) return;
        privacyKey = key;
        surface.Outline.Set(colors, model.Settings.PrivacyGlow);
    }

    private void PositionTooltip()
    {
        var top = model.IsOpen ? model.CurrentSize.Height : 0;
        tooltip.Width = root.Width;
        tooltip.Height = root.Height;
        tooltip.Update(top, root.Width);
    }

    // MARK: - State

    public void SetState(NotchModel.NotchState state)
    {
        if (model.State == state) return;
        model.State = state;
        if (state == NotchModel.NotchState.Open)
        {
            peekEnd.Stop();
            model.IsPeeking = false;
            StopAlarm(update: false);
        }
        else
        {
            openedByKeyboard = false;
            model.SetUsageHover(null);
            model.IsTimerPanelVisible = false;
        }
        Update();
    }

    /// Keyboard shortcut: opens or closes the notch.
    public void ToggleOpen()
    {
        if (model.IsShowingIntro || suppressed) return;
        CancelPending();
        if (model.IsOpen)
        {
            SetState(NotchModel.NotchState.Closed);
        }
        else
        {
            openedByKeyboard = true;
            SetState(NotchModel.NotchState.Open);
        }
    }

    /// Keyboard shortcut: closes an open notch and briefly shows the current song,
    /// or hides the peek if it's already showing.
    public void Peek()
    {
        if (model.IsPeeking)
        {
            peekEnd.Stop();
            model.IsPeeking = false;
            Update();
            return;
        }
        if (model.IsShowingIntro || model.Media.Track == null) return;
        if (model.IsOpen)
        {
            CancelPending();
            SetState(NotchModel.NotchState.Closed);
            // A pointer still over the notch must not reopen it over the peek.
            hoverOpenBlocked = true;
        }
        ShowPeek(PeekDuration);
    }

    /// Shows the new song in the closed notch, if turned on. It never closes an open
    /// notch, and a showing peek just stays up longer.
    public void PeekForTrackChange()
    {
        if (!model.Settings.PeekOnTrackChange || model.IsOpen || model.IsShowingIntro || model.Media.Track == null || suppressed) return;
        ShowPeek(model.Settings.TrackPeekDuration);
    }

    private void ShowPeek(double seconds)
    {
        peekEnd.Stop();
        model.IsPeeking = true;
        peekEnd.Interval = TimeSpan.FromSeconds(seconds);
        peekEnd.Start();
        Update();
    }

    public void PlayIntro()
    {
        if (model.IsShowingIntro) return;
        CancelPending();
        SetState(NotchModel.NotchState.Closed);
        peekEnd.Stop();
        model.IsPeeking = false;
        model.IsShowingIntro = true;
        contentKey = "";
        Update();
        // Never leave an expanded, inert notch behind.
        After(4, () =>
        {
            if (!model.IsShowingIntro) return;
            model.IsShowingIntro = false;
            Update();
        });
    }

    /// The notch folds down with the timer symbol, 0:00 and an X. The alarm rings
    /// for 10 seconds (unless the timer was silent) or until the X is clicked.
    public void TimerFinished()
    {
        if (model.IsShowingIntro) return;
        if (model.IsOpen)
        {
            CancelPending();
            SetState(NotchModel.NotchState.Closed);
        }
        peekEnd.Stop();
        model.IsPeeking = false;
        model.IsTimerFinished = true;
        alarmEnd.Stop();
        alarmEnd.Start();
        Update();
    }

    /// Only one screen rings, even with a notch on every display.
    public void RingAlarm()
    {
        alarm?.Stop();
        alarm = null;
        if (model.Timer.LastWasSilent) return;
        var file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "Media", "Alarm01.wav");
        if (File.Exists(file))
        {
            alarm = new MediaPlayer();
            alarm.Open(new Uri(file));
            var player = alarm;
            player.MediaEnded += (_, _) => { player.Position = TimeSpan.Zero; player.Play(); };
            player.Play();
        }
        else
        {
            System.Media.SystemSounds.Exclamation.Play();
        }
    }

    private void StopAlarm() => StopAlarm(update: true);

    private void StopAlarm(bool update)
    {
        alarmEnd.Stop();
        alarm?.Stop();
        alarm = null;
        if (!model.IsTimerFinished) return;
        model.IsTimerFinished = false;
        // A pointer still over the notch shouldn't open it right after the card folds up.
        hoverOpenBlocked = true;
        if (update) Update();
    }

    // MARK: - Pointer

    private Point CursorInWindow()
    {
        Native.GetCursorPos(out var cursor);
        return new Point((cursor.X - originPixels.x) / scale, (cursor.Y - originPixels.y) / scale);
    }

    /// The notch's rectangle in the window, for a given size.
    private Rect RectFor(Size size) => new((root.Width - size.Width) / 2, 0, size.Width, size.Height);

    private void Poll()
    {
        if (suppressed || model.IsShowingIntro || hwnd == IntPtr.Zero) return;
        var point = CursorInWindow();
        var buttonDown = Native.IsLeftButtonDown;
        var pressed = buttonDown && !wasButtonDown;
        wasButtonDown = buttonDown;

        if (!model.IsOpen)
        {
            // While the alarm rings the card stays down; only its X (or the timeout) ends it.
            if (model.IsTimerFinished) return;
            var hot = RectFor(model.CurrentSize);
            // Grow the hot zone a little so the very top edge of the screen counts.
            hot = new Rect(hot.X - 6, hot.Y - 4, hot.Width + 12, hot.Height + 6);
            if (!hot.Contains(point))
            {
                CancelPending();
                hoverOpenBlocked = false;
                return;
            }
            if (model.Settings.OpenMode == OpenMode.Hover && !hoverOpenBlocked && !buttonDown)
                Schedule(model.Settings.HoverDelay, () => SetState(NotchModel.NotchState.Open));
            return;
        }

        if (DebugHold) return;
        var size = model.CurrentSize;
        var area = RectFor(size);
        area.Inflate(8, 8);
        var inside = area.Contains(point);
        if (openedByKeyboard)
        {
            // Keep it open until the pointer has been inside once, or the user clicks elsewhere.
            if (inside) openedByKeyboard = false;
            else if (pressed)
            {
                openedByKeyboard = false;
                SetState(NotchModel.NotchState.Closed);
            }
            return;
        }
        // Stay open while a button is held, so scrubbing and drags in and out don't cut off.
        if (inside || model.IsInteracting || buttonDown) CancelPending();
        else Schedule(CloseDelay, () => SetState(NotchModel.NotchState.Closed));
    }

    private void Schedule(double seconds, Action action)
    {
        if (pendingAction != null) return;
        pendingAction = action;
        pending.Interval = TimeSpan.FromSeconds(Math.Max(seconds, 0.01));
        pending.Start();
    }

    private void CancelPending()
    {
        pending.Stop();
        pendingAction = null;
    }

    private static void After(double seconds, Action action)
    {
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) => { timer.Stop(); action(); };
        timer.Start();
    }

    // MARK: - Messages

    private IntPtr WndProc(IntPtr window, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        switch (message)
        {
            case Native.WM_MOUSEACTIVATE:
                // Clicks never take focus away from the app being used.
                handled = true;
                return new IntPtr(Native.MA_NOACTIVATE);
            case Native.WM_MOUSEHWHEEL:
                handled = HandleHorizontalWheel((short)((wParam.ToInt64() >> 16) & 0xFFFF));
                break;
        }
        return IntPtr.Zero;
    }

    /// Sideways scrolling (tilt wheel or two-finger swipe) switches tabs, once per gesture.
    private bool HandleHorizontalWheel(int delta)
    {
        if (!model.IsOpen) return false;
        // Over the calendar or a full shelf, scrolling scrolls those instead.
        if (Mouse.DirectlyOver is DependencyObject over && IsInside<CalendarPanel>(over)) return false;
        if (model.VisiblePage == NotchPage.Shelf && model.Services.Shelf.Items.Count > 5) return false;
        var now = DateTime.UtcNow;
        if ((now - lastWheel).TotalSeconds > 0.35)
        {
            wheelTravel = 0;
            wheelHandled = false;
        }
        lastWheel = now;
        wheelTravel += delta;
        if (!wheelHandled && Math.Abs(wheelTravel) >= 120)
        {
            wheelHandled = true;
            model.SelectPage(wheelTravel > 0 ? 1 : -1);
        }
        return true;
    }

    private static bool IsInside<T>(DependencyObject element) where T : DependencyObject
    {
        for (var current = element; current != null; current = VisualTreeHelper.GetParent(current) ?? LogicalTreeHelper.GetParent(current))
            if (current is T) return true;
        return false;
    }

    private static class Mouse
    {
        public static IInputElement? DirectlyOver => System.Windows.Input.Mouse.DirectlyOver;
    }
}
