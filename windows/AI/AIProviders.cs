using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Media;
using Lenotch.Core;

namespace Lenotch.AI;

/// Built-in coding assistants whose usage limits the notch can show. Each is read
/// with the sign-in its own tool already keeps on this PC; Lenotch never asks for a login.
public enum AIProvider { Claude, Codex, Cursor, Copilot, Grok, Kimi, Opencode, Amp }

public static class AIProviders
{
    public static readonly AIProvider[] All = Enum.GetValues<AIProvider>();
    public static IEnumerable<string> AllKeys => All.Select(Key);

    public static string Key(this AIProvider provider) => provider.ToString().ToLowerInvariant();

    public static AIProvider? FromKey(string key) =>
        All.Cast<AIProvider?>().FirstOrDefault(p => p!.Value.Key() == key);

    public static string Title(this AIProvider provider) => provider switch
    {
        AIProvider.Claude => "Claude Code",
        AIProvider.Codex => "Codex",
        AIProvider.Cursor => "Cursor",
        AIProvider.Copilot => "Copilot",
        AIProvider.Grok => "Grok",
        AIProvider.Kimi => "Kimi Code",
        AIProvider.Opencode => "OpenCode",
        _ => "Amp",
    };

    /// Where the sign-in comes from, for Settings.
    public static string Source(this AIProvider provider) => provider switch
    {
        AIProvider.Claude => @"%USERPROFILE%\.claude\.credentials.json",
        AIProvider.Codex => @"%USERPROFILE%\.codex\auth.json",
        AIProvider.Cursor => "Cursor editor's sign-in",
        AIProvider.Copilot => "GitHub CLI (gh auth)",
        AIProvider.Grok => @"%USERPROFILE%\.grok\auth.json (Grok CLI)",
        AIProvider.Kimi => @"%USERPROFILE%\.kimi-code (Kimi Code CLI)",
        AIProvider.Opencode => @"%USERPROFILE%\.local\share\opencode\auth.json",
        _ => @"%USERPROFILE%\.local\share\amp\secrets.json",
    };

    public static Geometry Glyph(this AIProvider provider) => provider switch
    {
        AIProvider.Claude => GlyphOutline.Claude,
        AIProvider.Codex => GlyphOutline.Openai,
        AIProvider.Cursor => GlyphOutline.Cursor,
        AIProvider.Copilot => GlyphOutline.Copilot,
        AIProvider.Grok => GlyphOutline.Grok,
        AIProvider.Kimi => GlyphOutline.Kimi,
        AIProvider.Opencode => GlyphOutline.Opencode,
        _ => AmpGlyph,
    };

    /// Resources/glyph-amp.svg, fitted into the unit box.
    private static readonly Geometry AmpGlyph = MakeAmp();

    private static Geometry MakeAmp()
    {
        var geometry = Geometry.Parse("M236.014 20C260.431 20.0001 280.602 37.4115 280.603 64.7432C280.602 93.5337 260.065 114.166 233.52 114.166C224.158 114.166 215.639 112.422 208.63 108.49C202.886 105.27 198.203 100.605 194.919 94.3379L188.115 141.822L187.946 143.016H174.214L174.448 141.423L191.772 22.4941H205.372L203.937 31.3369C212.143 23.8608 223.2 20.0002 236.014 20ZM47.082 20.1543C56.4435 20.1543 65.0012 21.8991 72.0488 25.8486C77.8222 29.0831 82.5323 33.7713 85.8271 40.085L88.1201 23.6924L88.2861 22.4932H101.863L89.1611 110.633L88.9873 111.826H75.4092L76.7227 102.855C68.5854 110.456 57.3981 114.323 44.5889 114.323C20.1709 114.323 0.000167223 96.9087 0 69.5771C0.000149745 40.7854 20.54 20.1549 47.082 20.1543ZM116.234 110.636L116.061 111.827H102.485L115.351 23.6855L115.521 22.4941H129.083L116.234 110.636ZM140.673 110.636L140.499 111.827H126.924L139.789 23.6855L139.96 22.4941H153.521L140.673 110.636ZM177.958 22.4941L165.108 110.636L164.935 111.827H151.36L164.225 23.6855L164.396 22.4941H177.958ZM48.4854 31.9844C27.8638 31.985 14.0133 48.3799 14.0127 68.9521C14.0127 77.7907 16.8094 86.1771 22.3145 92.334C27.7973 98.4657 36.0631 102.493 47.2402 102.493C67.8534 102.493 81.7122 85.9487 81.7129 65.3682C81.7129 55.4076 78.2493 47.0792 72.4131 41.2441C66.5794 35.4088 58.2871 31.9844 48.4854 31.9844ZM233.362 31.8291C212.749 31.8297 198.89 48.3716 198.89 68.9521C198.89 78.9123 202.356 87.2403 208.189 93.0742C214.023 98.9107 222.315 102.336 232.116 102.336C252.738 102.335 266.589 85.9407 266.59 65.3682C266.59 56.5296 263.795 48.1424 258.29 41.9863C252.807 35.8551 244.542 31.8291 233.362 31.8291Z").Clone();
        // viewBox 0 20 281 124: centre it in a square unit box.
        var group = new TransformGroup();
        group.Children.Add(new TranslateTransform(0, -20 + (281 - 124) / 2.0));
        group.Children.Add(new ScaleTransform(1 / 281.0, 1 / 281.0));
        geometry.Transform = group;
        var flat = geometry.GetFlattenedPathGeometry();
        flat.Freeze();
        return flat;
    }
}

