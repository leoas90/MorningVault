import SwiftUI

struct MarketsView: View {
    @StateObject private var viewModel: MarketsViewModel
    @State private var newSymbol: String = ""
    @State private var newEntryPrice: String = ""
    @State private var hasAppeared = false
    @State private var pricesLoadTaskStarted = false
    @State private var isEditing = false
    @FocusState private var isFieldFocused: Bool

    init() {
        _viewModel = StateObject(wrappedValue: MarketsViewModel())
    }

    /// Previews: inject rows and quotes; the view skips loading and fetching.
    init(previewSymbols: [TrackedSymbol], quotes: [String: (price: Double, change: Double)], updatedAt: Date? = Date()) {
        let vm = MarketsViewModel()
        vm.isPreview = true
        vm.trackedSymbols = previewSymbols
        vm.prices = quotes
        vm.setPreviewFetchDate(updatedAt)
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                        .padding(.top, 8)

                    ForEach(Array(viewModel.trackedSymbols.enumerated()), id: \.element.symbol) { index, item in
                        SymbolCard(
                            item: item,
                            quote: viewModel.quote(for: item.symbol),
                            isEditing: isEditing,
                            delay: Double(index) * AppAnimation.cardStaggerDelay,
                            onDelete: { withAnimation(.easeOut(duration: 0.2)) { viewModel.remove(item.symbol) } },
                            onPriceChange: { price in viewModel.updatePrice(for: item.symbol, price: price) }
                        )
                    }

                    if viewModel.trackedSymbols.isEmpty {
                        EmptyStateView(
                            title: "Nothing tracked yet",
                            message: "Add a stock or crypto symbol below. Up to \(MarketsViewModel.maxSymbols); prices come through MorningVault's own proxy.",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                    }

                    addSymbolCard

                    Text("Track up to \(MarketsViewModel.maxSymbols) symbols. Prices come through MorningVault's own proxy and are stored only on your device.")
                        .font(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.backgroundColor.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if isFieldFocused {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isFieldFocused = false
                        }
                        .font(.body.weight(.semibold))
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
                withAnimation(.easeOut(duration: 0.35)) {
                    hasAppeared = true
                }
                guard !viewModel.isPreview else { return }
                viewModel.load()
                // Debounce: skip if live prices were fetched within last 60 seconds
                await viewModel.fetchLivePricesIfStale(cooldown: 60)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
        }
    }

    // MARK: Header

    private var subtitle: String {
        if let date = viewModel.lastPriceFetch {
            return "Updated \(EditorialFormat.time(date)) · Prices delayed up to 5 min"
        }
        return viewModel.isLoadingPrices ? "Fetching prices…" : "Prices delayed up to 5 min"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("Markets")
                    .font(.display(34))
                    .foregroundStyle(Color.inkPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                headerButtons
            }
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerButtons: some View {
            HStack(spacing: 8) {
                Button(isEditing ? "Done" : "Edit") {
                    withAnimation(.easeInOut(duration: 0.2)) { isEditing.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.inkPrimary)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.surfaceColor, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.inkPrimary.opacity(0.16), lineWidth: 1))
                .buttonStyle(.plain)
                .accessibilityLabel(isEditing ? "Finish editing" : "Edit symbols")

                Button {
                    guard !viewModel.isLoadingPrices else { return }
                    Task { await viewModel.fetchLivePrices() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.surfaceColor)
                            .overlay(Circle().strokeBorder(Color.inkPrimary.opacity(0.16), lineWidth: 1))
                        if viewModel.isLoadingPrices {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.inkPrimary)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.inkPrimary)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh prices")
            }
    }

    // MARK: Add symbol

    private var canAdd: Bool {
        !newSymbol.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.isAtLimit
    }

    private func addSymbol() {
        guard canAdd else { return }
        let sym = newSymbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !sym.isEmpty else { return }
        viewModel.add(symbol: sym, entryPrice: Double(newEntryPrice))
        newSymbol = ""
        newEntryPrice = ""
        isFieldFocused = false
        guard !viewModel.isPreview else { return }
        Task { await viewModel.fetchLivePrices() }
    }

    private var addSymbolCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Track a symbol")

            fieldRow {
                TextField("Symbol", text: $newSymbol, prompt: Text("Symbol, e.g. AAPL or BTC").foregroundStyle(Color.inkSecondary))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($isFieldFocused)
            }

            fieldRow {
                TextField("Entry price", text: $newEntryPrice, prompt: Text("Entry price (optional)").foregroundStyle(Color.inkSecondary))
                    .keyboardType(.decimalPad)
                    .focused($isFieldFocused)
            }

            Button(action: addSymbol) {
                Text("Track symbol")
                    .font(.headline)
                    .foregroundStyle(canAdd ? Color.onAccent : Color.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canAdd ? Color.appAccentColor : Color.inkPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Track symbol")
            .accessibilityHint(canAdd ? "" : (viewModel.isAtLimit ? "At the symbol limit" : "Enter a symbol first"))

            if viewModel.isAtLimit {
                Text("You're tracking \(MarketsViewModel.maxSymbols) symbols, the maximum. Remove one to add another.")
                    .font(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialCard()
    }

    private func fieldRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body)
            .foregroundStyle(Color.inkPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.inkPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.inkPrimary.opacity(0.14), lineWidth: 1))
    }
}

@MainActor
final class MarketsViewModel: ObservableObject {
    @Published var trackedSymbols: [TrackedSymbol] = []
    @Published var prices: [String: (price: Double, change: Double)] = [:]  // symbol → (price, change24h%)
    @Published var isLoadingPrices = false
    /// Previews: skip UserDefaults and the network.
    var isPreview = false

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
        guard !isPreview else { return }
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
        lastPriceFetch = Date()
    }

