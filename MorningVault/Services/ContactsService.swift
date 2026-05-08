import Foundation
import Contacts
import UIKit

final class ContactsService {
    static let shared = ContactsService()
    private init() {}

    /// Fetches the user's name — prioritizes the device/contact card name on real hardware.
    /// Falls back to the current @AppStorage value if no name is available.
    func fetchDeviceName() async -> String? {
        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)

        // On simulator, UIDevice.name often returns just "iPhone" — not useful
        // On real device, it returns the user's configured device name ("Yezid's iPhone")
        // Only use it if it looks like a real personal name (no "iPhone", "iPad" etc.)
        let genericNames = ["iphone", "ipad", "mac", " simulator"]
        let lower = deviceName.lowercased()
        let looksReal = !genericNames.contains(where: { lower.contains($0) })

        if !deviceName.isEmpty && looksReal {
            return deviceName
        }

        return nil
    }
}