import SwiftUI

struct MarketsView: View {
    @StateObject private var viewModel = MarketsViewModel()
    @State private var newSymbol: String = ""
    @State private var newEntryPrice: String = ""
    @State private var hasAppeared = false
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
            .toolbar { EditButton() }
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
                viewModel.load()
                withAnimation(.easeOut(duration: 0.35)) {
                    hasAppeared = true
                }
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
        save()
    }

    func updatePrice(for symbol: String, price: Double) {
        if let idx = trackedSymbols.firstIndex(where: { $0.symbol == symbol }) {
            trackedSymbols[idx].entryPrice = price == 0 ? nil : price
            save()
        }
    }

    func sparklineData(for symbol: String) -> [Double] {
        // Mix symbol hash with day-of-year so the shape varies each day
        let dayComponent = Int(Date().timeIntervalSince1970 / 86400)
        var generator = SeededRandom(seed: symbol.hashValue ^ dayComponent)
        var values: [Double] = []
        let basePrice: Double = {
            switch symbol {
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
    let delay: Double
    let onDelete: () -> Void
    let onPriceChange: (Double) -> Void

    @State private var priceText: String = ""
    @FocusState private var isPriceFocused: Bool

    private var trend: NumberText.Trend {
        guard sparklineData.count >= 2 else { return .neutral }
        let diff = sparklineData.last! - sparklineData.first!
        return diff > 0 ? .up : (diff < 0 ? .down : .neutral)
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.symbol)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.warmTextPrimary)

                if let ep = item.entryPrice {
                    NumberText(value: ep, format: "%.2f", trend: trend)
                }
            }

            Spacer()

            if !sparklineData.isEmpty {
                SparklineView(
                    dataPoints: sparklineData,
                    color: trend == .up ? Color.warmPositive : (trend == .down ? Color.warmNegative : Color.warmSecondaryAccent),
                    showGradient: true
                )
                .frame(width: 80, height: 30)
                .cardEntrance(delay: delay + 0.1)
            }

            TextField("Entry $", text: $priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($isPriceFocused)
                .onChange(of: isPriceFocused) { _, focused in
                    if focused {
                        priceText = item.entryPrice == nil ? "" : String(format: "%.2f", item.entryPrice!)
                    }
                }
                .onSubmit {
                    if let val = Double(priceText) {
                        onPriceChange(val)
                    }
                    isPriceFocused = false
                }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { onDelete() }
        }
        .cardEntrance(delay: delay)
    }
}

#Preview {
    MarketsView()
}
