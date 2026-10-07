using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Lenotch.Services;

namespace Lenotch.AI;

/// One usage limit window, e.g. the 5-hour session or the week.
public sealed record UsageWindow(string Id, string Label, double Used, DateTime? ResetsAt);

public abstract record ProviderUsage
{
    public sealed record Loading : ProviderUsage;
    public sealed record Ok(string? Plan, List<UsageWindow> Windows) : ProviderUsage;
    /// Signed in, but the reading failed or needs action (message says what).
    public sealed record Problem(string Message) : ProviderUsage;
    /// The tool isn't installed or signed in on this PC; hidden in the notch.
    public sealed record NotSetUp : ProviderUsage;

    public List<UsageWindow> WindowList => this is Ok ok ? ok.Windows : new List<UsageWindow>();
    public UsageWindow? Headline => WindowList.FirstOrDefault();
}

internal sealed class UsageException : Exception
{
    public enum Kind { NotSetUp, RateLimited, Problem }
    public Kind Reason { get; }
    public UsageException(Kind reason, string message = "") : base(message) { Reason = reason; }

    public static UsageException NotSetUp => new(Kind.NotSetUp);
    public static UsageException Problem(string message) => new(Kind.Problem, message);
}

/// Fetches usage for the enabled sources. Only polls while the widget is on screen.
public sealed class AIUsageService
{
    /// Keyed by `UsageSource.Id`.
    public Dictionary<string, ProviderUsage> Usage { get; } = new();
    private readonly Dictionary<string, DateTime> lastRefresh = new();
    /// Providers' usage endpoints are rate limited; don't ask more often than this.
    private static readonly TimeSpan MinimumInterval = TimeSpan.FromSeconds(60);

    public event Action? Changed;

    public ProviderUsage UsageOf(string id) => Usage.TryGetValue(id, out var usage) ? usage : new ProviderUsage.Loading();

    public async Task Refresh(IEnumerable<UsageSource> sources, bool force = false)
    {
        var tasks = new List<Task>();
        foreach (var source in sources)
        {
            if (!force && lastRefresh.TryGetValue(source.Id, out var last) && DateTime.UtcNow - last < MinimumInterval) continue;
            lastRefresh[source.Id] = DateTime.UtcNow;
            if (!Usage.ContainsKey(source.Id)) Usage[source.Id] = new ProviderUsage.Loading();
            tasks.Add(Load(source));
        }
        Changed?.Invoke();
        await Task.WhenAll(tasks);
    }

    private async Task Load(UsageSource source)
    {
        var result = await Fetch(source);
        // null means "keep the previous reading" (e.g. rate limited).
        if (result != null) Usage[source.Id] = result;
        Changed?.Invoke();
    }

    /// One reading, for the Test button in Settings.
    public static async Task<ProviderUsage> Test(CustomProvider provider) =>
        await Fetch(new UsageSource(provider)) ?? new ProviderUsage.Problem("Rate limited, try again shortly");

    private static async Task<ProviderUsage?> Fetch(UsageSource source)
    {
        try
        {
            if (source.Custom is { } custom) return await CustomUsage.Fetch(custom);
            return source.BuiltIn switch
            {
                AIProvider.Claude => await ClaudeUsage.Fetch(),
                AIProvider.Codex => await CodexUsage.Fetch(),
                AIProvider.Cursor => await CursorUsage.Fetch(),
                AIProvider.Copilot => await CopilotUsage.Fetch(),
                AIProvider.Grok => await GrokUsage.Fetch(),
                AIProvider.Kimi => await KimiUsage.Fetch(),
                AIProvider.Opencode => await OpenCodeUsage.Fetch(),
                AIProvider.Amp => await AmpUsage.Fetch(),
                _ => new ProviderUsage.NotSetUp(),
            };
        }
        catch (UsageException error) when (error.Reason == UsageException.Kind.NotSetUp) { return new ProviderUsage.NotSetUp(); }
        catch (UsageException error) when (error.Reason == UsageException.Kind.RateLimited) { return null; }
        catch (UsageException error) { return new ProviderUsage.Problem(error.Message); }
        catch (Exception) { return new ProviderUsage.Problem($"Couldn't reach {source.Title}"); }
    }
}

