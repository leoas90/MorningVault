import SwiftUI

/// The meeting page on its own, filled with sample content.
///
/// The host app uses it to take a picture of the recorder without the tab bar.
public struct MeetingShowcaseView: View {
    public init() {}

    public var body: some View {
        MeetingScreen()
            .environment(\.vaultNotesSampleMode, true)
    }
}
