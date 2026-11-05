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
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.warmBackground.ignoresSafeArea())
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
                    .accessibilityLabel("Refresh prices")
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
                    quote: viewModel.quote(for: item.symbol),
                    delay: Double(index) * AppAnimation.cardStaggerDelay,
                    onDelete: { viewModel.remove(item.symbol) },
                    onPriceChange: { price in viewModel.updatePrice(for: item.symbol, price: price) }
                )
                .cardRow()
            }
            .onDelete { indexSet in
                for i in indexSet {
                    viewModel.remove(viewModel.trackedSymbols[i].symbol)
                }
            }
        } header: {
            Text("Tracked symbols")
        } footer: {
            Text("Entry price enables P&L tracking. Tap a price to edit.")
                .font(.caption)
        }
    }

    private var addSymbolSection: some View {
        Section {
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
                    Task { await viewModel.fetchLivePrices() }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(viewModel.isAtLimit ? Color.warmTextSecondary : Color.warmPositive)
                }
                .buttonStyle(.plain)
                .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isAtLimit)
                .accessibilityLabel("Add symbol")
            }
            .cardRow()
            .disabled(viewModel.isAtLimit)
        } header: {
            Text("Add symbol")
        } footer: {
            if viewModel.isAtLimit {
                Text("You're tracking \(MarketsViewModel.maxSymbols) symbols, the maximum. Remove one to add another.")
            }
        }
    }

    private var infoSection: some View {
        Section {
            Text("Track up to \(MarketsViewModel.maxSymbols) symbols. Prices come through MorningVault's own proxy and are stored only on your device.")
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
        guard !isAtLimit, !trackedSymbols.contains(where: { $0.symbol == symbol }) else { return }
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

    /// The UI states this cap; the add button and `add` enforce it.
    static let maxSymbols = 10

    var isAtLimit: Bool { trackedSymbols.count >= Self.maxSymbols }

    // MARK: - Fetch live prices (api.morningvault.app proxy — the phone never calls a market vendor directly)

    func fetchLivePrices() async {
        isLoadingPrices = true
        defer { isLoadingPrices = false }

        // One batched request for every tracked symbol (per-symbol fallback lives in the service).
        let quotes = await MarketBackendService.fetchBatch(symbols: trackedSymbols.map { $0.symbol })
        for row in quotes where row.error == nil && row.price > 0 {
            prices[row.symbol] = (row.price, row.change24h)
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

    /// Live quote for a symbol, or nil until the proxy answers (the row shows a dash).
    func quote(for symbol: String) -> (price: Double, change: Double)? {
        prices[symbol]
    }
}

private struct SymbolRowView: View {
    let item: TrackedSymbol
    let quote: (price: Double, change: Double)?
    let delay: Double
    let onDelete: () -> Void
    let onPriceChange: (Double) -> Void

    @State private var priceText: String = ""
    @State private var pressScale: CGFloat = 1.0
    @FocusState private var isPriceFocused: Bool

    private var trend: NumberText.Trend {
        guard let quote else { return .neutral }
        return quote.change > 0 ? .up : (quote.change < 0 ? .down : .neutral)
    }

    private var trendColor: Color {
        switch trend {
        case .up: return Color.warmPositive
        case .down: return Color.warmNegative
        case .neutral: return Color.warmTextSecondary
        }
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

            // Live price + 24h change; a dash until the proxy has answered. No invented data.
            VStack(alignment: .trailing, spacing: 2) {
                if let quote {
                    Text(MarketBackendService.formatPrice(symbol: item.symbol, price: quote.price))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color.warmTextPrimary)
                    Text(String(format: "%@%.2f%%", quote.change >= 0 ? "+" : "", quote.change))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(trendColor)
                } else {
                    Text("—")
                        .font(.subheadline)
                        .foregroundStyle(Color.warmTextSecondary)
                        .accessibilityLabel("No quote yet")
                }
            }
            .animation(.default, value: quote?.price)

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

/// Brief card language inside a `List`: each row on `warmSurface` with `AppRadius.card`,
/// separators hidden. Rows stay in a List so swipe-to-delete keeps working.
struct CardListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(Color.warmSurface)
                    .padding(.vertical, 4)
            )
    }
}

extension View {
    func cardRow() -> some View { modifier(CardListRow()) }
}

#Preview {
    MarketsView()
}