    /// Debounced fetch — skips if prices were updated within `cooldown` seconds.
    func fetchLivePricesIfStale(cooldown: TimeInterval) async {
        guard lastPriceFetch == nil || Date().timeIntervalSince(lastPriceFetch!) >= cooldown
        else { return }
        lastPriceFetch = Date()
        await fetchLivePrices()
    }

    @Published private(set) var lastPriceFetch: Date?

    func setPreviewFetchDate(_ date: Date?) {
        lastPriceFetch = date
    }

    /// Live quote for a symbol, or nil until the proxy answers (the row shows a dash).
    func quote(for symbol: String) -> (price: Double, change: Double)? {
        prices[symbol]
    }
}

// MARK: - Symbol card

private struct SymbolCard: View {
    let item: TrackedSymbol
    let quote: (price: Double, change: Double)?
    let isEditing: Bool
    let delay: Double
    let onDelete: () -> Void
    let onPriceChange: (Double) -> Void

    @State private var isEditingEntry = false
    @State private var priceText: String = ""
    @FocusState private var isPriceFocused: Bool

    private var pnl: (percent: Double, perUnit: Double)? {
        guard let quote, let entry = item.entryPrice, entry > 0 else { return nil }
        return ((quote.price - entry) / entry * 100, quote.price - entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if isEditing {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.negativeColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.symbol)")
                    .transition(.scale.combined(with: .opacity))
                }

                Text(item.symbol)
                    .font(.display(22))
                    .foregroundStyle(Color.inkPrimary)

                Spacer(minLength: 8)

                // Live price + 24h change; a dash until the proxy has answered. No invented data.
                if let quote {
                    Text(EditorialFormat.price(symbol: item.symbol, quote.price))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.inkPrimary)
                        .contentTransition(.numericText())
                    ChangePill(change: quote.change)
                } else {
                    Text("—")
                        .font(.title3)
                        .foregroundStyle(Color.inkSecondary)
                        .accessibilityLabel("No quote yet")
                }
            }
            .animation(.default, value: quote?.price)

            if isEditingEntry {
                entryEditor
            } else if let entry = item.entryPrice {
                HStack(spacing: 6) {
                    Text("Entry \(EditorialFormat.price(symbol: item.symbol, entry))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Color.inkSecondary)
                    if let pnl {
                        Text("·")
                            .foregroundStyle(Color.inkSecondary)
                        Text(String(format: "%@%.2f%% since entry", pnl.percent >= 0 ? "+" : "−", abs(pnl.percent)))
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(pnl.percent >= 0 ? Color.positiveColor : Color.negativeColor)
                    }
                    Spacer()
                    Button("Change") { beginEditingEntry() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appAccentColor)
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change entry price for \(item.symbol)")
                }
            } else {
                Button { beginEditingEntry() } label: {
                    Label("Add entry price", systemImage: "plus")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appAccentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add entry price for \(item.symbol)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialCard(padding: 16)
        .cardEntrance(delay: delay)
        .contextMenu {
            Button("Remove \(item.symbol)", role: .destructive, action: onDelete)
        }
    }

    private func beginEditingEntry() {
        priceText = item.entryPrice.map { String(format: "%.2f", $0) } ?? ""
        withAnimation(.easeInOut(duration: 0.2)) { isEditingEntry = true }
        isPriceFocused = true
    }

    private func commitEntry() {
        if let v = Double(priceText), v > 0 {
            onPriceChange(v)
        } else if priceText.trimmingCharacters(in: .whitespaces).isEmpty {
            onPriceChange(0)
        }
        isPriceFocused = false
        withAnimation(.easeInOut(duration: 0.2)) { isEditingEntry = false }
    }

    private var entryEditor: some View {
        HStack(spacing: 10) {
            TextField("Entry price", text: $priceText, prompt: Text("Entry price").foregroundStyle(Color.inkSecondary))
                .keyboardType(.decimalPad)
                .font(.body.monospacedDigit())
                .foregroundStyle(Color.inkPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.inkPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.inkPrimary.opacity(0.14), lineWidth: 1))
                .focused($isPriceFocused)
                .onSubmit(commitEntry)
                .toolbar {
                    ToolbarItem(placement: .keyboard) {
                        HStack {
                            Spacer()
                            Button("Done", action: commitEntry)
                        }
                    }
                }
            Button("Save", action: commitEntry)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.appAccentColor, in: Capsule())
                .buttonStyle(.plain)
            Button("Cancel") {
                isPriceFocused = false
                withAnimation(.easeInOut(duration: 0.2)) { isEditingEntry = false }
            }
            .font(.subheadline)
            .foregroundStyle(Color.inkSecondary)
            .buttonStyle(.plain)
        }
    }
}

/// Brief card language inside a `List`: each row on `warmSurface` with `AppRadius.card`,
/// separators hidden. Kept for any List-based screen that still wants card rows.
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

#Preview("Markets · light") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return MarketsView(
        previewSymbols: [TrackedSymbol(symbol: "SPY", entryPrice: 702.10), TrackedSymbol(symbol: "BTC", entryPrice: nil)],
        quotes: ["SPY": (price: 735.29, change: -2.70), "BTC": (price: 75699.0, change: 1.12)]
    )
    .preferredColorScheme(.light)
}

#Preview("Markets · dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return MarketsView(
        previewSymbols: [TrackedSymbol(symbol: "SPY", entryPrice: 702.10), TrackedSymbol(symbol: "BTC", entryPrice: nil)],
        quotes: ["SPY": (price: 735.29, change: -2.70), "BTC": (price: 75699.0, change: 1.12)]
    )
    .preferredColorScheme(.dark)
}
