using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Threading;
using Lenotch.Core;

namespace Lenotch.Services;

public sealed record CalendarEvent(string Id, string Title, DateTime Start, DateTime End, bool IsAllDay, Color Color)
{
    public bool IsHappening(DateTime now) => Start <= now && now < End;
}

/// The calendar in the notch. Windows doesn't share its calendars with desktop apps,
/// so events come from iCalendar feeds (Outlook, Google and iCloud all publish one).
public sealed class CalendarService
{
    private readonly AppSettings settings;
    private readonly Dictionary<Guid, List<IcsEvent>> feeds = new();
    private DateTime lastFetch = DateTime.MinValue;
    private bool isFetching;

    public event Action? Changed;
    public DateTime SelectedDay { get; private set; } = DateTime.Today;
    /// The first day of the month the grid shows.
    public DateTime DisplayedMonth { get; private set; } = new(DateTime.Today.Year, DateTime.Today.Month, 1);
    public List<CalendarEvent> Events { get; private set; } = new();
    /// Up to three event colours per day of the displayed grid.
    public Dictionary<DateTime, List<Color>> MonthDots { get; private set; } = new();
    public bool HasFeeds => settings.CalendarFeeds.Any(f => f.Enabled && !string.IsNullOrWhiteSpace(f.Url));

    public CalendarService(AppSettings settings)
    {
        this.settings = settings;
        // Feeds are edited as they're typed: download once the typing stops.
        var settle = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
        settle.Tick += (_, _) =>
        {
            settle.Stop();
            lastFetch = DateTime.MinValue;
            _ = Refresh();
        };
        settings.Changed += name =>
        {
            if (name != nameof(AppSettings.CalendarFeeds)) return;
            settle.Stop();
            settle.Start();
        };
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        timer.Tick += (_, _) => _ = Refresh();
        timer.Start();
    }

    public void Select(DateTime day)
    {
        SelectedDay = day.Date;
        var month = new DateTime(day.Year, day.Month, 1);
        if (month != DisplayedMonth) DisplayedMonth = month;
        Recompute();
    }

    public void ShowMonth(int offset)
    {
        DisplayedMonth = DisplayedMonth.AddMonths(offset);
        Recompute();
    }

    /// Six weeks starting on the week of the month's first day.
    public static List<DateTime> GridDays(DateTime month)
    {
        var first = new DateTime(month.Year, month.Month, 1);
        var firstWeekday = (int)CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek;
        var back = ((int)first.DayOfWeek - firstWeekday + 7) % 7;
        var start = first.AddDays(-back);
        return Enumerable.Range(0, 42).Select(i => start.AddDays(i)).ToList();
    }

    /// Downloads the feeds every 15 minutes (or when they change), then recomputes the day.
    public async Task Refresh()
    {
        if (!isFetching && (DateTime.UtcNow - lastFetch).TotalMinutes >= 15)
        {
            isFetching = true;
            lastFetch = DateTime.UtcNow;
            var enabled = settings.CalendarFeeds.Where(f => f.Enabled && !string.IsNullOrWhiteSpace(f.Url)).ToList();
            foreach (var id in feeds.Keys.Except(enabled.Select(f => f.Id)).ToList()) feeds.Remove(id);
            await Task.WhenAll(enabled.Select(async feed =>
            {
                var text = await Download(feed.Url);
                if (text != null) feeds[feed.Id] = IcsParser.Parse(text);
            }));
            isFetching = false;
        }
        Recompute();
    }

