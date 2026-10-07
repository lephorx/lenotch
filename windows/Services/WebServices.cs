using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Media;
using System.Windows.Threading;
using Lenotch.Core;

namespace Lenotch.Services;

public static class Http
{
    public static readonly HttpClient Client = Create();

    private static HttpClient Create()
    {
        var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("Lenotch");
        return client;
    }

    public static async Task<JsonElement?> GetJson(string url)
    {
        try
        {
            using var response = await Client.GetAsync(url);
            if (!response.IsSuccessStatusCode) return null;
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            return document.RootElement.Clone();
        }
        catch (Exception)
        {
            return null;
        }
    }

    public static double? Number(this JsonElement element, string name)
    {
        if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(name, out var value)) return null;
        return value.ValueKind switch
        {
            JsonValueKind.Number => value.GetDouble(),
            JsonValueKind.String when double.TryParse(value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var n) => n,
            _ => null,
        };
    }

    public static string? Text(this JsonElement element, string name) =>
        element.ValueKind == JsonValueKind.Object && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}

// MARK: - Weather

/// What the sky is doing, grouped for the animated scene.
public enum WeatherKind { Clear, PartlyCloudy, Cloudy, Fog, Drizzle, Rain, Snow, Thunderstorm }

public static class WeatherKinds
{
    /// From a WMO weather code (Open-Meteo's `weather_code`).
    public static WeatherKind FromCode(int code) => code switch
    {
        0 => WeatherKind.Clear,
        1 or 2 => WeatherKind.PartlyCloudy,
        3 => WeatherKind.Cloudy,
        45 or 48 => WeatherKind.Fog,
        >= 51 and <= 57 => WeatherKind.Drizzle,
        (>= 61 and <= 67) or (>= 80 and <= 82) => WeatherKind.Rain,
        (>= 71 and <= 77) or 85 or 86 => WeatherKind.Snow,
        >= 95 and <= 99 => WeatherKind.Thunderstorm,
        _ => WeatherKind.Cloudy,
    };

    public static string Title(this WeatherKind kind) => kind switch
    {
        WeatherKind.Clear => "Clear",
        WeatherKind.PartlyCloudy => "Partly cloudy",
        WeatherKind.Cloudy => "Cloudy",
        WeatherKind.Fog => "Fog",
        WeatherKind.Drizzle => "Drizzle",
        WeatherKind.Rain => "Rain",
        WeatherKind.Snow => "Snow",
        _ => "Thunderstorm",
    };
}

public sealed record WeatherReading(double Temperature, double High, double Low, WeatherKind Kind, bool IsDay);

/// Current weather from Open-Meteo (free, no account or key), for a city the user
/// chose or, without one, an approximate place from the IP address (Zurich if that fails).
public sealed class WeatherService
{
    private readonly AppSettings settings;
    private (WeatherPlace place, bool fahrenheit, DateTime date)? lastFetch;
    private WeatherPlace? approximatePlace;

    public static readonly WeatherPlace Zurich = new("Zurich", 47.3769, 8.5417);

    public event Action? Changed;
    public WeatherReading? Reading { get; private set; }
    public string? PlaceName { get; private set; }

    public WeatherService(AppSettings settings)
    {
        this.settings = settings;
    }

    /// Reloads when the place changed or the last reading is older than 15 minutes.
    public async Task RefreshIfNeeded()
    {
        WeatherPlace place;
        if (settings.WeatherPlace is { } chosen)
        {
            place = chosen;
        }
        else
        {
            approximatePlace ??= await PlaceFromIP() ?? Zurich;
            place = approximatePlace;
        }
        PlaceName = place.Name;
        var fahrenheit = settings.WeatherFahrenheit;
        if (lastFetch is { } last && last.place == place && last.fahrenheit == fahrenheit
            && (DateTime.UtcNow - last.date).TotalMinutes < 15) return;
        lastFetch = (place, fahrenheit, DateTime.UtcNow);
        Reading = await Fetch(place, fahrenheit) ?? Reading;
        Changed?.Invoke();
    }

    private static async Task<WeatherPlace?> PlaceFromIP()
    {
        foreach (var url in new[] { "https://ipwho.is/", "https://get.geojs.io/v1/ip/geo.json" })
        {
            if (await Http.GetJson(url) is not { } root) continue;
            if (root.Number("latitude") is { } latitude && root.Number("longitude") is { } longitude)
                return new WeatherPlace(root.Text("city") ?? "Your area", latitude, longitude);
        }
        return null;
    }

    public sealed record SearchResult(WeatherPlace Place, string Detail);

    public static async Task<List<SearchResult>> Search(string query)
    {
        var text = query.Trim();
        if (text.Length < 2) return new();
        var language = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        var url = $"https://geocoding-api.open-meteo.com/v1/search?name={Uri.EscapeDataString(text)}&count=6&language={language}";
        if (await Http.GetJson(url) is not { } root || !root.TryGetProperty("results", out var results)) return new();
        var list = new List<SearchResult>();
        foreach (var item in results.EnumerateArray())
        {
            if (item.Text("name") is not { } name || item.Number("latitude") is not { } lat || item.Number("longitude") is not { } lon) continue;
            var detail = string.Join(", ", new[] { item.Text("admin1"), item.Text("country") }.Where(s => !string.IsNullOrEmpty(s)));
            list.Add(new SearchResult(new WeatherPlace(name, lat, lon), detail));
        }
        return list;
    }