public enum CustomMode
{
    /// The response holds a used percentage (0–100).
    Percent,
    /// The response holds used and limit numbers.
    UsedAndLimit,
    /// The response holds remaining and limit numbers.
    RemainingAndLimit,
}

/// A user-defined usage source: any HTTP endpoint that returns JSON.
public sealed class CustomProvider
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "My Provider";
    public string Url { get; set; } = "";
    public string AuthHeader { get; set; } = "Authorization";
    public string AuthPrefix { get; set; } = "Bearer ";
    public CustomMode Mode { get; set; } = CustomMode.Percent;
    /// Dot paths into the JSON, e.g. `data.usage.percent` or `limits.0.used`.
    public string ValuePath { get; set; } = "";
    public string LimitPath { get; set; } = "";
    /// Optional: when the limit resets (ISO 8601 date or Unix seconds).
    public string ResetPath { get; set; } = "";
    public string Label { get; set; } = "Usage";
    /// Custom logo: a file name in the Logos folder, or a path.
    public string? LogoPath { get; set; }
    public bool? TintLogo { get; set; }
    /// Read the API key from this file instead of Lenotch's encrypted key store.
    public string? ApiKeyFile { get; set; }
    /// Set for providers loaded from a config file in the Providers folder.
    [JsonIgnore] public string? ConfigFile { get; set; }

    [JsonIgnore] public string Key => $"custom:{Id}";

    [JsonIgnore]
    public string? LogoFile
    {
        get
        {
            if (string.IsNullOrEmpty(LogoPath)) return null;
            var expanded = ProviderConfigStore.ExpandHome(LogoPath);
            return Path.IsPathRooted(expanded) ? expanded : Path.Combine(ProviderConfigStore.LogosFolder, LogoPath);
        }
    }

    // MARK: API key (encrypted for this Windows user, never in settings.json)

    private string KeyFile => Path.Combine(AppSettings.Folder, "Keys", $"{Id}.bin");

    [JsonIgnore]
    public string? ApiKey
    {
        get
        {
            if (!string.IsNullOrEmpty(ApiKeyFile))
            {
                try { return File.ReadAllText(ProviderConfigStore.ExpandHome(ApiKeyFile)).Trim(); }
                catch (Exception) { return null; }
            }
            try
            {
                if (!File.Exists(KeyFile)) return null;
                var bytes = ProtectedData.Unprotect(File.ReadAllBytes(KeyFile), null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(bytes);
            }
            catch (Exception) { return null; }
        }
    }

    public void SaveApiKey(string key)
    {
        try
        {
            var trimmed = key.Trim();
            if (trimmed.Length == 0) { File.Delete(KeyFile); return; }
            Directory.CreateDirectory(Path.GetDirectoryName(KeyFile)!);
            File.WriteAllBytes(KeyFile, ProtectedData.Protect(Encoding.UTF8.GetBytes(trimmed), null, DataProtectionScope.CurrentUser));
        }
        catch (Exception) { }
    }

    public CustomProvider Copy() => (CustomProvider)MemberwiseClone();
}

/// A ring in the usage widget: a built-in provider or a custom one.
public sealed class UsageSource
{
    public string Id { get; }
    public string Title { get; }
    public AIProvider? BuiltIn { get; }
    public CustomProvider? Custom { get; }

    public UsageSource(AIProvider provider)
    {
        Id = provider.Key();
        Title = provider.Title();
        BuiltIn = provider;
    }

