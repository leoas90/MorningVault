import SwiftUI

struct MarketsView: View {
    @StateObject private var viewModel = MarketsViewModel()
    @State private var newSymbol: String = ""
    @State private var newEntryPrice: String = ""
    @State private var hasAppeared = false
    @State private var pricesLoadTaskStarted = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                symbolsSection
                addSymbolSection
                infoSection
            }
            .navigationTitle("Markets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
                if viewModel.isLoadingPrices {
                    ProgressView()
                } else {
                    Button {
                        Task { await viewModel.fetchLivePrices() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isFieldFocused {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isFieldFocused = false
                        }
                        .padding()
                    }
                    .background(.bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isFieldFocused)
            .task {
                guard !pricesLoadTaskStarted else { return }
                pricesLoadTaskStarted = true
                viewModel.load()
                withAnimation(.easeOut(duration: 0.35)) {
                    hasAppeared = true
                }
                // Debounce: skip if live prices were fetched within last 60 seconds
                await viewModel.fetchLivePricesIfStale(cooldown: 60)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 12)
        }
    }

    private var symbolsSection: some View {
        Section {
            ForEach(Array(viewModel.trackedSymbols.enumerated()), id: \.element.symbol) { index, item in
                SymbolRowView(
                    item: item,
                    sparklineData: viewModel.sparklineData(for: item.symbol),
                    isEstimated: viewModel.isEstimated(for: item.symbol),
                    delay: Double(index) * AppAnimation.cardStaggerDelay,
                    onDelete: { viewModel.remove(item.symbol) },
                    onPriceChange: { price in viewModel.updatePrice(for: item.symbol, price: price) }
                )
            }
            .onDelete { indexSet in
                for i in indexSet {
                    viewModel.remove(viewModel.trackedSymbols[i].symbol)
                }
            }
        } header: {
            Text("Tracked Symbols")
        } footer: {
            Text("Entry price enables P&L tracking. Tap a price to edit.")
                .font(.caption)
        }
    }

    private var addSymbolSection: some View {
        Section("Add Symbol") {
            HStack {
                TextField("Symbol (e.g. AAPL)", text: $newSymbol)
                    .textInputAutocapitalization(.characters)
                    .frame(maxWidth: 130)
                    .focused($isFieldFocused)
                TextField("Entry $", text: $newEntryPrice)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 100)
                    .focused($isFieldFocused)
                Button {
                    let sym = newSymbol.uppercased().trimmingCharacters(in: .whitespaces)
                    guard !sym.isEmpty else { return }
                    viewModel.add(symbol: sym, entryPrice: Double(newEntryPrice))
                    newSymbol = ""
                    newEntryPrice = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var infoSection: some View {
        Section {
            Text("Track up to 10 symbols. Prices are stored locally on your device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class MarketsViewModel: ObservableObject {
    @Published var trackedSymbols: [TrackedSymbol] = []
    @Published var prices: [String: (price: Double, change: Double)] = [:]  // symbol → (price, change24h%)
    @Published var isLoadingPrices = false

    // MARK: - Load symbols

    func load() {
        let data = UserDefaults.standard.data(forKey: "tracked_symbols") ?? Data()
        if let decoded = try? JSONDecoder().decode([TrackedSymbol].self, from: data), !decoded.isEmpty {
            trackedSymbols = decoded
        } else {
            trackedSymbols = [TrackedSymbol(symbol: "BTC", entryPrice: nil),
                             TrackedSymbol(symbol: "SPY", entryPrice: nil)]
        }
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(trackedSymbols) {
            UserDefaults.standard.set(encoded, forKey: "tracked_symbols")
        }
    }

    func add(symbol: String, entryPrice: Double?) {
        trackedSymbols.append(TrackedSymbol(symbol: symbol, entryPrice: entryPrice))
        save()
    }

    func remove(_ symbol: String) {
        trackedSymbols.removeAll { $0.symbol == symbol }
        prices.removeValue(forKey: symbol)
        save()
    }

    func updatePrice(for symbol: String, price: Double) {
        if let idx = trackedSymbols.firstIndex(where: { $0.symbol == symbol }) {
            trackedSymbols[idx].entryPrice = price == 0 ? nil : price
            save()
        }
    }

    // MARK: - Fetch live prices from Polygon.io

    func fetchLivePrices() async {
        isLoadingPrices = true
        defer { isLoadingPrices = false }

        await withTaskGroup(of: (String, Double, Double)?.self) { group in
            for symbol in trackedSymbols.map({ $0.symbol }) {
                group.addTask {
                    if let data = await self.fetchFromBackend(symbol: symbol) {
                        return (symbol, data.price, data.change)
                    }
                    return nil
                }
            }
            for await result in group {
                if let (symbol, price, change) = result {
                    prices[symbol] = (price, change)
                }
            }
        }
    }

    /// Debounced fetch — skips if prices were updated within `cooldown` seconds.
    func fetchLivePricesIfStale(cooldown: TimeInterval) async {
        guard lastPriceFetch == nil || Date().timeIntervalSince(lastPriceFetch!) >= cooldown
        else { return }
        lastPriceFetch = Date()
        await fetchLivePrices()
    }

    @Published private(set) var lastPriceFetch: Date?

    private func fetchFromBackend(symbol: String) async -> (price: Double, change: Double)? {
        let batch = await MarketBackendService.fetchBatch(symbols: [symbol])
        guard let row = batch.first, row.error == nil, row.price > 0 else { return nil }
        return (row.price, row.change24h)
    }

    private var cryptoSymbols: Set<String> {
        ["BTC", "ETH", "SOL", "BNB", "XRP", "ADA", "DOGE", "DOT", "AVAX", "LINK"]
    }

    // MARK: - Sparkline — seeded demo, shown when no live price available

    func sparklineData(for symbol: String) -> [Double] {
        // If we have a live price, don't show fake sparkline — return empty
        guard prices[symbol] == nil else { return [] }

        // Demo sparkline: mix symbol hash with day-of-year so shape varies daily
        let dayComponent = Int(Date().timeIntervalSince1970 / 86400)
        var generator = SeededRandom(seed: symbol.hashValue ^ dayComponent)
        var values: [Double] = []
        let basePrice: Double = {
            switch symbol.uppercased() {
            case "BTC": return 67500
            case "SPY": return 520
            case "AAPL": return 185
            case "NVDA": return 850
            default: return Double(abs(symbol.hashValue) % 1000 + 50)
            }
        }()
        var value = basePrice * 0.95
        for _ in 0..<20 {
            let change = (generator.random() - 0.5) * basePrice * 0.02
            value += change
            values.append(value)
        }
        return values
    }

    /// True when showing estimated/demo sparkline data (no live price available)
    func isEstimated(for symbol: String) -> Bool {
        return prices[symbol] == nil
    }
}

private struct SeededRandom {
    private var seed: Int
    private var state: UInt64

    init(seed: Int) {
        self.seed = seed
        self.state = UInt64(bitPattern: Int64(abs(seed)))
    }

    mutating func random() -> Double {
        state = (state &* 6364136223846793009) &+ 1
        return Double(state) / Double(UInt64.max)
    }
}

private struct SymbolRowView: View {
    let item: TrackedSymbol
    let sparklineData: [Double]
    let isEstimated: Bool
    let delay: Double
    let onDelete: () -> Void
    let onPriceChange: (Double) -> Void

    @State private var priceText: String = ""
    @State private var pressScale: CGFloat = 1.0
    @FocusState private var isPriceFocused: Bool

    private var trend: NumberText.Trend {
        guard sparklineData.count >= 2 else { return .neutral }
        let diff = sparklineData.last! - sparklineData.first!
        return diff > 0 ? .up : (diff < 0 ? .down : .neutral)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.symbol)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.warmTextPrimary)

                if let ep = item.entryPrice {
                    Text("Entry: $\(String(format: "%.2f", ep))")
                        .font(.caption)
                        .foregroundStyle(Color.warmTextSecondary)
                }
            }

            Spacer()

            // Live price + change OR demo sparkline
            if !sparklineData.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    SparklineView(
                        dataPoints: sparklineData,
                        color: trend == .up ? Color.warmPositive : (trend == .down ? Color.warmNegative : Color.warmSecondaryAccent),
                        showGradient: true
                    )
                    .frame(width: 80, height: 30)
                    if isEstimated {
                        Text("demo")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.warmTextSecondary.opacity(0.6))
                    }
                }
            }

            // Entry price input
            TextField("Entry $", text: $priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($isPriceFocused)
                .scaleEffect(pressScale)
                .toolbar {
                    ToolbarItem(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button("Done") {
                                let val = Double(priceText)
                                if let v = val, v > 0 {
                                    onPriceChange(v)
                                }
                                isPriceFocused = false
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                    }
                }
                .onChange(of: isPriceFocused) { _, focused in
                    if focused {
                        priceText = item.entryPrice == nil ? "" : String(format: "%.2f", item.entryPrice!)
                    }
                }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { onDelete() }
        }
        .cardEntrance(delay: delay)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        pressScale = 0.98
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        pressScale = 1.0
                    }
                }
        )
    }
}

#Preview {
    MarketsView()
}
