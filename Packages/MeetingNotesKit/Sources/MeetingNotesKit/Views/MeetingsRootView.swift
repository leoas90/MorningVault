import SwiftUI

/// The entry point of the kit.
///
/// MorningVault can drop this straight into a tab: it brings the recorder, the
/// day view and the meeting library with it.
public struct MeetingsRootView: View {
    /// The tabs the root view shows.
    public enum Tab: String, Hashable, CaseIterable, Sendable {
        case record
        case today
        case library
    }

    @State private var selection: Tab

    public init(initialTab: Tab = .record) {
        _selection = State(initialValue: initialTab)
    }

    public var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Record", systemImage: "waveform", value: Tab.record) {
                RecordScreen()
            }
            SwiftUI.Tab("Today", systemImage: "calendar", value: Tab.today) {
                TodayScreen()
            }
            SwiftUI.Tab("Library", systemImage: "books.vertical", value: Tab.library) {
                LibraryScreen()
            }
        }
    }
}
