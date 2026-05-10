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
            "iphone 17 pro", "iphone 17 pro max", "iphone 16 pro", "iphone 16 pro max", "iphone 15 pro max"
        ]
        let lower = name.lowercased()
        if genericNames.contains(lower) {
            return nil
        }

        if !name.isEmpty {
            // "O'Brien's iPhone" → "O'Brien" (split at "'s" suffix)
            // "Yezid's iPhone" → "Yezid"
            if let aposIndex = name.firstIndex(of: "'"),
               name.distance(from: aposIndex, to: name.endIndex) >= 2,
               name[name.index(after: aposIndex)] == "s" {
                let firstName = String(name[..<aposIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
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