// MARK: - Shared helpers

internal static class UsageHttp
{
    public static readonly string Home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    public static string HomePath(params string[] parts) => Path.Combine(new[] { Home }.Concat(parts).ToArray());

    public static async Task<string> Get(string url, Dictionary<string, string> headers, HttpMethod? method = null, string? body = null)
    {
        using var request = new HttpRequestMessage(method ?? HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("User-Agent", "Lenotch");
        foreach (var (name, value) in headers)
        {
            if (name.Equals("Content-Type", StringComparison.OrdinalIgnoreCase)) continue;
            request.Headers.TryAddWithoutValidation(name, value);
        }
        if (body != null) request.Content = new StringContent(body, Encoding.UTF8, "application/json");
        using var response = await Http.Client.SendAsync(request);
        var code = (int)response.StatusCode;
        if (code is >= 200 and < 300) return await response.Content.ReadAsStringAsync();
        throw response.StatusCode switch
        {
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden => UsageException.Problem("Sign in again"),
            HttpStatusCode.TooManyRequests => new UsageException(UsageException.Kind.RateLimited),
            _ => UsageException.Problem("Usage unavailable right now"),
        };
    }

    /// Runs a command-line tool and returns its standard output.
    public static async Task<string?> Run(string file, string arguments)
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo(file, arguments)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            });
            if (process == null) return null;
            var output = await process.StandardOutput.ReadToEndAsync();
            await process.WaitForExitAsync();
            return process.ExitCode == 0 ? output.Trim() : null;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public static JsonElement? ReadJson(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            return document.RootElement.Clone();
        }
        catch (Exception)
        {
            return null;
        }
    }

    public static JsonElement ParseJson(string text)
    {
        try
        {
            using var document = JsonDocument.Parse(text);
            return document.RootElement.Clone();
        }
        catch (JsonException)
        {
            throw UsageException.Problem("Unexpected response");
        }
    }
}

internal static class Json
{
    public static JsonElement? Get(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null
            ? value : null;

    public static double? AsNumber(this JsonElement? element) => element switch
    {
        { ValueKind: JsonValueKind.Number } e => e.GetDouble(),
        { ValueKind: JsonValueKind.String } e when double.TryParse(e.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var n) => n,
        _ => null,
    };

    public static string? AsString(this JsonElement? element) =>
        element is { ValueKind: JsonValueKind.String } e ? e.GetString() : null;

    /// Reads a value by dot path, e.g. `data.limits.0.used`.
    public static JsonElement? At(this JsonElement root, string path)
    {
        JsonElement? current = root;
        foreach (var component in path.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            if (current is not { } node) return null;
            if (node.ValueKind == JsonValueKind.Object) current = node.Get(component);
            else if (node.ValueKind == JsonValueKind.Array && int.TryParse(component, out var index) && index >= 0
                     && index < node.GetArrayLength()) current = node[index];
            else return null;
        }
        return current;
    }

    /// ISO 8601 text, or Unix seconds / milliseconds.
    public static DateTime? AsDate(this JsonElement? element)
    {
        if (element.AsString() is { } text)
        {
            if (DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date))
                return date.UtcDateTime;
            if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var number)) return FromEpoch(number);
            return null;
        }
        return element.AsNumber() is { } value ? FromEpoch(value) : null;
    }

    public static DateTime FromEpoch(double value) =>
        DateTimeOffset.FromUnixTimeMilliseconds((long)(value > 1e12 ? value : value * 1000)).UtcDateTime;
}

// MARK: - Claude Code

