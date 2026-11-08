import SwiftUI

/// Markets as an instrument: a serif page title, then one hairline-separated list of
/// tracked symbols (price 32 pt, delta, 120×40 sparkline from the worker's real series),
/// entry price / P&L under each row, Edit mode for removal, and the Track-a-symbol form.
struct MarketsView: View {
    @StateObject private var viewModel: MarketsViewModel
    @State private var newSymbol: String = ""
    @State private var newEntryPrice: String = ""
    @State private var hasAppeared = false
    @State private var pricesLoadTaskStarted = false
    @State private var isEditing = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        _viewModel = StateObject(wrappedValue: MarketsViewModel())
    }

    /// Previews: inject rows and quotes; the view skips loading and fetching.
    init(previewSymbols: [TrackedSymbol], quotes: [String: MarketQuote], updatedAt: Date? = Date()) {
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
                VStack(alignment: .leading, spacing: 28) {
                    header
                        .padding(.top, 8)

                    if viewModel.trackedSymbols.isEmpty {
                        EmptyStateView(
                            title: "Nothing tracked yet",
                            message: "Add a stock or crypto symbol below. Up to \(MarketsViewModel.maxSymbols); prices come through MorningVault's own proxy.",
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                    } else {
                        VStack(spacing: 0) {
                            Hairline()
                            ForEach(Array(viewModel.trackedSymbols.enumerated()), id: \.element.symbol) { index, item in
                                SymbolRow(
                                    item: item,
                                    quote: viewModel.quote(for: item.symbol),
                                    isEditing: isEditing,
                                    onDelete: { withAnimation(.easeOut(duration: 0.2)) { viewModel.remove(item.symbol) } },
                                    onPriceChange: { price in viewModel.updatePrice(for: item.symbol, price: price) }
                                )
                                .cardEntrance(delay: Double(index) * AppAnimation.cardStaggerDelay)
                                Hairline()
                            }
                        }
                    }

                    addSymbolForm

                    Text("Track up to \(MarketsViewModel.maxSymbols) symbols. Prices come through MorningVault's own proxy and are stored only on your device.")
                        .font(.metaText)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.backgroundColor.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                guard !viewModel.isPreview else { return }
                await viewModel.fetchLivePrices()
            }
            .safeAreaInset(edge: .bottom) {
                if isFieldFocused {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isFieldFocused = false
                        }
                        .font(.system(size: 17, weight: .semibold))
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
                withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.35)) {
                    hasAppeared = true
                }
                guard !viewModel.isPreview else { return }
                viewModel.load()
                // Debounce: skip if live prices were fetched within last 60 seconds
                await viewModel.fetchLivePricesIfStale(cooldown: 60)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : 8)
        }
    }

    // MARK: Header

    private var subtitle: String {
        if viewModel.isLoadingPrices { return "Fetching prices…" }
        if let date = viewModel.lastPriceFetch {
            return "Updated \(EditorialFormat.time(date)) · Delayed up to 5 min"
        }
        return "Delayed up to 5 min · Pull to refresh"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("Markets")
                    .font(.display(34))
                    .foregroundStyle(Color.inkPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !viewModel.trackedSymbols.isEmpty {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(.easeInOut(duration: 0.2)) { isEditing.toggle() }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.pressable)
                    .accessibilityLabel(isEditing ? "Finish editing" : "Edit symbols")
                }
            }
            HStack(spacing: 6) {
                if viewModel.isLoadingPrices {
                    ProgressView().controlSize(.mini).tint(Color.inkSecondary)
                }
                Text(subtitle)
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private var addSymbolForm: some View {
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

            // The one accent-filled control on this screen.
            Button(action: addSymbol) {
                Text("Track symbol")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canAdd ? Color.onAccent : Color.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canAdd ? Color.appAccentColor : Color.inkPrimary.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.button, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Track symbol")
            .accessibilityHint(canAdd ? "" : (viewModel.isAtLimit ? "At the symbol limit" : "Enter a symbol first"))

            if viewModel.isAtLimit {
                Text("You're tracking \(MarketsViewModel.maxSymbols) symbols, the maximum. Remove one to add another.")
                    .font(.metaText)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .editorialCard()
    }

    private func fieldRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.bodyText)
            .foregroundStyle(Color.inkPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.inkPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
    }
}

/// Live quote for one tracked symbol. `series` is the worker's real closes (empty = no sparkline).
struct MarketQuote: Equatable, Sendable {
    var price: Double
    var change: Double
    var prevClose: Double? = nil
    var series: [Double] = []
}

@MainActor
final class MarketsViewModel: ObservableObject {
    @Published var trackedSymbols: [TrackedSymbol] = []
    @Published var prices: [String: MarketQuote] = [:]  // symbol → quote
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
            prices[row.symbol] = MarketQuote(price: row.price, change: row.change24h, prevClose: row.prevClose, series: row.series)
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
    func quote(for symbol: String) -> MarketQuote? {
        prices[symbol]
    }
}

// MARK: - Symbol row

private struct SymbolRow: View {
    let item: TrackedSymbol
    let quote: MarketQuote?
    let isEditing: Bool
    let onDelete: () -> Void
    let onPriceChange: (Double) -> Void

    @State private var isEditingEntry = false
    @State private var priceText: String = ""
    @FocusState private var isPriceFocused: Bool

    private var pnl: (percent: Double, perUnit: Double)? {
        guard let quote, let entry = item.entryPrice, entry > 0 else { return nil }
        return ((quote.price - entry) / entry * 100, quote.price - entry)
    }

    private var entryFootnote: String? {
        guard let entry = item.entryPrice else { return nil }
        return "Entry \(EditorialFormat.price(symbol: item.symbol, entry))"
    }

    private var pnlText: String? {
        guard let pnl else { return nil }
        return String(format: "%@%.2f%% since entry", pnl.percent >= 0 ? "+" : "−", abs(pnl.percent))
    }

    private var pnlColor: Color? {
        guard let pnl else { return nil }
        return pnl.percent >= 0 ? Color.positiveColor : Color.negativeColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if isEditing {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.negativeColor)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Remove \(item.symbol)")
                    .transition(.scale.combined(with: .opacity))
                }

                // Live price + 24h change + series; a dash until the proxy has answered. No invented data.
                if let quote {
                    MarketRow(symbol: item.symbol,
                              priceText: EditorialFormat.price(symbol: item.symbol, quote.price),
                              change: quote.change,
                              series: quote.series,
                              prevClose: quote.prevClose,
                              compact: false,
                              footnote: entryFootnote,
                              footnoteDetail: pnlText,
                              footnoteDetailColor: pnlColor)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: item.symbol)
                        Text("—")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color.inkSecondary)
                            .accessibilityLabel("No quote yet")
                        if let entryFootnote {
                            Text(entryFootnote)
                                .font(.metaText)
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
                    .padding(.vertical, 14)
                }
            }
            .animation(.default, value: quote?.price)

            if isEditingEntry {
                entryEditor
                    .padding(.bottom, 14)
            } else {
                Button {
                    beginEditingEntry()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.entryPrice == nil ? "plus" : "pencil")
                            .font(.system(size: 13, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                        Text(item.entryPrice == nil ? "Add entry price" : "Change entry price")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color.inkPrimary)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(item.entryPrice == nil ? "Add" : "Change") entry price for \(item.symbol)")
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.bodyText.monospacedDigit())
                .foregroundStyle(Color.inkPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.inkPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.inkPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .overlay(Capsule().strokeBorder(Color.inkPrimary.opacity(0.3), lineWidth: 1))
                .buttonStyle(.pressable)
            Button("Cancel") {
                isPriceFocused = false
                withAnimation(.easeInOut(duration: 0.2)) { isEditingEntry = false }
            }
            .font(.system(size: 15))
            .foregroundStyle(Color.inkSecondary)
            .buttonStyle(.pressable)
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

// Preview quotes use `MarketPreviewData` series (preview data, not market data).
#Preview("Markets · light") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return MarketsView(
        previewSymbols: [TrackedSymbol(symbol: "SPY", entryPrice: 702.10), TrackedSymbol(symbol: "BTC", entryPrice: nil), TrackedSymbol(symbol: "AAPL", entryPrice: nil)],
        quotes: ["SPY": MarketQuote(price: 735.29, change: -2.70, prevClose: 755.0, series: MarketPreviewData.spy),
                 "BTC": MarketQuote(price: 75699.0, change: 1.12, prevClose: 74_860, series: MarketPreviewData.btc)],
        updatedAt: BriefingViewModel.previewNow
    )
    .preferredColorScheme(.light)
}

#Preview("Markets · dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    return MarketsView(
        previewSymbols: [TrackedSymbol(symbol: "SPY", entryPrice: 702.10), TrackedSymbol(symbol: "BTC", entryPrice: nil)],
        quotes: ["SPY": MarketQuote(price: 735.29, change: -2.70, prevClose: 755.0, series: MarketPreviewData.spy),
                 "BTC": MarketQuote(price: 75699.0, change: 1.12, prevClose: 74_860, series: MarketPreviewData.btc)],
        updatedAt: BriefingViewModel.previewNow
    )
    .preferredColorScheme(.dark)
}
