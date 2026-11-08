import SwiftUI

/// Markets as an instrument: a serif page title in the content, Edit / Done and Add in the
/// navigation bar, then one hairline-separated list of tracked symbols (quote 30 pt, delta,
/// 104×40 sparkline from the worker's real series, ~104 pt rows), entry price / P&L under
/// each row, and the Track-a-symbol form as a sheet.
struct MarketsView: View {
    @StateObject private var viewModel: MarketsViewModel
    @State private var hasAppeared = false
    @State private var pricesLoadTaskStarted = false
    @State private var isEditing = false
    @State private var showTrackSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        _viewModel = StateObject(wrappedValue: MarketsViewModel())
    }

    /// Previews: inject rows and quotes; the view skips loading and fetching.
    init(previewSymbols: [TrackedSymbol], quotes: [String: MarketQuote], updatedAt: Date? = Date(), showTrackSheet: Bool = false) {
        let vm = MarketsViewModel()
        vm.isPreview = true
        vm.trackedSymbols = previewSymbols
        vm.prices = quotes
        vm.setPreviewFetchDate(updatedAt)
        _viewModel = StateObject(wrappedValue: vm)
        _showTrackSheet = State(initialValue: showTrackSheet)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Grid4.section) {
                    header

                    if viewModel.trackedSymbols.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            EmptyStateView(
                                title: "Nothing tracked yet",
                                message: "Track a stock or crypto symbol to see its price and today's line here. Up to \(MarketsViewModel.maxSymbols); prices come through MorningVault's own proxy.",
                                systemImage: "chart.line.uptrend.xyaxis"
                            )
                            PrimaryButton(title: "Track a symbol", systemImage: "plus.circle") { showTrackSheet = true }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Eyebrow(text: "Watchlist")
                                Spacer()
                                Text("Today's line")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.inkSecondary)
                            }
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.trackedSymbols.enumerated()), id: \.element.symbol) { index, item in
                                    SymbolRow(
                                        item: item,
                                        quote: viewModel.quote(for: item.symbol),
                                        isEditing: isEditing,
                                        onDelete: { withAnimation(.easeOut(duration: 0.2)) { viewModel.remove(item.symbol) } },
                                        onPriceChange: { price in viewModel.updatePrice(for: item.symbol, price: price) }
                                    )
                                    .cardEntrance(delay: Double(index) * AppAnimation.cardStaggerDelay)
                                    if index < viewModel.trackedSymbols.count - 1 { Hairline() }
                                }
                            }
                        }
                    }

                    Text("Track up to \(MarketsViewModel.maxSymbols) symbols. The dotted line is the previous close. Quotes come through MorningVault's own proxy; your list and entry prices stay on this device.")
                        .font(.secondaryText)
                        .lineSpacing(Leading.secondary)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Grid4.margin)
                .padding(.bottom, 24)
            }
            .background(Color.backgroundColor.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.trackedSymbols.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "Done" : "Edit") {
                            withAnimation(.easeInOut(duration: 0.2)) { isEditing.toggle() }
                        }
                        .font(.system(size: 17, weight: isEditing ? .semibold : .regular))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(isEditing ? "Finish editing" : "Edit symbols")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showTrackSheet = true } label: {
                        Image(systemName: "plus.circle")
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(viewModel.isAtLimit)
                    .accessibilityLabel("Track a symbol")
                }
            }
            .sheet(isPresented: $showTrackSheet) {
                TrackSymbolSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .refreshable {
                guard !viewModel.isPreview else { return }
                await viewModel.fetchLivePrices()
            }
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
            return "Updated \(EditorialFormat.time(date)) · Quotes delayed up to 5 min"
        }
        return "Quotes delayed up to 5 min · Pull to refresh"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Markets")
                .font(.pageTitle)
                .foregroundStyle(Color.inkPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                if viewModel.isLoadingPrices {
                    ProgressView().controlSize(.mini).tint(Color.inkSecondary)
                }
                Text(subtitle)
                    .font(.secondaryText)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Track-a-symbol sheet

/// Half-sheet form: 52 pt fields (radius 12, accent focus ring), a filled 52 pt "Track symbol"
/// button with a real disabled state, and inline validation under the symbol field.
struct TrackSymbolSheet: View {
    @ObservedObject var viewModel: MarketsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var symbol: String = ""
    @State private var entryPrice: String = ""
    @FocusState private var focus: Field?

    enum Field { case symbol, price }

    private var cleaned: String { symbol.uppercased().trimmingCharacters(in: .whitespaces) }

    /// nil when the form can be submitted.
    private var validation: String? {
        if viewModel.isAtLimit { return "You're tracking \(MarketsViewModel.maxSymbols) symbols, the maximum. Remove one to add another." }
        if cleaned.isEmpty { return nil }
        if cleaned.count > 10 || cleaned.rangeOfCharacter(from: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").inverted) != nil {
            return "Use letters and numbers only, like AAPL or BTC."
        }
        if viewModel.trackedSymbols.contains(where: { $0.symbol == cleaned }) { return "\(cleaned) is already on your list." }
        if !entryPrice.trimmingCharacters(in: .whitespaces).isEmpty, Double(entryPrice) == nil || (Double(entryPrice) ?? 0) <= 0 {
            return "Entry price should be a number, like 702.10."
        }
        return nil
    }

    private var canAdd: Bool { !cleaned.isEmpty && validation == nil }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Track a symbol")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.inkPrimary)
                    Text("A stock ticker or a crypto symbol. The entry price is optional and turns on since-entry P&L.")
                        .font(.secondaryText)
                        .lineSpacing(Leading.secondary)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    FormField(isFocused: focus == .symbol) {
                        TextField("Symbol", text: $symbol, prompt: Text("Symbol, e.g. AAPL or BTC").foregroundStyle(Color.inkSecondary))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .symbol)
                            .onSubmit { focus = .price }
                    }
                    FormField(isFocused: focus == .price) {
                        TextField("Entry price", text: $entryPrice, prompt: Text("Entry price (optional)").foregroundStyle(Color.inkSecondary))
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .price)
                    }
                    if let validation {
                        Text(validation)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(viewModel.isAtLimit ? Color.inkSecondary : Color.negativeColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: validation)

                PrimaryButton(title: "Track symbol", isEnabled: canAdd, action: add)
                    .accessibilityHint(canAdd ? "" : (viewModel.isAtLimit ? "At the symbol limit" : "Enter a symbol first"))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Grid4.margin)
            .padding(.top, 8)
            .background(Color.backgroundColor.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack { Spacer(); Button("Done") { focus = nil } }
                }
            }
            .onAppear { focus = .symbol }
        }
    }

    private func add() {
        guard canAdd else { return }
        viewModel.add(symbol: cleaned, entryPrice: Double(entryPrice))
        focus = nil
        dismiss()
        guard !viewModel.isPreview else { return }
        Task { await viewModel.fetchLivePrices() }
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
                            .font(.system(size: 22, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.negativeColor)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Remove \(item.symbol)")
                    .transition(.scale.combined(with: .opacity))
                }

                // Live price + 24h change + series; "No quote yet" until the proxy has answered.
                if let quote {
                    MarketRow(symbol: item.symbol,
                              priceText: EditorialFormat.price(symbol: item.symbol, quote.price),
                              change: quote.change,
                              series: quote.series,
                              prevClose: quote.prevClose,
                              compact: false)
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow(text: item.symbol)
                            Text("No quote yet")
                                .font(.secondaryText)
                                .foregroundStyle(Color.inkSecondary)
                            Text("Prices arrive on the next refresh")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer(minLength: 8)
                        // Placeholder in the chart slot so the grid stays aligned.
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: 20))
                            p.addLine(to: CGPoint(x: 104, y: 20))
                        }
                        .stroke(Color.hairline, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 3]))
                        .frame(width: 104, height: 40)
                        .accessibilityHidden(true)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .animation(.default, value: quote?.price)

            // Fixed meta slot: entry / P&L on the left, the one action on the right.
            if isEditingEntry {
                entryEditor
                    .padding(.bottom, 16)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 6) {
                        Text(entryFootnote ?? "Entry not set")
                            .foregroundStyle(Color.inkSecondary)
                        if let pnlText {
                            Text(pnlText)
                                .fontWeight(.semibold)
                                .foregroundStyle(pnlColor ?? Color.inkSecondary)
                        }
                    }
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        beginEditingEntry()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .medium))
                            Text(item.entryPrice == nil ? "Set entry" : "Edit entry")
                                .font(.control)
                        }
                        .foregroundStyle(Color.appAccentColor)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("\(item.entryPrice == nil ? "Set" : "Edit") entry price for \(item.symbol)")
                }
                .padding(.top, -10)
                .padding(.bottom, 2)
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
            FormField(isFocused: isPriceFocused) {
                TextField("Entry price", text: $priceText, prompt: Text("Entry price").foregroundStyle(Color.inkSecondary))
                    .keyboardType(.decimalPad)
                    .font(.bodyText.monospacedDigit())
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
            }
            Button("Save", action: commitEntry)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.onAccent)
                .frame(height: 44)
                .padding(.horizontal, 16)
                .background(Color.appAccentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(.pressable)
            Button("Cancel") {
                isPriceFocused = false
                withAnimation(.easeInOut(duration: 0.2)) { isEditingEntry = false }
            }
            .font(.control)
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
    let rows = BriefingViewModel.previewMarketRows
    return MarketsView(previewSymbols: rows.symbols, quotes: rows.quotes, updatedAt: rows.updatedAt)
        .preferredColorScheme(.light)
}

#Preview("Markets · dark") {
    ThemeStore.shared.themeRaw = AppTheme.dark.rawValue
    let rows = BriefingViewModel.previewMarketRows
    return MarketsView(previewSymbols: rows.symbols, quotes: rows.quotes, updatedAt: rows.updatedAt)
        .preferredColorScheme(.dark)
}

#Preview("Track symbol sheet") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    let rows = BriefingViewModel.previewMarketRows
    return MarketsView(previewSymbols: rows.symbols, quotes: rows.quotes, updatedAt: rows.updatedAt, showTrackSheet: true)
        .preferredColorScheme(.light)
}

#Preview("Markets · empty") {
    ThemeStore.shared.themeRaw = AppTheme.light.rawValue
    return MarketsView(previewSymbols: [], quotes: [:], updatedAt: nil)
        .preferredColorScheme(.light)
}