/// Claude Code keeps its sign-in in ~/.claude/.credentials.json on Windows.
/// Expired tokens aren't refreshed here, since that would sign Claude Code out.
internal static class ClaudeUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        var folder = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR") ?? UsageHttp.HomePath(".claude");
        if (UsageHttp.ReadJson(Path.Combine(folder, ".credentials.json")) is not { } root
            || root.Get("claudeAiOauth") is not { } oauth
            || oauth.Get("accessToken").AsString() is not { Length: > 0 } token) throw UsageException.NotSetUp;
        if (oauth.Get("expiresAt").AsNumber() is { } expires && expires / 1000 < DateTimeOffset.UtcNow.ToUnixTimeSeconds())
            throw UsageException.Problem("Open Claude Code to refresh");

        var body = UsageHttp.ParseJson(await UsageHttp.Get("https://api.anthropic.com/api/oauth/usage", new()
        {
            ["Authorization"] = $"Bearer {token}",
            ["anthropic-beta"] = "oauth-2025-04-20",
        }));
        var windows = new[] { ("session", "Current session", "five_hour"), ("week", "All models", "seven_day"),
                ("opus", "Opus", "seven_day_opus"), ("sonnet", "Sonnet", "seven_day_sonnet") }
            .Select(w => body.Get(w.Item3) is { } window && window.Get("utilization").AsNumber() is { } used
                ? new UsageWindow(w.Item1, w.Item2, used / 100, window.Get("resets_at").AsDate())
                : null)
            .OfType<UsageWindow>().ToList();
        return new ProviderUsage.Ok(null, windows);
    }
}

// MARK: - Codex

/// Codex keeps its ChatGPT sign-in in ~/.codex/auth.json and refreshes it itself.
internal static class CodexUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        var folder = Environment.GetEnvironmentVariable("CODEX_HOME") ?? UsageHttp.HomePath(".codex");
        if (UsageHttp.ReadJson(Path.Combine(folder, "auth.json")) is not { } root
            || root.Get("tokens") is not { } tokens
            || tokens.Get("access_token").AsString() is not { Length: > 0 } token) throw UsageException.NotSetUp;

        var body = UsageHttp.ParseJson(await UsageHttp.Get("https://chatgpt.com/backend-api/wham/usage", new()
        {
            ["Authorization"] = $"Bearer {token}",
            ["ChatGPT-Account-Id"] = tokens.Get("account_id").AsString() ?? "",
        }));
        var limits = body.Get("rate_limit");
        var windows = new[] { "primary", "secondary" }
            .Select(id => limits?.Get(id + "_window") is { } window && window.Get("used_percent").AsNumber() is { } used
                ? new UsageWindow(id, Label(window.Get("limit_window_seconds").AsNumber(), id), used / 100,
                    window.Get("reset_at").AsNumber() is { } reset ? Json.FromEpoch(reset) : null)
                : null)
            .OfType<UsageWindow>().ToList();
        var plan = body.Get("plan_type").AsString();
        return new ProviderUsage.Ok(plan != null ? Capitalize(plan) : null, windows);
    }

    private static string Label(double? seconds, string fallback) => seconds switch
    {
        18_000 => "5h limit",
        604_800 => "Weekly limit",
        >= 86_400 => $"{(int)(seconds.Value / 86_400)}-day limit",
        { } s => $"{(int)(s / 3_600)}h limit",
        _ => fallback == "primary" ? "5h limit" : "Weekly limit",
    };

    public static string Capitalize(string text) =>
        CultureInfo.InvariantCulture.TextInfo.ToTitleCase(text.ToLowerInvariant());
}

// MARK: - GitHub Copilot

