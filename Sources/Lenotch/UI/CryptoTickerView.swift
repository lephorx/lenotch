import SwiftUI

/// Closed notch while nothing else shows: a coin on the left of the notch, its
/// price and 24-hour change on the right, cycling through the chosen coins.
struct CryptoTickerView: View {
    let model: NotchViewModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let prices = model.crypto.prices
            if !prices.isEmpty {
                let index = Int(context.date.timeIntervalSinceReferenceDate / 5) % prices.count
                row(prices[index])
                    .id(prices[index].coin.id)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: index)
            }
        }
        .clipped()
    }

    private func row(_ price: CoinPrice) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(String(price.coin.symbol.prefix(1)))
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(price.coin.color.gradient))
                Text(price.coin.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 12)
            .frame(width: NotchGeometry.indicatorSideWidth, alignment: .leading)
            Spacer(minLength: model.geometry.notchSize.width)
            VStack(alignment: .trailing, spacing: 0) {
                Text(CryptoService.format(price.price, currency: model.settings.cryptoCurrency))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(String(format: "%@%.1f%%", price.change >= 0 ? "▲" : "▼", abs(price.change)))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(price.change >= 0 ? Color.green : Color.red)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.trailing, 12)
            .frame(width: NotchGeometry.indicatorSideWidth, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }
}
