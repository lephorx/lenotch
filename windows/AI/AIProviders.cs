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
public enum AIProvider { Claude, Codex, Cursor, Copilot, Grok, Kimi, Opencode, Amp, DeepSeek }

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
        AIProvider.DeepSeek => "DeepSeek",
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
        AIProvider.DeepSeek => "Sign in or API key (add it here), or DEEPSEEK_API_KEY",
        _ => @"%USERPROFILE%\.local\share\amp\secrets.json",
    };

    public static Geometry Glyph(this AIProvider provider) => provider switch
    {
        AIProvider.Claude => GlyphOutline.Claude,
        AIProvider.Codex => GlyphOutline.Openai,
        AIProvider.Cursor => GlyphOutline.Cursor,
        AIProvider.Copilot => CopilotGlyph,
        AIProvider.Grok => GlyphOutline.Grok,
        AIProvider.Kimi => GlyphOutline.Kimi,
        AIProvider.Opencode => GlyphOutline.Opencode,
        AIProvider.DeepSeek => DeepSeekGlyph,
        _ => AmpGlyph,
    };

    /// Resources/glyph-deepseek.svg (viewBox 0 0 24 24), fitted into the unit box.
    private static readonly Geometry DeepSeekGlyph = MakeDeepSeek();

    private static Geometry MakeDeepSeek()
    {
        // Parsed geometry can come back frozen; clone it to set the transform.
        var geometry = Geometry.Parse("F0 M 23.748 4.482 c -.254 -.124 -.364 .113 -.512 .234 -.051 .039 -.094 .09 -.137 .136 -.372 .397 -.806 .657 -1.373 .626 -.829 -.046 -1.537 .214 -2.163 .848 -.133 -.782 -.575 -1.248 -1.247 -1.548 -.352 -.156 -.708 -.311 -.955 -.65 -.172 -.241 -.219 -.51 -.305 -.774 -.055 -.16 -.11 -.323 -.293 -.35 -.2 -.031 -.278 .136 -.356 .276 -.313 .572 -.434 1.202 -.422 1.84 .027 1.436 .633 2.58 1.838 3.393 .137 .093 .172 .187 .129 .323 -.082 .28 -.18 .552 -.266 .833 -.055 .179 -.137 .217 -.329 .14 a 5.526 5.526 0 0 1 -1.736 -1.18 c -.857 -.828 -1.631 -1.742 -2.597 -2.458 a 11.365 11.365 0 0 0 -.689 -.471 c -.985 -.957 .13 -1.743 .388 -1.836 .27 -.098 .093 -.432 -.779 -.428 -.872 .004 -1.67 .295 -2.687 .684 a 3.055 3.055 0 0 1 -.465 .137 9.597 9.597 0 0 0 -2.883 -.102 c -1.885 .21 -3.39 1.102 -4.497 2.623 C .082 8.606 -.231 10.684 .152 12.85 c .403 2.284 1.569 4.175 3.36 5.653 1.858 1.533 3.997 2.284 6.438 2.14 1.482 -.085 3.133 -.284 4.994 -1.86 .47 .234 .962 .327 1.78 .397 .63 .059 1.236 -.03 1.705 -.128 .735 -.156 .684 -.837 .419 -.961 -2.155 -1.004 -1.682 -.595 -2.113 -.926 1.096 -1.296 2.746 -2.642 3.392 -7.003 .05 -.347 .007 -.565 0 -.845 -.004 -.17 .035 -.237 .23 -.256 a 4.173 4.173 0 0 0 1.545 -.475 c 1.396 -.763 1.96 -2.015 2.093 -3.517 .02 -.23 -.004 -.467 -.247 -.588 z M 11.581 18 c -2.089 -1.642 -3.102 -2.183 -3.52 -2.16 -.392 .024 -.321 .471 -.235 .763 .09 .288 .207 .486 .371 .739 .114 .167 .192 .416 -.113 .603 -.673 .416 -1.842 -.14 -1.897 -.167 -1.361 -.802 -2.5 -1.86 -3.301 -3.307 -.774 -1.393 -1.224 -2.887 -1.298 -4.482 -.02 -.386 .093 -.522 .477 -.592 a 4.696 4.696 0 0 1 1.529 -.039 c 2.132 .312 3.946 1.265 5.468 2.774 .868 .86 1.525 1.887 2.202 2.891 .72 1.066 1.494 2.082 2.48 2.914 .348 .292 .625 .514 .891 .677 -.802 .09 -2.14 .11 -3.054 -.614 z m 1 -6.44 a .306 .306 0 0 1 .415 -.287 .302 .302 0 0 1 .2 .288 .306 .306 0 0 1 -.31 .307 .303 .303 0 0 1 -.304 -.308 z m 3.11 1.596 c -.2 .081 -.399 .151 -.59 .16 a 1.245 1.245 0 0 1 -.798 -.254 c -.274 -.23 -.47 -.358 -.552 -.758 a 1.73 1.73 0 0 1 .016 -.588 c .07 -.327 -.008 -.537 -.239 -.727 -.187 -.156 -.426 -.199 -.688 -.199 a .559 .559 0 0 1 -.254 -.078 c -.11 -.054 -.2 -.19 -.114 -.358 .028 -.054 .16 -.186 .192 -.21 .356 -.202 .767 -.136 1.146 .016 .352 .144 .618 .408 1.001 .782 .391 .451 .462 .576 .685 .914 .176 .265 .336 .537 .445 .848 .067 .195 -.019 .354 -.25 .452 z").Clone();
        geometry.Transform = new ScaleTransform(1 / 24.0, 1 / 24.0);
        var flat = geometry.GetFlattenedPathGeometry();
        flat.Freeze();
        return flat;
    }

    /// Resources/glyph-copilot.svg (viewBox 0 0 24 24), fitted into the unit box.
    private static readonly Geometry CopilotGlyph = MakeCopilot();

    private static Geometry MakeCopilot()
    {
        // Parsed geometry can come back frozen; clone it to set the transform.
        var geometry = Geometry.Parse("F0 M10.759 2.301C7.457 2.699 4.78 4.415 3.606 6.878C3.166 7.808 2.785 9.38 2.67 10.753C2.635 11.169 2.642 11.155 2.429 11.155C2.034 11.155 1.544 11.33 1.282 11.567C1.08 11.749 0.238 12.881 0.147 13.094C-0.004 13.44 -0.007 13.514 0.003 15.191L0.014 16.798L0.108 16.973C0.22 17.186 0.412 17.371 0.8 17.64C3.613 19.604 6.779 21.012 9.518 21.512C11.175 21.816 12.915 21.816 14.55 21.516C17.367 20.998 20.211 19.73 23.146 17.679C23.586 17.371 23.775 17.193 23.89 16.973L23.985 16.798L23.995 15.177C24.009 13.129 24.048 13.308 23.356 12.361C22.891 11.721 22.702 11.515 22.465 11.386C22.248 11.267 21.808 11.155 21.57 11.155C21.35 11.155 21.375 11.211 21.294 10.509C20.913 7.175 19.949 5.393 17.719 3.894C16.514 3.08 15.12 2.57 13.449 2.329C12.908 2.248 11.321 2.234 10.759 2.301ZM8.68 4.9C9.99 5.051 10.444 5.603 10.504 7.119C10.549 8.297 10.298 9.233 9.801 9.736C8.806 10.739 7.107 11.117 5.811 10.617C4.861 10.257 4.595 9.719 4.595 8.185C4.595 7.49 4.602 7.406 4.689 7.035C4.871 6.263 5.189 5.777 5.717 5.463C6.478 5.012 7.666 4.788 8.68 4.9ZM16.804 4.953C17.562 5.082 18.314 5.41 18.687 5.774C19.152 6.225 19.425 7.109 19.425 8.181C19.425 9.226 19.187 10.019 18.789 10.306C17.534 11.2 15.392 10.931 14.183 9.722C13.32 8.859 13.226 6.249 14.026 5.393C14.459 4.932 15.602 4.75 16.804 4.953ZM12.807 7.535C12.81 7.535 12.807 7.752 12.796 8.01L12.775 8.482L11.996 8.482L11.213 8.482L11.213 8.185C11.213 8.021 11.203 7.808 11.192 7.706L11.168 7.525L11.426 7.511C11.646 7.497 12.793 7.518 12.807 7.535ZM12.88 9.673C12.936 9.691 12.971 9.736 12.999 9.841C13.47 11.606 16.294 12.605 18.16 11.665L18.397 11.546L18.628 11.641C19.068 11.829 19.309 12.064 19.39 12.385C19.481 12.738 19.54 17.707 19.46 18.004C19.362 18.36 19.156 18.504 18.111 18.926C15.847 19.838 14.044 20.219 12.017 20.219C9.854 20.223 7.894 19.782 5.507 18.766C4.85 18.483 4.724 18.395 4.595 18.137L4.504 17.955L4.504 16.522C4.508 14.618 4.56 12.507 4.612 12.347C4.714 12.036 4.965 11.805 5.399 11.63L5.601 11.546L5.881 11.686C6.835 12.165 8.222 12.14 9.319 11.62C10.158 11.225 10.72 10.652 10.955 9.964C11.003 9.824 11.049 9.701 11.059 9.691C11.122 9.628 12.656 9.614 12.88 9.673ZM9.131 13.797C8.928 13.87 8.711 14.066 8.599 14.279L8.505 14.457L8.505 15.593C8.505 16.907 8.512 16.942 8.799 17.214C9.291 17.672 9.99 17.571 10.333 16.991L10.427 16.833L10.437 15.673C10.448 14.545 10.444 14.51 10.371 14.335C10.175 13.877 9.602 13.629 9.131 13.797ZM14.166 13.783C13.841 13.902 13.589 14.195 13.519 14.531C13.491 14.66 13.481 15.062 13.491 15.743C13.502 16.725 13.505 16.77 13.582 16.928C13.946 17.661 14.962 17.689 15.347 16.973C15.42 16.84 15.424 16.784 15.434 15.67L15.445 14.506L15.361 14.324C15.26 14.101 15.092 13.93 14.882 13.835C14.7 13.755 14.32 13.723 14.166 13.783Z").Clone();
        geometry.Transform = new ScaleTransform(1 / 24.0, 1 / 24.0);
        var flat = geometry.GetFlattenedPathGeometry();
        flat.Freeze();
        return flat;
    }

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