/// Copilot's quota, authenticated with the GitHub CLI's sign-in.
internal static class CopilotUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        var installed = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "GitHub CLI", "gh.exe");
        var token = await UsageHttp.Run(File.Exists(installed) ? installed : "gh", "auth token");
        if (string.IsNullOrEmpty(token)) throw UsageException.NotSetUp;

        var body = UsageHttp.ParseJson(await UsageHttp.Get("https://api.github.com/copilot_internal/user", new()
        {
            ["Authorization"] = $"token {token}",
            ["Accept"] = "application/json",
        }));
        if (body.Get("copilot_plan").AsString() is not { } plan) throw UsageException.NotSetUp;
        DateTime? resets = DateTime.TryParseExact(body.Get("quota_reset_date").AsString(), "yyyy-MM-dd",
            CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? date.ToUniversalTime() : null;
        var snapshots = body.Get("quota_snapshots");
        var windows = new[] { ("premium_interactions", "Premium requests"), ("chat", "Chat"), ("completions", "Completions") }
            .Select(q => snapshots?.Get(q.Item1) is { } quota
                         && quota.Get("unlimited") is not { ValueKind: JsonValueKind.True }
                         && quota.Get("percent_remaining").AsNumber() is { } remaining
                ? new UsageWindow(q.Item1, q.Item2, 1 - remaining / 100, resets)
                : null)
            .OfType<UsageWindow>().ToList();
        return new ProviderUsage.Ok(CodexUsage.Capitalize(plan), windows);
    }
}

// MARK: - Cursor

/// The Cursor editor keeps its session in its SQLite state database.
internal static class CursorUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Cursor", "User", "globalStorage", "state.vscdb");
        if (!File.Exists(path) || SqliteReader.Value("cursorAuth/accessToken", path) is not { Length: > 0 } token)
            throw UsageException.NotSetUp;
        var account = SqliteReader.Value("cursorAuth/stripeMembershipAuthId", path) is { Length: > 0 } id
            ? id
            : Jwt.Claims(token)?.Get("sub").AsString();
        if (account == null) throw UsageException.NotSetUp;

        var root = UsageHttp.ParseJson(await UsageHttp.Get("https://cursor.com/api/usage-summary", new()
        {
            ["Cookie"] = $"WorkosCursorSessionToken={account}::{token}",
            ["Accept"] = "application/json",
        }));
        var resets = root.Get("billingCycleEnd").AsDate();
        var plan = root.Get("individualUsage")?.Get("plan");
        var windows = new List<UsageWindow>();
        if (plan?.Get("autoPercentUsed").AsNumber() is { } auto)
            windows.Add(new UsageWindow("auto", "Auto usage", auto / 100, resets));
        if (plan?.Get("apiPercentUsed").AsNumber() is { } api && api > 0)
            windows.Add(new UsageWindow("api", "API usage", api / 100, resets));
        if (windows.Count == 0 && plan?.Get("totalPercentUsed").AsNumber() is { } total)
            windows.Add(new UsageWindow("total", "Included usage", total / 100, resets));
        if (windows.Count == 0) throw UsageException.Problem("Nothing metered on this plan");
        var membership = root.Get("membershipType").AsString();
        return new ProviderUsage.Ok(membership != null ? CodexUsage.Capitalize(membership) : null, windows);
    }
}

// MARK: - Grok

