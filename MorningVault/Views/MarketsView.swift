import SwiftUI

struct MarketsView: View {
    @AppStorage("tracked_symbols") private var trackedSymbolsData: Data = Data()
    @State private var trackedSymbols: [TrackedSymbol] = []
    @State private var newSymbol = ""
    @State private var newEntryPrice = ""

    private func loadTrackedSymbols() {
        if let data = try? JSONDecoder().decode([TrackedSymbol].self, from: trackedSymbolsData), !data.isEmpty {
            trackedSymbols = data
        } else {
            trackedSymbols = [TrackedSymbol(symbol: "BTC", entryPrice: nil),
                             TrackedSymbol(symbol: "SPY", entryPrice: nil)]
        }
    }

    private func saveTrackedSymbols() {
        if let encoded = try? JSONEncoder().encode(trackedSymbols) {
            trackedSymbolsData = encoded
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(trackedSymbols) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.symbol)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                if let entry = item.entryPrice {
                                    Text("Entry: $\(String(format: "%.2f", entry))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            TextField("Entry $", value: Binding(
                                get: { item.entryPrice ?? 0 },
                                set: { newPrice in
                                    if let idx = trackedSymbols.firstIndex(where: { $0.symbol == item.symbol }) {
                                        trackedSymbols[idx].entryPrice = newPrice == 0 ? nil : newPrice
                                    }
                                }
                            ), format: .currency(code: "USD")
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                trackedSymbols.removeAll { $0.symbol == item.symbol }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        trackedSymbols.remove(atOffsets: indexSet)
                    }
                } header: {
                    Text("Tracked Symbols")
                } footer: {
                    Text("Entry price enables P&L tracking. Tap a price to edit.")
                        .font(.caption)
                }

                Section("Add Symbol") {
                    HStack {
                        TextField("Symbol (e.g. AAPL)", text: $newSymbol)
                            .textInputAutocapitalization(.characters)
                            .frame(maxWidth: 130)
                        TextField("Entry $", text: $newEntryPrice)
                            .keyboardType(.decimalPad)
                            .frame(maxWidth: 100)
                        Button {
                            let sym = newSymbol.uppercased().trimmingCharacters(in: .whitespaces)
                            guard !sym.isEmpty else { return }
                            trackedSymbols.append(TrackedSymbol(symbol: sym, entryPrice: Double(newEntryPrice)))
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

                Section {
                    Text("Track up to 10 symbols. Prices are stored locally on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Markets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                EditButton()
            }
            .task {
                loadTrackedSymbols()
            }
            .onChange(of: trackedSymbols) { _, _ in
                saveTrackedSymbols()
            }
        }
    }
}

#Preview {
    MarketsView()
}