    private static async Task<WeatherReading?> Fetch(WeatherPlace place, bool fahrenheit)
    {
        var url = "https://api.open-meteo.com/v1/forecast"
                  + $"?latitude={place.Latitude.ToString(CultureInfo.InvariantCulture)}"
                  + $"&longitude={place.Longitude.ToString(CultureInfo.InvariantCulture)}"
                  + "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min"
                  + "&forecast_days=1&timezone=auto&temperature_unit=" + (fahrenheit ? "fahrenheit" : "celsius");
        if (await Http.GetJson(url) is not { } root
            || !root.TryGetProperty("current", out var current)
            || current.Number("temperature_2m") is not { } temperature
            || current.Number("weather_code") is not { } code) return null;
        double high = temperature, low = temperature;
        if (root.TryGetProperty("daily", out var daily))
        {
            if (daily.TryGetProperty("temperature_2m_max", out var max) && max.GetArrayLength() > 0) high = max[0].GetDouble();
            if (daily.TryGetProperty("temperature_2m_min", out var min) && min.GetArrayLength() > 0) low = min[0].GetDouble();
        }
        return new WeatherReading(temperature, high, low, WeatherKinds.FromCode((int)code), current.Number("is_day") != 0);
    }
}

// MARK: - Crypto

public sealed record Coin(string Id, string Symbol, string Name, Color Color)
{
    public static readonly Coin[] All =
    {
        new("bitcoin", "BTC", "Bitcoin", Color.FromRgb(247, 148, 26)),
        new("ethereum", "ETH", "Ethereum", Color.FromRgb(97, 120, 237)),
        new("solana", "SOL", "Solana", Color.FromRgb(153, 77, 250)),
        new("ripple", "XRP", "XRP", Color.FromRgb(191, 191, 191)),
        new("binancecoin", "BNB", "BNB", Color.FromRgb(242, 186, 46)),
        new("cardano", "ADA", "Cardano", Color.FromRgb(51, 115, 242)),
        new("dogecoin", "DOGE", "Dogecoin", Color.FromRgb(204, 171, 71)),
        new("litecoin", "LTC", "Litecoin", Color.FromRgb(140, 153, 179)),
        new("polkadot", "DOT", "Polkadot", Color.FromRgb(230, 0, 122)),
        new("tron", "TRX", "TRON", Color.FromRgb(235, 46, 46)),
    };

    public static Coin? With(string id) => All.FirstOrDefault(c => c.Id == id);
}

public sealed record CoinPrice(Coin Coin, double Price, double Change);

/// Prices for the chosen coins from CoinGecko's free API (no account), refreshed
/// every minute while the ticker is on.
public sealed class CryptoService
{
    private readonly AppSettings settings;
    private string lastKey = "";
    private DateTime lastFetch = DateTime.MinValue;
    private bool isFetching;

    public static readonly string[] Currencies = { "usd", "eur", "chf", "gbp", "jpy" };

    public event Action? Changed;
    public List<CoinPrice> Prices { get; private set; } = new();

    public CryptoService(AppSettings settings)
    {
        this.settings = settings;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(60) };
        timer.Tick += (_, _) => Refresh();
        timer.Start();
        settings.Changed += name =>
        {
            if (name is nameof(AppSettings.ShowCrypto) or nameof(AppSettings.CryptoCoins) or nameof(AppSettings.CryptoCurrency))
            {
                if (!settings.ShowCrypto && Prices.Count > 0) { Prices = new(); Changed?.Invoke(); }
                Refresh();
            }
        };
        Refresh();
    }

    public async void Refresh()
    {
        if (!settings.ShowCrypto || settings.CryptoCoins.Count == 0) return;
        var coins = settings.CryptoCoins.Select(Coin.With).OfType<Coin>().ToList();
        var currency = settings.CryptoCurrency;
        var key = string.Join(",", coins.Select(c => c.Id)) + "/" + currency;
        if (isFetching || (key == lastKey && (DateTime.UtcNow - lastFetch).TotalSeconds <= 55)) return;
        if (key != lastKey) { Prices = new(); Changed?.Invoke(); }
        isFetching = true;
        var url = "https://api.coingecko.com/api/v3/simple/price?ids=" + string.Join(",", coins.Select(c => c.Id))
                  + "&vs_currencies=" + currency + "&include_24hr_change=true";
        var json = await Http.GetJson(url);
        isFetching = false;
        // Keep the last prices (e.g. rate limited).
        if (json is not { } root) return;
        lastKey = key;
        lastFetch = DateTime.UtcNow;
        Prices = coins.Select(coin => root.TryGetProperty(coin.Id, out var values) && values.Number(currency) is { } price
                ? new CoinPrice(coin, price, values.Number(currency + "_24h_change") ?? 0)
                : null).OfType<CoinPrice>().ToList();
        Changed?.Invoke();
    }

    /// "$84,095", "$2,675.88", "$0.2412".
    public static string Format(double price, string currency)
    {
        var digits = price >= 1000 ? 0 : price >= 1 ? 2 : 4;
        var symbol = currency.ToLowerInvariant() switch
        {
            "usd" => "$",
            "eur" => "€",
            "gbp" => "£",
            "jpy" => "¥",
            "chf" => "CHF ",
            _ => currency.ToUpperInvariant() + " ",
        };
        return symbol + price.ToString("N" + digits, CultureInfo.GetCultureInfo("en-US"));
    }
}