    public static async Task<string?> Download(string url)
    {
        try
        {
            var address = url.Trim();
            // Calendar apps hand out webcal:// links.
            if (address.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) address = "https://" + address[9..];
            return await Http.Client.GetStringAsync(address);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private void Recompute()
    {
        var colors = settings.CalendarFeeds.ToDictionary(f => f.Id, f => Ui.ParseColor(f.Color, Colors.OrangeRed));
        var grid = GridDays(DisplayedMonth);
        DateTime from = grid[0] < SelectedDay ? grid[0] : SelectedDay, to = (grid[^1] > SelectedDay ? grid[^1] : SelectedDay).AddDays(1);
        var occurrences = new List<CalendarEvent>();
        foreach (var (id, events) in feeds)
        {
            if (!colors.TryGetValue(id, out var color)) continue;
            foreach (var item in events) occurrences.AddRange(item.Occurrences(from, to, color));
        }

        var dayStart = SelectedDay;
        var dayEnd = SelectedDay.AddDays(1);
        var isToday = SelectedDay == DateTime.Today;
        Events = occurrences
            .Where(e => e.Start < dayEnd && e.End > dayStart)
            // Today: hide what has already ended.
            .Where(e => !isToday || e.IsAllDay || e.End > DateTime.Now)
            .OrderBy(e => !e.IsAllDay).ThenBy(e => e.Start)
            .ToList();

        var dots = new Dictionary<DateTime, List<Color>>();
        foreach (var day in grid)
        {
            var next = day.AddDays(1);
            var list = occurrences.Where(e => e.Start < next && e.End > day).OrderBy(e => e.Start)
                .Select(e => e.Color).Distinct().Take(3).ToList();
            if (list.Count > 0) dots[day] = list;
        }
        MonthDots = dots;
        Changed?.Invoke();
    }
}

/// One VEVENT, with enough of RRULE to expand the common repeating events.
internal sealed class IcsEvent
{
    public string Uid = "";
    public string Summary = "";
    public DateTime Start;
    public DateTime End;
    public bool AllDay;
    public string? Rule;
    public HashSet<DateTime> Exceptions = new();
    public DateTime? RecurrenceId;
    public bool Cancelled;

    public IEnumerable<CalendarEvent> Occurrences(DateTime from, DateTime to, Color color)
    {
        var length = End > Start ? End - Start : AllDay ? TimeSpan.FromDays(1) : TimeSpan.Zero;
        var title = string.IsNullOrWhiteSpace(Summary) ? "Untitled" : Summary;
        foreach (var start in Starts(from - length, to))
        {
            if (Exceptions.Contains(start)) continue;
            var end = start + length;
            if (start < to && (end > from || start >= from))
                yield return new CalendarEvent($"{Uid}|{start:O}", title, start, end, AllDay, color);
        }
    }

    private IEnumerable<DateTime> Starts(DateTime from, DateTime to)
    {
        if (string.IsNullOrEmpty(Rule))
        {
            yield return Start;
            yield break;
        }
        var parts = Rule.Split(';').Select(p => p.Split('=', 2)).Where(p => p.Length == 2)
            .ToDictionary(p => p[0].ToUpperInvariant(), p => p[1]);
        var freq = parts.GetValueOrDefault("FREQ", "DAILY");
        var interval = int.TryParse(parts.GetValueOrDefault("INTERVAL"), out var n) && n > 0 ? n : 1;
        int? count = int.TryParse(parts.GetValueOrDefault("COUNT"), out var c) ? c : null;
        DateTime? until = parts.TryGetValue("UNTIL", out var u) ? IcsParser.ParseDate(u, null, out _) : null;
        var byDay = parts.TryGetValue("BYDAY", out var days) ? days.Split(',') : Array.Empty<string>();
        var byMonthDay = parts.TryGetValue("BYMONTHDAY", out var monthDays)
            ? monthDays.Split(',').Select(s => int.TryParse(s, out var d) ? d : 0).Where(d => d != 0).ToArray()
            : Array.Empty<int>();

        var produced = 0;
        var time = Start.TimeOfDay;
        // Walk period by period; each yields its candidate days.
        for (var period = 0; period < 5000; period++)
        {
            IEnumerable<DateTime> candidates;
            DateTime periodStart;
            switch (freq)
            {
                case "WEEKLY":
                {
                    var weekStart = Start.Date.AddDays(-(((int)Start.DayOfWeek + 6) % 7)).AddDays(7 * interval * period);
                    periodStart = weekStart;
                    candidates = byDay.Length == 0
                        ? new[] { weekStart.AddDays(((int)Start.DayOfWeek + 6) % 7) }
                        : byDay.Select(Weekday).Where(d => d != null)
                            .Select(d => weekStart.AddDays(((int)d!.Value + 6) % 7)).OrderBy(d => d);
                    break;
                }
                case "MONTHLY":
                {
                    var month = new DateTime(Start.Year, Start.Month, 1).AddMonths(interval * period);
                    periodStart = month;
                    if (byMonthDay.Length > 0)
                        candidates = byMonthDay.Select(d => DayOfMonth(month, d)).OfType<DateTime>().OrderBy(d => d);
                    else if (byDay.Length > 0)
                        candidates = byDay.SelectMany(d => NthWeekday(month, d)).OrderBy(d => d);
                    else
                        candidates = DayOfMonth(month, Start.Day) is { } day ? new[] { day } : Array.Empty<DateTime>();
                    break;
                }
                case "YEARLY":
                {
                    var year = Start.Year + interval * period;
                    periodStart = new DateTime(year, 1, 1);
                    candidates = Start.Month == 2 && Start.Day == 29 && !DateTime.IsLeapYear(year)
                        ? Array.Empty<DateTime>()
                        : new[] { new DateTime(year, Start.Month, Start.Day) };
                    break;
                }
                default:
                    periodStart = Start.Date.AddDays(interval * period);
                    candidates = new[] { periodStart };
                    break;
            }
            if (periodStart > to) yield break;
            foreach (var day in candidates)
            {
                var start = day.Date + time;
                if (start < Start) continue;
                if (until is { } last && start > last) yield break;
                produced++;
                if (count is { } max && produced > max) yield break;
                if (start >= from && start < to) yield return start;
            }
        }
    }

    private static DayOfWeek? Weekday(string text)
    {
        var code = text.Length >= 2 ? text[^2..].ToUpperInvariant() : "";
        return code switch
        {
            "MO" => DayOfWeek.Monday,
            "TU" => DayOfWeek.Tuesday,
            "WE" => DayOfWeek.Wednesday,
            "TH" => DayOfWeek.Thursday,
            "FR" => DayOfWeek.Friday,
            "SA" => DayOfWeek.Saturday,
            "SU" => DayOfWeek.Sunday,
            _ => null,
        };
    }

    private static DateTime? DayOfMonth(DateTime month, int day)
    {
        var days = DateTime.DaysInMonth(month.Year, month.Month);
        var actual = day > 0 ? day : days + day + 1;
        return actual >= 1 && actual <= days ? new DateTime(month.Year, month.Month, actual) : null;
    }

    /// "MO" (every Monday), "1MO" (first), "-1FR" (last Friday).
    private static IEnumerable<DateTime> NthWeekday(DateTime month, string text)
    {
        if (Weekday(text) is not { } weekday) yield break;
        var all = Enumerable.Range(0, DateTime.DaysInMonth(month.Year, month.Month))
            .Select(i => month.AddDays(i)).Where(d => d.DayOfWeek == weekday).ToList();
        var prefix = text[..^2];
        if (prefix.Length == 0)
        {
            foreach (var day in all) yield return day;
        }
        else if (int.TryParse(prefix, out var nth) && nth != 0)
        {
            var index = nth > 0 ? nth - 1 : all.Count + nth;
            if (index >= 0 && index < all.Count) yield return all[index];
        }
    }
}

internal static class IcsParser
{
    public static List<IcsEvent> Parse(string text)
    {
        // Unfold continuation lines.
        var lines = text.Replace("\r\n", "\n").Replace("\n ", "").Replace("\n\t", "").Split('\n');
        var events = new List<IcsEvent>();
        IcsEvent? current = null;
        var depth = 0;
        foreach (var raw in lines)
        {
            var line = raw.TrimEnd('\r');
            if (line == "BEGIN:VEVENT") { current = new IcsEvent(); depth = 0; continue; }
            if (current == null) continue;
            if (line.StartsWith("BEGIN:")) { depth++; continue; }
            if (line.StartsWith("END:") && depth > 0) { depth--; continue; }
            if (line == "END:VEVENT")
            {
                if (current.Start != default) events.Add(current);
                current = null;
                continue;
            }
            if (depth > 0) continue; // inside VALARM
            var colon = line.IndexOf(':');
            if (colon < 0) continue;
            var head = line[..colon];
            var value = line[(colon + 1)..];
            var segments = head.Split(';');
            var name = segments[0].ToUpperInvariant();
            var parameters = segments.Skip(1).Select(p => p.Split('=', 2)).Where(p => p.Length == 2)
                .ToDictionary(p => p[0].ToUpperInvariant(), p => p[1].Trim('"'));
            parameters.TryGetValue("TZID", out var zone);
            switch (name)
            {
                case "UID": current.Uid = value; break;
                case "SUMMARY": current.Summary = Unescape(value); break;
                case "DTSTART":
                    current.Start = ParseDate(value, zone, out var allDay) ?? default;
                    current.AllDay = allDay;
                    break;
                case "DTEND":
                    current.End = ParseDate(value, zone, out _) ?? default;
                    break;
                case "DURATION":
                    if (TryParseDuration(value, out var duration)) current.End = current.Start + duration;
                    break;
                case "RRULE": current.Rule = value; break;
                case "EXDATE":
                    foreach (var item in value.Split(','))
                        if (ParseDate(item, zone, out _) is { } date) current.Exceptions.Add(date);
                    break;
                case "RECURRENCE-ID":
                    current.RecurrenceId = ParseDate(value, zone, out _);
                    break;
                case "STATUS":
                    if (value.Equals("CANCELLED", StringComparison.OrdinalIgnoreCase)) current.Cancelled = true;
                    break;
            }
        }

        // Moved or changed occurrences replace their slot in the repeating event.
        foreach (var moved in events.Where(e => e.RecurrenceId != null).ToList())
        {
            foreach (var master in events.Where(e => e.Uid == moved.Uid && e.RecurrenceId == null && e.Rule != null))
                master.Exceptions.Add(moved.RecurrenceId!.Value);
        }
        events.RemoveAll(e => e.Cancelled);
        return events;
    }

    /// Local time for "20260101T090000Z", "20260101T090000" (+TZID) or "20260101" (all day).
    public static DateTime? ParseDate(string value, string? zone, out bool allDay)
    {
        value = value.Trim();
        allDay = value.Length == 8;
        if (allDay)
            return DateTime.TryParseExact(value, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day)
                ? day : null;
        var utc = value.EndsWith('Z');
        var body = utc ? value[..^1] : value;
        if (!DateTime.TryParseExact(body, "yyyyMMdd'T'HHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var time))
            return null;
        if (utc) return DateTime.SpecifyKind(time, DateTimeKind.Utc).ToLocalTime();
        if (zone != null && FindZone(zone) is { } info)
        {
            try { return TimeZoneInfo.ConvertTime(time, info, TimeZoneInfo.Local); }
            catch (ArgumentException) { }
        }
        return time;
    }

    private static readonly Dictionary<string, TimeZoneInfo?> Zones = new();

    private static TimeZoneInfo? FindZone(string id)
    {
        if (Zones.TryGetValue(id, out var cached)) return cached;
        TimeZoneInfo? zone = null;
        try { zone = TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch (TimeZoneNotFoundException) { }
        catch (InvalidTimeZoneException) { }
        Zones[id] = zone;
        return zone;
    }

    private static bool TryParseDuration(string text, out TimeSpan duration)
    {
        duration = TimeSpan.Zero;
        var negative = text.StartsWith('-');
        var body = text.TrimStart('+', '-');
        if (!body.StartsWith('P')) return false;
        var number = "";
        var inTime = false;
        foreach (var ch in body[1..])
        {
            if (char.IsDigit(ch)) { number += ch; continue; }
            if (ch == 'T') { inTime = true; continue; }
            var value = number.Length > 0 ? int.Parse(number, CultureInfo.InvariantCulture) : 0;
            number = "";
            duration += ch switch
            {
                'W' => TimeSpan.FromDays(7 * value),
                'D' => TimeSpan.FromDays(value),
                'H' when inTime => TimeSpan.FromHours(value),
                'M' when inTime => TimeSpan.FromMinutes(value),
                'S' when inTime => TimeSpan.FromSeconds(value),
                _ => TimeSpan.Zero,
            };
        }
        if (negative) duration = -duration;
        return true;
    }

    private static string Unescape(string text) =>
        text.Replace("\\n", " ").Replace("\\N", " ").Replace("\\,", ",").Replace("\\;", ";").Replace("\\\\", "\\");
}
