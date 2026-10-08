using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Lenotch.AI;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace Lenotch.Settings;

/// Signs in to the DeepSeek Platform in Lenotch's own window, the way codenotch does.
/// The page runs in a private WebView2 profile in a temporary folder (nothing is read
/// from Edge or Chrome, and the folder is deleted afterwards); once the user has signed
/// in, the Platform's session token is taken from the page, checked once and kept
/// encrypted for this Windows user.
public sealed class DeepSeekSignIn : Window
{
    private const string TokenScript = """
        (() => {
            const raw = localStorage.getItem('userToken');
            if (!raw) return null;
            const pick = (value) => {
                if (typeof value === 'string') return value.trim() || null;
                if (!value || typeof value !== 'object') return null;
                for (const key of ['value', 'token', 'access_token', 'accessToken']) {
                    const found = pick(value[key]);
                    if (found) return found;
                }
                return null;
            };
            try { return pick(JSON.parse(raw)); } catch (_) { return raw.trim() || null; }
        })()
        """;

    private readonly WebView2 webView = new();
    private readonly DispatcherTimer poll = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly string profile = Path.Combine(Path.GetTempPath(), "Lenotch-DeepSeek-" + Guid.NewGuid().ToString("N"));
    private string? checkedToken;
    private bool checking;

    /// Whether an account was signed in before the window closed.
    public bool SignedIn { get; private set; }

    public DeepSeekSignIn()
    {
        Title = "Sign in to DeepSeek";
        Width = 1000;
        Height = 760;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        Content = webView;
        poll.Tick += async (_, _) => await Check();
        Loaded += async (_, _) => await Start();
        Closed += (_, _) =>
        {
            poll.Stop();
            webView.Dispose();
            // The browser processes take a moment to let go of the profile folder.
            _ = Task.Run(async () =>
            {
                for (var attempt = 0; attempt < 10; attempt++)
                {
                    try { Directory.Delete(profile, true); return; }
                    catch (DirectoryNotFoundException) { return; }
                    catch (Exception) { await Task.Delay(500); }
                }
            });
        };
    }

    private async Task Start()
    {
        try
        {
            var environment = await CoreWebView2Environment.CreateAsync(null, profile);
            var options = environment.CreateCoreWebView2ControllerOptions();
            options.IsInPrivateModeEnabled = true;
            await webView.EnsureCoreWebView2Async(environment, options);
        }
        catch (Exception)
        {
            MessageBox.Show(this, "Signing in needs the Microsoft Edge WebView2 Runtime. Install it from microsoft.com/edge/webview2, or use an API key instead.", "Lenotch");
            Close();
            return;
        }
        webView.CoreWebView2.Navigate(DeepSeekUsage.Platform);
        poll.Start();
    }

    /// Looks for the session token the Platform keeps in the page's local storage once
    /// signed in. Reading it is local; only a token that turns up is checked with DeepSeek.
    private async Task Check()
    {
        if (checking || webView.CoreWebView2 is not { } core) return;
        if (!Uri.TryCreate(core.Source, UriKind.Absolute, out var url) || url.Host != new Uri(DeepSeekUsage.Platform).Host) return;
        checking = true;
        try
        {
            var result = await core.ExecuteScriptAsync(TokenScript);
            var token = JsonSerializer.Deserialize<string?>(result)?.Trim();
            if (string.IsNullOrEmpty(token)) return;
            if (token.StartsWith("Bearer ", StringComparison.Ordinal)) token = token[7..];
            if (token == checkedToken) return;
            checkedToken = token;
            await DeepSeekUsage.FetchAccount(token);
            DeepSeekUsage.SaveSessionToken(token);
            SignedIn = true;
            Close();
        }
        catch (Exception) { }
        finally { checking = false; }
    }
}
