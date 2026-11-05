import SwiftUI

/// The kit's home screen for hosts (like MorningVault) that already have their
/// own tab bar: a single list of today's events and past meetings, with one
/// button that starts a new meeting.
public struct MeetingsHubView: View {
    /// Kept for source compatibility; the hub is a single home screen now.
    public init(initialTab: MeetingsRootView.Tab = .record) {}

    public var body: some View {
        HomeScreen()
    }
}
