using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Lenotch.Core;
using Windows.Media;
using Windows.Media.Control;

namespace Lenotch.Services;

public sealed record Track(string Title, string Artist, string Album, double Duration);

public enum RepeatMode { Off, All, One }

/// Now Playing from Windows' media sessions (the same ones the volume flyout shows),
/// filtered to the chosen audio source.
public sealed class MediaService
{
    private readonly AppSettings settings;
    private readonly Dispatcher dispatcher;
    private GlobalSystemMediaTransportControlsSessionManager? manager;
    private GlobalSystemMediaTransportControlsSession? session;
    private readonly DispatcherTimer poll;

    /// Anything shown changed (track, state, artwork, position).
    public event Action? Changed;
    /// A different song started (for the peek).
    public event Action? TrackChanged;

    public Track? Track { get; private set; }
    public bool IsPlaying { get; private set; }
    public BitmapSource? Artwork { get; private set; }
    /// The artwork's most vivid colour, brightened so it reads on black.
    public Color? AccentColor { get; private set; }
    /// nil when the player doesn't offer it.
    public bool? Shuffle { get; private set; }
    public RepeatMode? Repeat { get; private set; }
    /// The last skip went forward (new songs slide in from that side).
    public bool SkippedForward { get; private set; } = true;
    public string? SourceAppId { get; private set; }

    private double position;
    private DateTime positionUpdated = DateTime.UtcNow;
    private double rate = 1;
    private string artworkKey = "";
    /// Ignores timeline updates for a moment after seeking, so the bar doesn't jump back.
    private DateTime seekHold = DateTime.MinValue;

    public MediaService(AppSettings settings)
    {
        this.settings = settings;
        dispatcher = Dispatcher.CurrentDispatcher;
        poll = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        poll.Tick += (_, _) => Refresh();
        settings.Changed += name =>
        {
            if (name == nameof(AppSettings.AudioSource)) PickSession();
        };
    }

    public async Task StartAsync()
    {
        try
        {
            manager = await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        }
        catch (Exception)
        {
            return;
        }
        manager.SessionsChanged += (_, _) => dispatcher.BeginInvoke(() => PickSession());
        manager.CurrentSessionChanged += (_, _) => dispatcher.BeginInvoke(() => PickSession());
        PickSession();
        poll.Start();
    }

    /// Seconds into the song at `now`, extrapolated while playing.
    public double Elapsed(DateTime now)
    {
        var elapsed = IsPlaying ? position + (now - positionUpdated).TotalSeconds * rate : position;
        var duration = Track?.Duration ?? 0;
        return duration > 0 ? Math.Clamp(elapsed, 0, duration) : Math.Max(elapsed, 0);
    }

    private bool Matches(GlobalSystemMediaTransportControlsSession candidate)
    {
        var id = candidate.SourceAppUserModelId?.ToLowerInvariant() ?? "";
        return settings.AudioSource switch
        {
            AudioSource.Spotify => id.Contains("spotify"),
            AudioSource.AppleMusic => id.Contains("applemusic") || id.Contains("appleinc"),
            AudioSource.Browser => new[] { "chrome", "msedge", "firefox", "brave", "opera", "vivaldi", "arc", "zen" }
                .Any(id.Contains),
            _ => true,
        };
    }

    private static bool IsPlayingSession(GlobalSystemMediaTransportControlsSession candidate)
    {
        try
        {
            return candidate.GetPlaybackInfo()?.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
        }
        catch (Exception) { return false; }
    }

    /// Prefers a playing session of the chosen source, then Windows' current one, then any.
    private void PickSession()
    {
        if (manager == null) return;
        IReadOnlyList<GlobalSystemMediaTransportControlsSession> sessions;
        try { sessions = manager.GetSessions(); }
        catch (Exception) { return; }
        var matching = sessions.Where(Matches).ToList();
        GlobalSystemMediaTransportControlsSession? current = null;
        try { current = manager.GetCurrentSession(); } catch (Exception) { }
        var pick = matching.FirstOrDefault(IsPlayingSession)
                   ?? (current != null && Matches(current) ? current : null)
                   ?? matching.FirstOrDefault();
        if (!ReferenceEquals(pick, session)) Attach(pick);
        Refresh();
    }

    private void Attach(GlobalSystemMediaTransportControlsSession? next)
    {
        if (session != null)
        {
            session.MediaPropertiesChanged -= OnMediaProperties;
            session.PlaybackInfoChanged -= OnPlaybackInfo;
            session.TimelinePropertiesChanged -= OnTimeline;
        }
        session = next;
        SourceAppId = next?.SourceAppUserModelId;
        if (session == null) return;
        session.MediaPropertiesChanged += OnMediaProperties;
        session.PlaybackInfoChanged += OnPlaybackInfo;
        session.TimelinePropertiesChanged += OnTimeline;
    }

