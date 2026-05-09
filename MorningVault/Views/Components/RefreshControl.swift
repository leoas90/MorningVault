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