    public UsageSource(CustomProvider provider)
    {
        Id = provider.Key;
        Title = provider.Name;
        Custom = provider;
    }

    /// Resolves a saved key ("claude", "custom:<uuid>") against the custom and config providers.
    public static UsageSource? Resolve(string key, IEnumerable<CustomProvider> customs)
    {
        if (AIProviders.FromKey(key) is { } provider) return new UsageSource(provider);
        var custom = customs.FirstOrDefault(c => c.Key == key);
        return custom != null ? new UsageSource(custom) : null;
    }

    /// The provider's mark at `size`, white.
    public FrameworkElement GlyphView(double size, Brush? brush = null)
    {
        brush ??= Brushes.White;
        if (BuiltIn is { } provider)
        {
            return new System.Windows.Shapes.Path
            {
                Data = provider.Glyph(),
                Fill = brush,
                Stretch = Stretch.Uniform,
                Width = size,
                Height = size,
            };
        }
        if (Custom?.LogoFile is { } file && File.Exists(file) && !file.EndsWith(".svg", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var image = new System.Windows.Media.Imaging.BitmapImage();
                image.BeginInit();
                image.UriSource = new Uri(file);
                image.DecodePixelWidth = 96;
                image.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
                image.EndInit();
                image.Freeze();
                if (Custom.TintLogo ?? true)
                    return new System.Windows.Controls.Border { Width = size, Height = size, Background = brush, OpacityMask = new ImageBrush(image) { Stretch = Stretch.Uniform } };
                return new System.Windows.Controls.Image { Source = image, Width = size, Height = size };
            }
            catch (Exception) { }
        }
        return Ui.Icon(Glyphs.Sparkle, size * 0.8, brush);
    }
}

/// A usage provider defined in a JSON file, so providers (and their logos) can be
/// written by hand, shared and imported. See docs/provider-config.md.
public sealed class ProviderConfig
{
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("url")] public string Url { get; set; } = "";
    [JsonPropertyName("authHeader")] public string? AuthHeader { get; set; }
    [JsonPropertyName("authPrefix")] public string? AuthPrefix { get; set; }
    [JsonPropertyName("apiKeyFile")] public string? ApiKeyFile { get; set; }
    [JsonPropertyName("mode")] public string? Mode { get; set; }
    [JsonPropertyName("value")] public string Value { get; set; } = "";
    [JsonPropertyName("limit")] public string? Limit { get; set; }
    [JsonPropertyName("reset")] public string? Reset { get; set; }
    [JsonPropertyName("label")] public string? Label { get; set; }
    [JsonPropertyName("symbol")] public string? Symbol { get; set; }
    [JsonPropertyName("logo")] public string? Logo { get; set; }
    [JsonPropertyName("tintLogo")] public bool? TintLogo { get; set; }
}