/// The Grok CLI keeps its xAI session in ~/.grok/auth.json.
internal static class GrokUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        if (UsageHttp.ReadJson(UsageHttp.HomePath(".grok", "auth.json")) is not { ValueKind: JsonValueKind.Object } root)
            throw UsageException.NotSetUp;
        // Only sessions issued by xAI's own sign-in; prefer one that hasn't expired.
        var entries = root.EnumerateObject()
            .Where(p => p.Value.ValueKind == JsonValueKind.Object
                        && (p.Name.Split("::")[0] == "https://auth.x.ai" || p.Value.Get("oidc_issuer").AsString() == "https://auth.x.ai"))
            .Select(p => p.Value).ToList();
        var entry = entries.FirstOrDefault(e => (e.Get("expires_at").AsDate() ?? DateTime.MaxValue) > DateTime.UtcNow);
        if (entry.ValueKind == JsonValueKind.Undefined && entries.Count > 0) entry = entries[0];
        if (entry.ValueKind != JsonValueKind.Object || entry.Get("key").AsString() is not { Length: > 0 } token)
            throw UsageException.NotSetUp;

        var body = UsageHttp.ParseJson(await UsageHttp.Get("https://cli-chat-proxy.grok.com/v1/billing?format=credits", new()
        {
            ["Authorization"] = $"Bearer {token}",
            ["X-XAI-Token-Auth"] = "xai-grok-cli",
            ["Accept"] = "application/json",
        }));
        if (body.Get("config") is not { } config) throw UsageException.Problem("Unexpected response");
        var resets = config.Get("currentPeriod")?.Get("end").AsDate() ?? config.Get("billingPeriodEnd").AsDate();
        var windows = new List<UsageWindow>();
        if (config.Get("creditUsagePercent").AsNumber() is { } percent)
        {
            windows.Add(new UsageWindow("credits", "Credits", percent / 100, resets));
        }
        else if (config.Get("productUsage") is { ValueKind: JsonValueKind.Array } products)
        {
            foreach (var product in products.EnumerateArray())
            {
                if (product.Get("usagePercent").AsNumber() is not { } used) continue;
                var name = product.Get("product").AsString() ?? "Usage";
                windows.Add(new UsageWindow(name, name, used / 100, resets));
            }
        }
        if (windows.Count == 0) throw UsageException.Problem("Nothing metered yet");
        return new ProviderUsage.Ok(null, windows);
    }
}

// MARK: - Kimi Code

/// The Kimi Code CLI keeps its session in ~/.kimi-code/credentials/kimi-code.json.
internal static class KimiUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        var home = Environment.GetEnvironmentVariable("KIMI_CODE_HOME") ?? UsageHttp.HomePath(".kimi-code");
        if (UsageHttp.ReadJson(Path.Combine(home, "credentials", "kimi-code.json")) is not { } root
            || root.Get("access_token").AsString() is not { Length: > 0 } token) throw UsageException.NotSetUp;
        if (root.Get("expires_at").AsNumber() is { } expires && expires < DateTimeOffset.UtcNow.ToUnixTimeSeconds())
            throw UsageException.Problem("Open Kimi Code to refresh");

        var response = UsageHttp.ParseJson(await UsageHttp.Get("https://api.kimi.com/coding/v1/usages", new()
        {
            ["Authorization"] = $"Bearer {token}",
            ["Accept"] = "application/json",
        }));
        var windows = new List<UsageWindow>();
        if (response.Get("limits") is { ValueKind: JsonValueKind.Array } limits)
            foreach (var entry in limits.EnumerateArray())
                if (entry.Get("detail") is { } detail && Row(detail, "rolling", "5h limit") is { } window) windows.Add(window);
        if (response.Get("usage") is { } summary && Row(summary, "weekly", "Weekly limit") is { } week) windows.Add(week);
        if (windows.Count == 0) throw UsageException.Problem("No usage limits on this account");
        var plan = response.Get("user")?.Get("membership")?.Get("level").AsString();
        return new ProviderUsage.Ok(plan != null ? CodexUsage.Capitalize(plan.Replace("LEVEL_", "")) : null, windows);
    }

    private static UsageWindow? Row(JsonElement detail, string id, string label)
    {
        if (detail.Get("limit").AsNumber() is not { } limit || limit <= 0) return null;
        var used = detail.Get("used").AsNumber() ?? (detail.Get("remaining").AsNumber() is { } remaining ? limit - remaining : null);
        return used is { } u ? new UsageWindow(id, label, u / limit, detail.Get("resetTime").AsDate()) : null;
    }
}

// MARK: - OpenCode

