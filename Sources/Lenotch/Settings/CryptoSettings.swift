import SwiftUI

/// The crypto ticker in the closed notch: on/off, which coins and the currency.
struct CryptoSettings: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show crypto prices", isOn: $settings.showCrypto)
            } footer: {
                Text("Prices show beside the closed notch when no music is playing, switching coins every few seconds. From CoinGecko, updated every minute.")
            }
            Group {
                Section("Coins") {
                    ForEach(Coin.all) { coin in
                        Toggle(isOn: Binding(
                            get: { settings.cryptoCoins.contains(coin.id) },
                            set: { on in
                                if on {
                                    // Keep the catalogue order.
                                    let ids = Set(settings.cryptoCoins + [coin.id])
                                    settings.cryptoCoins = Coin.all.map(\.id).filter(ids.contains)
                                } else {
                                    settings.cryptoCoins.removeAll { $0 == coin.id }
                                }
                            })) {
                            HStack(spacing: 8) {
                                Circle().fill(coin.color.gradient).frame(width: 10, height: 10)
                                Text(coin.name)
                                Text(coin.symbol).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Picker("Currency", selection: $settings.cryptoCurrency) {
                        ForEach(CryptoService.currencies, id: \.self) { Text($0.uppercased()).tag($0) }
                    }
                }
            }
            .disabled(!settings.showCrypto)
        }
        .formStyle(.grouped)
    }
}
