import SwiftUI

/// The entry point of the kit.
///
/// MorningVault can drop this straight into a tab: it brings the home list and
/// the recorder with it.
public struct MeetingsRootView: View {
    /// Kept for source compatibility with earlier hosts.
    public enum Tab: String, Hashable, CaseIterable, Sendable {
        case record
        case today
        case library
    }

    public init(initialTab: Tab = .record) {}

    public var body: some View {
        HomeScreen()
    }
}