/// OpenCode stores its Go plan key in ~/.local/share/opencode/auth.json.
internal static class OpenCodeUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        if (UsageHttp.ReadJson(UsageHttp.HomePath(".local", "share", "opencode", "auth.json")) is not { } root
            || root.Get("opencode-go") is not { } entry) throw UsageException.NotSetUp;
        var token = entry.ValueKind == JsonValueKind.String
            ? entry.GetString()
            : new[] { "key", "apiKey", "api_key", "token", "accessToken" }.Select(k => entry.Get(k).AsString()).FirstOrDefault(s => s != null);
        if (string.IsNullOrEmpty(token)) throw UsageException.NotSetUp;

        var body = UsageHttp.ParseJson(await UsageHttp.Get("https://opencode.ai/zen/go/v1/usage", new()
        {
            ["Authorization"] = $"Bearer {token}",
            ["Accept"] = "application/json",
        }));
        if (body.Get("usage") is not { } usage) throw UsageException.Problem("Unexpected response");
        var windows = new[] { ("rolling", "5h limit"), ("weekly", "Weekly limit"), ("monthly", "Monthly limit") }
            .Select(w => usage.Get(w.Item1) is { } window && window.Get("percent").AsNumber() is { } percent
                ? new UsageWindow(w.Item1, w.Item2, percent / 100, window.Get("resetsAt").AsDate())
                : null)
            .OfType<UsageWindow>().ToList();
        if (windows.Count == 0) throw UsageException.Problem("Unexpected response");
        return new ProviderUsage.Ok("Go", windows);
    }
}

// MARK: - Amp

/// The Amp CLI keeps its API key in ~/.local/share/amp/secrets.json; usage comes back as display text.
internal static class AmpUsage
{
    public static async Task<ProviderUsage> Fetch()
    {
        var candidates = new[]
        {
            UsageHttp.HomePath(".local", "share", "amp", "secrets.json"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "amp", "secrets.json"),
        };
        var root = candidates.Select(UsageHttp.ReadJson).FirstOrDefault(r => r != null);
        var token = root is { } r
            ? new[] { "apiKey@https://ampcode.com/", "apiKey@https://ampcode.com" }.Select(k => r.Get(k).AsString()).FirstOrDefault(s => s != null)
            : null;
        if (string.IsNullOrEmpty(token)) throw UsageException.NotSetUp;

        var response = UsageHttp.ParseJson(await UsageHttp.Get("https://ampcode.com/api/internal", new()
        {
            ["Authorization"] = $"Bearer {token}",
            ["Accept"] = "application/json",
        }, HttpMethod.Post, """{"jsonrpc":"2.0","method":"userDisplayBalanceInfo","params":{},"id":1}"""));
        var text = (response.Get("result") ?? response).Get("displayText").AsString()
                   ?? throw UsageException.Problem("Unexpected response");
        var clean = text.Replace("**", "");

        // "Amp Pro Subscription: 72% agent usage and 90% orb usage remaining"
        var tier = Regex.Match(clean, @"Amp\s+(.+?)\s+(?:Subscription|Tier):.*?([0-9.]+)%.*?([0-9.]+)%", RegexOptions.IgnoreCase);
        if (tier.Success && double.TryParse(tier.Groups[2].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var agent)
            && double.TryParse(tier.Groups[3].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var orb))
        {
            return new ProviderUsage.Ok(tier.Groups[1].Value, new List<UsageWindow>
            {
                new("agent", "Agent usage", (100 - agent) / 100, null),
                new("orb", "Orb usage", (100 - orb) / 100, null),
            });
        }
        // "Amp Free: $4.20/$10 remaining (replenishes +$0.42/hour)"
        var free = Regex.Match(clean, @"Amp Free:\s*\$([0-9.]+)/\$([0-9.]+)\s+remaining", RegexOptions.IgnoreCase);
        if (free.Success && double.TryParse(free.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var left)
            && double.TryParse(free.Groups[2].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var total) && total > 0)
        {
            return new ProviderUsage.Ok("Free", new List<UsageWindow> { new("free", "Free allowance", 1 - left / total, null) });
        }
        throw UsageException.Problem("Couldn't read Amp's balance");
    }
}

// MARK: - Custom

