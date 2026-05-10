import Foundation
import Contacts
import UIKit

/// Fetches the user's personal name for the greeting.
/// Uses CNContactStore.me (iOS 18+) — reads only the user's own contact card,
/// not all contacts. Falls back to device name if contact access is denied.
final class ContactsService {
    static let shared = ContactsService()

    private let contactStore = CNContactStore()

    /// Fetches the user's personal name for the greeting.
    /// Reads from the user's contact card (Me card in Contacts app).
    /// Falls back to device name if contact access is denied or Me card unavailable.
    func fetchDeviceName() -> String? {
        if let contactName = fetchMeCardName() {
            return contactName
        }
        return fetchDeviceNameFallback()
    }

    // MARK: - Me Card (iOS 18+)

    /// Fetches the user's name from their contact card via CNContactStore.me.
    /// This reads ONLY the user's own card — not all contacts.
    private func fetchMeCardName() -> String? {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status != .denied else {
            print("[ContactsService] Contact access denied")
            return nil
        }

        guard #available(iOS 18.0, *) else {
            // Fallback for older iOS — use enumerate with "me" identifier
            return fetchMeCardLegacy()
        }

        // Use CNContactStore.me to fetch only the user's card
        do {
            let meIdentifier = contactStore.me
            guard let identifier = meIdentifier else {
                print("[ContactsService] No Me card set on this device")
                return nil
            }

            let keysToFetch: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor
            ]

            let contact = try contactStore.unifiedContact(withIdentifier: identifier, keysToFetch: keysToFetch)

            // Prefer nickname over given name
            let name: String?
            if !contact.nickname.isEmpty {
                name = contact.nickname
            } else if !contact.givenName.isEmpty {
                name = contact.familyName.isEmpty
                    ? contact.givenName
                    : "\(contact.givenName) \(contact.familyName)"
            } else {
                name = nil
            }

            if let name = name, !name.isEmpty, name.count > 1 {
                return name
            }

            return nil
        } catch {
            print("[ContactsService] Could not fetch Me card: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Legacy fallback (iOS < 18)

    /// Legacy fallback: enumerates contacts looking for identifier == "me".
    /// Only used on iOS versions before 18 where CNContactStore.me is unavailable.
    private func fetchMeCardLegacy() -> String? {
        do {
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor
            ]

            let request = CNContactFetchRequest(keysToFetch: keysToFetch)

            var meContact: CNContact?
            try contactStore.enumerateContacts(with: request) { contact, _ in
                if contact.identifier == "me" {
                    meContact = contact
                }
            }

            if let contact = meContact {
                let givenName = contact.givenName
                let familyName = contact.familyName
                if !givenName.isEmpty {
                    let fullName = familyName.isEmpty ? givenName : "\(givenName) \(familyName)"
                    if fullName.count > 1 {
                        return fullName
                    }
                }
            }

            return nil
        } catch {
            print("[ContactsService] Legacy Me card enumeration failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Device name fallback

    /// Fallback: reads device name set in iPhone Settings → General → AirDrop → Name.
    /// e.g. "Yezid's iPhone" → "Yezid"
    private func fetchDeviceNameFallback() -> String? {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let genericNames: Set<String> = [
            "iphone", "ipad", "simulator", "mac",
            "mobile user", "user", "admin", "guest",
            "iphone 17 pro", "iphone 17 pro max", "iphone 16 pro", "iphone 16 pro max", "iphone 15 pro max",
            "john iphone", "jane iphone", "my iphone", "user's iphone"
        ]

        let lower = name.lowercased()
        if genericNames.contains(lower) {
            return nil
        }

        if !name.isEmpty {
            // "Yezid's iPhone" → "Yezid"
            if let aposIndex = name.firstIndex(of: "'"),
               name.distance(from: aposIndex, to: name.endIndex) >= 2,
               name[name.index(after: aposIndex)] == "s" {
                let firstName = String(name[..<aposIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !firstName.isEmpty && firstName.count > 1 {
                    return firstName
                }
            }
            // "Yezid Rodriguez" (full name, no apostrophe) → "Yezid Rodriguez"
            if name.contains(" ") {
                return name
            }
            return name
        }

        return nil
    }
}