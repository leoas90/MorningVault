import SwiftUI

/// The kit's one entry point: a single list of today's events and past
/// meetings, with one button that starts a new meeting. Hosts (like
/// MorningVault) drop it straight into a tab.
public struct MeetingsHubView: View {
    public init() {}

    public var body: some View {
        HomeScreen()
    }
}

/// Earlier name of `MeetingsHubView`. Kept so older hosts still compile.
@available(*, deprecated, renamed: "MeetingsHubView")
public typealias MeetingsRootView = MeetingsHubView