internal static class CustomUsage
{
    public static async Task<ProviderUsage> Fetch(CustomProvider provider)
    {
        var url = provider.Url.Trim();
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || !uri.Scheme.StartsWith("http"))
            throw UsageException.Problem("Set a valid URL");
        var headers = new Dictionary<string, string> { ["Accept"] = "application/json" };
        if (provider.ApiKey is { } key && provider.AuthHeader.Length > 0) headers[provider.AuthHeader] = provider.AuthPrefix + key;
        JsonElement root;
        try { root = JsonDocument.Parse(await UsageHttp.Get(url, headers)).RootElement.Clone(); }
        catch (JsonException) { throw UsageException.Problem("Not JSON"); }

        double? Number(string path) => root.At(path).AsNumber();
        var used = provider.Mode switch
        {
            CustomMode.Percent => Number(provider.ValuePath) / 100,
            CustomMode.UsedAndLimit => Number(provider.ValuePath) / Number(provider.LimitPath),
            _ => 1 - Number(provider.ValuePath) / Number(provider.LimitPath),
        };
        if (used is not { } value || !double.IsFinite(value)) throw UsageException.Problem("Value not found at that path");
        var resets = provider.ResetPath.Length == 0 ? null : root.At(provider.ResetPath).AsDate();
        return new ProviderUsage.Ok(null, new List<UsageWindow> { new("custom", provider.Label, value, resets) });
    }
}

// MARK: - Small readers

internal static class Jwt
{
    public static JsonElement? Claims(string token)
    {
        var parts = token.Split('.');
        if (parts.Length < 2) return null;
        var payload = parts[1].Replace('-', '+').Replace('_', '/');
        payload += new string('=', (4 - payload.Length % 4) % 4);
        try
        {
            using var document = JsonDocument.Parse(Convert.FromBase64String(payload));
            return document.RootElement.Clone();
        }
        catch (Exception) { return null; }
    }
}

/// Reads one value from a VS Code-style state database with Windows' own SQLite (winsqlite3.dll).
internal static class SqliteReader
{
    private const int SQLITE_OK = 0, SQLITE_ROW = 100, SQLITE_OPEN_READONLY = 1;

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_open_v2", CharSet = CharSet.Ansi)]
    private static extern int Open([MarshalAs(UnmanagedType.LPUTF8Str)] string path, out IntPtr db, int flags, IntPtr vfs);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_close_v2")]
    private static extern int Close(IntPtr db);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_prepare_v2")]
    private static extern int Prepare(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, int length, out IntPtr statement, IntPtr tail);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_bind_text")]
    private static extern int BindText(IntPtr statement, int index, byte[] text, int length, IntPtr destructor);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_step")]
    private static extern int Step(IntPtr statement);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_blob")]
    private static extern IntPtr ColumnBlob(IntPtr statement, int column);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_bytes")]
    private static extern int ColumnBytes(IntPtr statement, int column);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_finalize")]
    private static extern int Finalize(IntPtr statement);

    public static string? Value(string key, string databasePath)
    {
        try
        {
            if (Open(databasePath, out var db, SQLITE_OPEN_READONLY, IntPtr.Zero) != SQLITE_OK) { Close(db); return null; }
            try
            {
                if (Prepare(db, "SELECT value FROM ItemTable WHERE key = ?", -1, out var statement, IntPtr.Zero) != SQLITE_OK)
                    return null;
                try
                {
                    var bytes = Encoding.UTF8.GetBytes(key);
                    // SQLITE_TRANSIENT (-1): SQLite copies the text.
                    BindText(statement, 1, bytes, bytes.Length, new IntPtr(-1));
                    if (Step(statement) != SQLITE_ROW) return null;
                    var length = ColumnBytes(statement, 0);
                    var pointer = ColumnBlob(statement, 0);
                    if (pointer == IntPtr.Zero || length <= 0) return null;
                    var data = new byte[length];
                    Marshal.Copy(pointer, data, 0, length);
                    return Encoding.UTF8.GetString(data).Trim('"');
                }
                finally { Finalize(statement); }
            }
            finally { Close(db); }
        }
        catch (Exception)
        {
            return null;
        }
    }
}
