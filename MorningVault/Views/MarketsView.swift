import SwiftUI

struct MarketsView: View {
    @StateObject private var viewModel = MarketsViewModel()
    @State private var newSymbol: String = ""
    @State private var newEntryPrice: String = ""
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
            .task { viewModel.load() }
        }
    }

    private var symbolsSection: some View {
        Section {
            ForEach(viewModel.trackedSymbols) { item in
                SymbolRowView(
                    item: item,
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
}

private struct SymbolRowView: View {
    let item: TrackedSymbol
    let onDelete: () -> Void
    let onPriceChange: (Double) -> Void

    @State private var priceText: String = ""
    @FocusState private var isPriceFocused: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.symbol)
                    .font(.headline)
                    .fontWeight(.bold)
                if let ep = item.entryPrice {
                    Text("Entry: $\(String(format: "%.2f", ep))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            TextField("Entry $", text: $priceText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
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
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

#Preview {
    MarketsView()
}