    private void OnMediaProperties(GlobalSystemMediaTransportControlsSession sender, MediaPropertiesChangedEventArgs args) =>
        dispatcher.BeginInvoke(() => Refresh());

    private void OnPlaybackInfo(GlobalSystemMediaTransportControlsSession sender, PlaybackInfoChangedEventArgs args) =>
        dispatcher.BeginInvoke(() =>
        {
            // Another app may have started playing: follow it.
            if (!IsPlayingSession(sender)) Refresh(); else PickSession();
        });

    private void OnTimeline(GlobalSystemMediaTransportControlsSession sender, TimelinePropertiesChangedEventArgs args) =>
        dispatcher.BeginInvoke(() => Refresh());

    private bool refreshing;

    private async void Refresh()
    {
        if (refreshing) return;
        refreshing = true;
        try
        {
            await RefreshCore();
        }
        catch (Exception)
        {
            // Sessions vanish when their app quits; the next pick tidies up.
        }
        finally
        {
            refreshing = false;
        }
    }

    private async Task RefreshCore()
    {
        // A paused session while another app plays: switch to the playing one.
        if (manager != null && (session == null || !IsPlayingSession(session)))
        {
            var playing = manager.GetSessions().Where(Matches).FirstOrDefault(IsPlayingSession);
            if (playing != null && !ReferenceEquals(playing, session)) Attach(playing);
        }
        if (session == null)
        {
            SetTrack(null);
            IsPlaying = false;
            Changed?.Invoke();
            return;
        }

        var info = session.GetPlaybackInfo();
        IsPlaying = info.PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing;
        rate = info.PlaybackRate is { } r && r > 0 ? r : 1;
        Shuffle = info.Controls.IsShuffleEnabled ? info.IsShuffleActive ?? false : null;
        Repeat = info.Controls.IsRepeatEnabled
            ? info.AutoRepeatMode switch
            {
                MediaPlaybackAutoRepeatMode.Track => RepeatMode.One,
                MediaPlaybackAutoRepeatMode.List => RepeatMode.All,
                _ => RepeatMode.Off,
            }
            : null;

        var timeline = session.GetTimelineProperties();
        var duration = (timeline.EndTime - timeline.StartTime).TotalSeconds;
        if (DateTime.UtcNow > seekHold)
        {
            position = (timeline.Position - timeline.StartTime).TotalSeconds;
            positionUpdated = timeline.LastUpdatedTime.UtcDateTime;
            // Some players never update the timestamp: don't extrapolate from far in the past.
            if (positionUpdated > DateTime.UtcNow || (DateTime.UtcNow - positionUpdated).TotalSeconds > Math.Max(duration, 1))
                positionUpdated = DateTime.UtcNow;
        }

        var properties = await session.TryGetMediaPropertiesAsync();
        if (properties == null) return;
        var title = properties.Title ?? "";
        if (string.IsNullOrWhiteSpace(title))
        {
            SetTrack(null);
            Changed?.Invoke();
            return;
        }
        SetTrack(new Track(title, properties.Artist ?? "", properties.AlbumTitle ?? "", Math.Max(duration, 0)));

        var key = title + "\u0001" + properties.Artist;
        if (key != artworkKey)
        {
            artworkKey = key;
            var image = await LoadArtwork(properties.Thumbnail);
            // The song may have changed again while loading.
            if (artworkKey == key)
            {
                Artwork = image;
                AccentColor = image != null ? ArtworkColor.Accent(image) : null;
            }
        }
        Changed?.Invoke();
    }

    private void SetTrack(Track? track)
    {
        var old = Track;
        Track = track;
        if (track == null)
        {
            Artwork = null;
            AccentColor = null;
            artworkKey = "";
            return;
        }
        if (old == null || old.Title != track.Title || old.Artist != track.Artist) TrackChanged?.Invoke();
    }

