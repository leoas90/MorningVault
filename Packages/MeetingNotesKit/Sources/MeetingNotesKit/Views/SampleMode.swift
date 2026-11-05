import SwiftUI

private struct MeetingSampleModeKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Fills the screens with sample content.
    ///
    /// The host app turns this on when it takes a picture of the app, so the
    /// picture shows a meeting in progress instead of an empty screen.
    var meetingSampleMode: Bool {
        get { self[MeetingSampleModeKey.self] }
        set { self[MeetingSampleModeKey.self] = newValue }
    }
}
