import SwiftUI

/// The kit's screens behind a segmented control instead of a tab bar, for hosts
/// (like MorningVault) that already have their own tab bar. Avoids tabs inside tabs.
public struct MeetingsHubView: View {
    @State private var selection: MeetingsRootView.Tab

    public init(initialTab: MeetingsRootView.Tab = .record) {
        _selection = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Meetings", selection: $selection) {
                Text("Record").tag(MeetingsRootView.Tab.record)
                Text("Today").tag(MeetingsRootView.Tab.today)
                Text("Library").tag(MeetingsRootView.Tab.library)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selection {
            case .record: RecordScreen()
            case .today: TodayScreen()
            case .library: LibraryScreen()
            }
        }
    }
}
