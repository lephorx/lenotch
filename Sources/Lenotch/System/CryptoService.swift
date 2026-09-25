import Foundation
import Observation
import SwiftUI

/// A coin Lenotch can show, with its CoinGecko id.
struct Coin: Identifiable, Hashable {
    let id: String
    let symbol: String
    let name: String
    let color: Color

    static let all: [Coin] = [
        Coin(id: "bitcoin", symbol: "BTC", name: "Bitcoin", color: Color(red: 0.97, green: 0.58, blue: 0.10)),
        Coin(id: "ethereum", symbol: "ETH", name: "Ethereum", color: Color(red: 0.38, green: 0.47, blue: 0.93)),
        Coin(id: "solana", symbol: "SOL", name: "Solana", color: Color(red: 0.60, green: 0.30, blue: 0.98)),
        Coin(id: "ripple", symbol: "XRP", name: "XRP", color: Color(white: 0.75)),
        Coin(id: "binancecoin", symbol: "BNB", name: "BNB", color: Color(red: 0.95, green: 0.73, blue: 0.18)),
        Coin(id: "cardano", symbol: "ADA", name: "Cardano", color: Color(red: 0.20, green: 0.45, blue: 0.95)),
        Coin(id: "dogecoin", symbol: "DOGE", name: "Dogecoin", color: Color(red: 0.80, green: 0.67, blue: 0.28)),
        Coin(id: "litecoin", symbol: "LTC", name: "Litecoin", color: Color(red: 0.55, green: 0.60, blue: 0.70)),
        Coin(id: "polkadot", symbol: "DOT", name: "Polkadot", color: Color(red: 0.90, green: 0.00, blue: 0.48)),
        Coin(id: "tron", symbol: "TRX", name: "TRON", color: Color(red: 0.92, green: 0.18, blue: 0.18)),
    ]

    static func with(id: String) -> Coin? { all.first { $0.id == id } }
}

struct CoinPrice: Equatable {
    let coin: Coin
    let price: Double
    /// Percent change over the last 24 hours.
    let change: Double
}

/// Prices for the chosen coins from CoinGecko's free API (no account), refreshed
/// every minute while the ticker is on.
@Observable
final class CryptoService {
    private(set) var prices: [CoinPrice] = []

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastKey = ""
    @ObservationIgnored private var lastFetch = Date.distantPast
    @ObservationIgnored private var isFetching = false

    static let currencies = ["usd", "eur", "chf", "gbp", "jpy"]

    init(settings: AppSettings) {
        self.settings = settings
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    /// Fetches when the coins or currency changed, or the prices are over a minute old.
    func refresh() {
        guard settings.showCrypto, !settings.cryptoCoins.isEmpty else { return }
        let coins = settings.cryptoCoins.compactMap(Coin.with)
        let currency = settings.cryptoCurrency
        let key = coins.map(\.id).joined(separator: ",") + "/" + currency
        guard !isFetching, key != lastKey || Date().timeIntervalSince(lastFetch) > 55 else { return }
        if key != lastKey { prices = [] }
        isFetching = true
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: coins.map(\.id).joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: currency),
            URLQueryItem(name: "include_24hr_change", value: "true"),
        ]
        URLSession.shared.dataTask(with: URLRequest(url: components.url!, timeoutInterval: 15)) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: Double]] }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                guard let json else { return }  // Keep the last prices (e.g. rate limited).
                self.lastKey = key
                self.lastFetch = Date()
                self.prices = coins.compactMap { coin in
                    guard let values = json[coin.id], let price = values[currency] else { return nil }
                    return CoinPrice(coin: coin, price: price, change: values["\(currency)_24h_change"] ?? 0)
                }
            }
        }.resume()
    }

    /// "$84,095", "$2,675.88", "$0.2412".
    static func format(_ price: Double, currency: String) -> String {
        let digits = price >= 1000 ? 0 : price >= 1 ? 2 : 4
        return price.formatted(.currency(code: currency.uppercased())
            .precision(.fractionLength(digits))
            .locale(Locale(identifier: "en_US")))
    }
}