public static class ProviderConfigStore
{
    public static readonly string ProvidersFolder = Path.Combine(AppSettings.Folder, "Providers");
    /// Logos chosen in Settings (and ones embedded in configs) are kept here.
    public static readonly string LogosFolder = Path.Combine(AppSettings.Folder, "Logos");

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static string ExpandHome(string path) =>
        path.StartsWith("~")
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), path[1..].TrimStart('/', '\\'))
            : Environment.ExpandEnvironmentVariables(path);

    public static void EnsureFolders()
    {
        try
        {
            Directory.CreateDirectory(ProvidersFolder);
            Directory.CreateDirectory(LogosFolder);
        }
        catch (Exception) { }
    }

    /// Every valid config in the Providers folder, sorted by file name.
    public static List<CustomProvider> LoadAll()
    {
        EnsureFolders();
        var list = new List<CustomProvider>();
        string[] files;
        try { files = Directory.GetFiles(ProvidersFolder, "*.json"); }
        catch (Exception) { return list; }
        foreach (var file in files.OrderBy(f => f, StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var config = JsonSerializer.Deserialize<ProviderConfig>(File.ReadAllText(file), Options);
                if (config != null && config.Name.Length > 0) list.Add(ToProvider(config, Path.GetFileName(file)));
            }
            catch (Exception) { }
        }
        return list;
    }

    private static CustomProvider ToProvider(ProviderConfig config, string file) => new()
    {
        Id = StableId(file),
        Name = config.Name,
        Url = config.Url,
        AuthHeader = config.AuthHeader ?? "Authorization",
        AuthPrefix = config.AuthPrefix ?? "Bearer ",
        ApiKeyFile = config.ApiKeyFile,
        Mode = config.Mode switch
        {
            "usedAndLimit" => CustomMode.UsedAndLimit,
            "remainingAndLimit" => CustomMode.RemainingAndLimit,
            _ => CustomMode.Percent,
        },
        ValuePath = config.Value,
        LimitPath = config.Limit ?? "",
        ResetPath = config.Reset ?? "",
        Label = config.Label ?? "Usage",
        TintLogo = config.TintLogo,
        LogoPath = ResolveLogo(config.Logo, file),
        ConfigFile = file,
    };

    /// Copies a config (and a logo it references by file name) into the Providers folder.
    public static string Import(string path)
    {
        EnsureFolders();
        var text = File.ReadAllText(path);
        var config = JsonSerializer.Deserialize<ProviderConfig>(text, Options) ?? throw new InvalidDataException();
        var name = Path.GetFileName(path);
        if (File.Exists(Path.Combine(ProvidersFolder, name)))
            name = Path.GetFileNameWithoutExtension(path) + $"-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.json";
        File.WriteAllText(Path.Combine(ProvidersFolder, name), text);
        if (config.Logo is { } logo && !logo.StartsWith("data:") && !Path.IsPathRooted(logo) && !logo.StartsWith("~"))
        {
            var source = Path.Combine(Path.GetDirectoryName(path) ?? "", logo);
            var target = Path.Combine(ProvidersFolder, logo);
            if (File.Exists(source) && !File.Exists(target)) File.Copy(source, target);
        }
        return name;
    }

    /// Writes a provider as a shareable config with its logo embedded (never the API key).
    public static void Export(CustomProvider provider, string path)
    {
        var config = new ProviderConfig
        {
            Name = provider.Name,
            Url = provider.Url,
            AuthHeader = provider.AuthHeader,
            AuthPrefix = provider.AuthPrefix,
            ApiKeyFile = provider.ApiKeyFile,
            Mode = provider.Mode switch
            {
                CustomMode.UsedAndLimit => "usedAndLimit",
                CustomMode.RemainingAndLimit => "remainingAndLimit",
                _ => "percent",
            },
            Value = provider.ValuePath,
            Limit = provider.LimitPath.Length > 0 ? provider.LimitPath : null,
            Reset = provider.ResetPath.Length > 0 ? provider.ResetPath : null,
            Label = provider.Label,
            TintLogo = provider.TintLogo,
        };
        if (provider.LogoFile is { } logo && File.Exists(logo))
        {
            var extension = Path.GetExtension(logo).TrimStart('.').ToLowerInvariant();
            var type = extension == "svg" ? "svg+xml" : extension;
            config.Logo = $"data:image/{type};base64,{Convert.ToBase64String(File.ReadAllBytes(logo))}";
        }
        File.WriteAllText(path, JsonSerializer.Serialize(config, Options));
    }

    /// Copies a chosen logo into the Logos folder; returns its file name.
    public static string StoreLogo(string path)
    {
        EnsureFolders();
        var extension = Path.GetExtension(path);
        var name = $"{Guid.NewGuid()}{(extension.Length > 0 ? extension.ToLowerInvariant() : ".png")}";
        File.Copy(path, Path.Combine(LogosFolder, name));
        return name;
    }

    /// Where a config's logo lives: next to the config, at a path, or decoded from a data URL.
    private static string? ResolveLogo(string? logo, string configFile)
    {
        if (string.IsNullOrEmpty(logo)) return null;
        if (logo.StartsWith("data:") && logo.IndexOf(',') is var comma and > 0)
        {
            try
            {
                var data = Convert.FromBase64String(logo[(comma + 1)..]);
                var type = logo.Contains("svg") ? "svg" : logo.Contains("jpeg") || logo.Contains("jpg") ? "jpg" : "png";
                var file = Path.Combine(LogosFolder, $"config-{StableId(configFile)}.{type}");
                EnsureFolders();
                if (!File.Exists(file)) File.WriteAllBytes(file, data);
                return file;
            }
            catch (FormatException) { return null; }
        }
        if (Path.IsPathRooted(logo) || logo.StartsWith("~")) return logo;
        return Path.Combine(ProvidersFolder, logo);
    }

    /// The same config file always gets the same id, so its order and on/off state stick.
    public static Guid StableId(string file) => new(MD5.HashData(Encoding.UTF8.GetBytes(file)));
}
