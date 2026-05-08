import SwiftUI

struct OnboardingSymbolsStep: View {
    let onComplete: () -> Void

    @AppStorage("tracked_symbols") private var trackedSymbolsData: Data = Data()

    @State private var selectedSymbols: Set<String> = []

    private struct SymbolItem: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let category: String
    }

    private let allSymbols: [SymbolItem] = [
        // Crypto
        SymbolItem(id: "btc", symbol: "BTC", name: "Bitcoin", category: "Crypto"),
        SymbolItem(id: "eth", symbol: "ETH", name: "Ethereum", category: "Crypto"),
        SymbolItem(id: "sol", symbol: "SOL", name: "Solana", category: "Crypto"),
        SymbolItem(id: "xrp", symbol: "XRP", name: "Ripple", category: "Crypto"),
        SymbolItem(id: "ada", symbol: "ADA", name: "Cardano", category: "Crypto"),
        SymbolItem(id: "doge", symbol: "DOGE", name: "Dogecoin", category: "Crypto"),
        // US Stocks
        SymbolItem(id: "aapl", symbol: "AAPL", name: "Apple", category: "US Stocks"),
        SymbolItem(id: "msft", symbol: "MSFT", name: "Microsoft", category: "US Stocks"),
        SymbolItem(id: "nvda", symbol: "NVDA", name: "Nvidia", category: "US Stocks"),
        SymbolItem(id: "tsla", symbol: "TSLA", name: "Tesla", category: "US Stocks"),
        SymbolItem(id: "amzn", symbol: "AMZN", name: "Amazon", category: "US Stocks"),
        SymbolItem(id: "googl", symbol: "GOOGL", name: "Alphabet", category: "US Stocks"),
        SymbolItem(id: "meta", symbol: "META", name: "Meta", category: "US Stocks"),
        // ETFs
        SymbolItem(id: "spy", symbol: "SPY", name: "S&P 500 ETF", category: "ETFs"),
        SymbolItem(id: "qqq", symbol: "QQQ", name: "Nasdaq-100 ETF", category: "ETFs"),
        SymbolItem(id: "vti", symbol: "VTI", name: "Vanguard Total Stock", category: "ETFs"),
        SymbolItem(id: "tlt", symbol: "TLT", name: "iShares 20+ Year Treasury", category: "ETFs")
    ]

    private var groupedSymbols: [(category: String, symbols: [SymbolItem])] {
        [
            ("Crypto", allSymbols.filter { $0.category == "Crypto" }),
            ("US Stocks", allSymbols.filter { $0.category == "US Stocks" }),
            ("ETFs", allSymbols.filter { $0.category == "ETFs" })
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Track Markets")
                    .font(.largeTitle.bold())
                Text("Select symbols to watch. You can edit these anytime in the Markets tab.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 48)
            .padding(.horizontal, 32)
            .padding(.bottom, 16)

            // Symbol grid
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(groupedSymbols, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.leading, 4)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(group.symbols) { item in
                                    SymbolChip(
                                        symbol: item.symbol,
                                        name: item.name,
                                        isSelected: selectedSymbols.contains(item.id)
                                    ) {
                                        toggleSymbol(item.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Selected count
            Text("\(selectedSymbols.count) symbol\(selectedSymbols.count == 1 ? "" : "s") selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)

            // Page indicator
            OnboardingPageIndicator(total: 3, current: 2)
                .padding(.vertical, 12)

            // Done button
            Button {
                saveSymbols()
                onComplete()
            } label: {
                Text(selectedSymbols.isEmpty ? "Skip for Now" : "Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedSymbols.isEmpty ? Color.secondary : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    private func toggleSymbol(_ id: String) {
        if selectedSymbols.contains(id) {
            selectedSymbols.remove(id)
        } else {
            selectedSymbols.insert(id)
        }
    }

    private func saveSymbols() {
        struct CodableSymbol: Codable {
            let symbol: String
            var entryPrice: Double?
        }
        let symbols = selectedSymbols.map { id -> CodableSymbol in
            CodableSymbol(symbol: allSymbols.first { $0.id == id }?.symbol ?? id.uppercased(), entryPrice: nil)
        }
        if let encoded = try? JSONEncoder().encode(symbols) {
            trackedSymbolsData = encoded
        }
    }
}

// MARK: - Symbol Chip

struct SymbolChip: View {
    let symbol: String
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(symbol)
                    .font(.headline)
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingSymbolsStep(onComplete: {})
}