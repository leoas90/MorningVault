import SwiftUI

// MARK: - Custom Pull to Refresh Control

struct RefreshControl: UIViewRepresentable {
    @Binding var isRefreshing: Bool
    let onRefresh: () async -> Void

    func makeUIView(context: Context) -> UIRefreshControl {
        let control = UIRefreshControl()

        // Standard iOS refresh control — always available
        control.tintColor = UIColor(Color.warmPrimaryAccent)

        // Use native iOS refresh spinner
        control.addTarget(context.coordinator, action: #selector(Coordinator.handleRefresh(_:)), for: .valueChanged)

        return control
    }

    func updateUIView(_ uiView: UIRefreshControl, context: Context) {
        if isRefreshing && !uiView.isRefreshing {
            uiView.beginRefreshing()
        } else if !isRefreshing && uiView.isRefreshing {
            uiView.endRefreshing()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRefresh: onRefresh, isRefreshing: $isRefreshing)
    }

    class Coordinator: NSObject {
        let onRefresh: () async -> Void
        @Binding var isRefreshing: Bool

        init(onRefresh: @escaping () async -> Void, isRefreshing: Binding<Bool>) {
            self.onRefresh = onRefresh
            self._isRefreshing = isRefreshing
        }

        @objc func handleRefresh(_ control: UIRefreshControl) {
            Task { @MainActor in
                await onRefresh()
                isRefreshing = false
                control.endRefreshing()
            }
        }
    }
}

// MARK: - View Extension for Pull-to-Refresh

extension View {
    func customRefreshable(isRefreshing: Binding<Bool>, action: @escaping () async -> Void) -> some View {
        self.modifier(RefreshModifier(isRefreshing: isRefreshing, action: action))
    }
}

// MARK: - Refresh Modifier

struct RefreshModifier: ViewModifier {
    @Binding var isRefreshing: Bool
    let action: () async -> Void

    func body(content: Content) -> some View {
        ScrollView {
            content
        }
        .refreshable {
            await action()
        }
        .overlay(alignment: .top) {
            if isRefreshing {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Color.warmPrimaryAccent)
                    .padding(.top, 4)
            }
        }
    }
}