    private static async Task<BitmapSource?> LoadArtwork(Windows.Storage.Streams.IRandomAccessStreamReference? reference)
    {
        if (reference == null) return null;
        try
        {
            using var stream = await reference.OpenReadAsync();
            using var source = stream.AsStream();
            var memory = new MemoryStream();
            await source.CopyToAsync(memory);
            memory.Position = 0;
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 300;
            image.StreamSource = memory;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch (Exception)
        {
            return null;
        }
    }

    // MARK: Controls

    public async void TogglePlayPause()
    {
        if (session == null) return;
        IsPlaying = !IsPlaying;
        position = Elapsed(DateTime.UtcNow);
        positionUpdated = DateTime.UtcNow;
        Changed?.Invoke();
        try { await session.TryTogglePlayPauseAsync(); } catch (Exception) { }
    }

    public async void Next()
    {
        if (session == null) return;
        SkippedForward = true;
        try { await session.TrySkipNextAsync(); } catch (Exception) { }
    }

    public async void Previous()
    {
        if (session == null) return;
        SkippedForward = false;
        try { await session.TrySkipPreviousAsync(); } catch (Exception) { }
    }

    public async void Seek(double seconds)
    {
        if (session == null) return;
        position = seconds;
        positionUpdated = DateTime.UtcNow;
        seekHold = DateTime.UtcNow.AddSeconds(1.5);
        Changed?.Invoke();
        try { await session.TryChangePlaybackPositionAsync(TimeSpan.FromSeconds(seconds).Ticks); } catch (Exception) { }
    }

    public async void ToggleShuffle()
    {
        if (session == null || Shuffle is not { } shuffle) return;
        Shuffle = !shuffle;
        Changed?.Invoke();
        try { await session.TryChangeShuffleActiveAsync(!shuffle); } catch (Exception) { }
    }

    public async void CycleRepeat()
    {
        if (session == null || Repeat is not { } repeat) return;
        var next = repeat switch { RepeatMode.Off => RepeatMode.All, RepeatMode.All => RepeatMode.One, _ => RepeatMode.Off };
        Repeat = next;
        Changed?.Invoke();
        var mode = next switch
        {
            RepeatMode.All => MediaPlaybackAutoRepeatMode.List,
            RepeatMode.One => MediaPlaybackAutoRepeatMode.Track,
            _ => MediaPlaybackAutoRepeatMode.None,
        };
        try { await session.TryChangeAutoRepeatModeAsync(mode); } catch (Exception) { }
    }

    /// Brings the playing app to the front.
    public void OpenSourceApp()
    {
        var id = SourceAppId;
        if (string.IsNullOrEmpty(id)) return;
        try
        {
            if (id.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                var name = Path.GetFileNameWithoutExtension(id);
                var process = Process.GetProcessesByName(name).FirstOrDefault(p => p.MainWindowHandle != IntPtr.Zero);
                if (process != null) WindowActivation.BringToFront(process.MainWindowHandle);
                return;
            }
            Process.Start(new ProcessStartInfo("explorer.exe", $"shell:AppsFolder\\{id}") { UseShellExecute = true });
        }
        catch (Exception) { }
    }
}

/// The artwork's most vivid colour, brightened so it reads on black. Averages the
/// pixels of a tiny thumbnail, weighting each by its saturation.
public static class ArtworkColor
{
    public static Color? Accent(BitmapSource image)
    {
        try
        {
            const int side = 24;
            var scaled = new TransformedBitmap(image, new ScaleTransform(side / (double)image.PixelWidth, side / (double)image.PixelHeight));
            var converted = new FormatConvertedBitmap(scaled, PixelFormats.Bgra32, null, 0);
            int width = converted.PixelWidth, height = converted.PixelHeight;
            var pixels = new byte[width * height * 4];
            converted.CopyPixels(pixels, width * 4, 0);
            double red = 0, green = 0, blue = 0, total = 0;
            for (var i = 0; i < width * height; i++)
            {
                double b = pixels[i * 4] / 255.0, g = pixels[i * 4 + 1] / 255.0, r = pixels[i * 4 + 2] / 255.0;
                double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b));
                var saturation = max > 0 ? (max - min) / max : 0;
                // Favour saturated, not-too-dark pixels; keep a small floor so grey art still averages.
                var weight = 0.05 + saturation * saturation * max;
                red += r * weight;
                green += g * weight;
                blue += b * weight;
                total += weight;
            }
            if (total <= 0) return null;
            var (h, s, v) = ToHsv(red / total, green / total, blue / total);
            return FromHsv(h, Math.Min(s * 1.2, 0.85), Math.Max(v, 0.85));
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static (double h, double s, double v) ToHsv(double r, double g, double b)
    {
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b)), delta = max - min;
        double h = 0;
        if (delta > 0)
        {
            if (max == r) h = (g - b) / delta % 6;
            else if (max == g) h = (b - r) / delta + 2;
            else h = (r - g) / delta + 4;
            h /= 6;
            if (h < 0) h += 1;
        }
        return (h, max > 0 ? delta / max : 0, max);
    }

    private static Color FromHsv(double h, double s, double v)
    {
        var i = (int)Math.Floor(h * 6);
        var f = h * 6 - i;
        double p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
        var (r, g, b) = (i % 6) switch
        {
            0 => (v, t, p),
            1 => (q, v, p),
            2 => (p, v, t),
            3 => (p, q, v),
            4 => (t, p, v),
            _ => (v, p, q),
        };
        return Color.FromRgb((byte)(r * 255), (byte)(g * 255), (byte)(b * 255));
    }
}

internal static class WindowActivation
{
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int command);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    public static void BringToFront(IntPtr hwnd)
    {
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9); // SW_RESTORE
        SetForegroundWindow(hwnd);
    }
}
