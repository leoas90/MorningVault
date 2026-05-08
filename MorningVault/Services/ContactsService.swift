import Foundation
import UIKit

final class ContactsService {
    static let shared = ContactsService()

    /// Fetches the user's personal name for the greeting.
    /// Uses the device name set in iPhone Settings → General → AirDrop → Name
    /// e.g. "Yezid's iPhone" → "Yezid"
    func fetchDeviceName() -> String? {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip common generic/placeholder names
        let genericNames = [
            "iphone", "ipad", "simulator", "mac",
            "mobile user", "user", "admin", "guest",
            "iphone 17 pro", "iphone 17", "iphone 16"
        ]
        let lower = name.lowercased()
        if genericNames.contains(lower) {
            return nil
        }

        if !name.isEmpty {
            // "Yezid's iPhone" → "Yezid"
            if let apostropheIndex = name.firstIndex(of: "'") {
                let firstName = String(name[..<apostropheIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !firstName.isEmpty && firstName.count > 1 {
                    return firstName
                }
            }
            // "Yezid Rodriguez" (no apostrophe) → "Yezid Rodriguez"
            if name.contains(" ") {
                return name
            }
            return name
        }

        return nil
    }
}