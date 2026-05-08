import Foundation
import UIKit

final class ContactsService {
    static let shared = ContactsService()
    private init() {}

    /// Fetches a personal name for the greeting.
    /// Uses the device/contact card name on real hardware.
    /// Returns nil if no personal name is set (keeps @AppStorage default).
    func fetchDeviceName() async -> String? {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip generic device names that aren't personal names
        let genericSuffixes = ["iPhone", "iPad", "Simulator", "Mac"]
        for suffix in genericSuffixes {
            if name.hasSuffix(suffix) || name == suffix {
                return nil
            }
        }

        // Also strip trailing "'s iPhone" patterns but keep the first name
        let components = name.components(separatedBy: "'")
        if let first = components.first, !first.isEmpty {
            return first.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return name.isEmpty ? nil : name
    }
}