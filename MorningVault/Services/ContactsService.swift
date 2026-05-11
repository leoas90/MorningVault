import Foundation
@preconcurrency import Contacts
import UIKit

/// Fetches the user's personal name for the greeting.
/// Reads from the user's contact card (Me card in Contacts app).
/// Falls back to device name if contact access is denied or Me card unavailable.
final class ContactsService: @unchecked Sendable {
    static let shared = ContactsService()

    private let contactStore = CNContactStore()

    /// Async — fetches contact name off the main thread via detached task.
    func fetchDeviceName() async -> String? {
        let store = self.contactStore
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let contactName = Self.enumerateMeCardName(using: store)
                if let name = contactName {
                    continuation.resume(returning: name)
                } else {
                    // Fallback: UIDevice.current.name must run on main thread.
                    // We bridge to the main actor via Task and then resume.
                    Task { @MainActor in
                        let fallback = self.deviceNameFallback()
                        continuation.resume(returning: fallback)
                    }
                }
            }
        }
    }

    // MARK: - Me Card

    /// Enumerates contacts looking for identifier == "me".
    /// `CNContactStore.enumerateContacts` is thread-safe per Apple documentation.
    private nonisolated static func enumerateMeCardName(using store: CNContactStore) -> String? {
        do {
            let keysToFetch: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor
            ]

            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var meContact: CNContact?
            try store.enumerateContacts(with: request) { contact, _ in
                if contact.identifier == "me" {
                    meContact = contact
                }
            }

            if let contact = meContact, let name = Self.extractName(from: contact) {
                return name
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Extracts a displayable name from a CNContact, preferring nickname.
    private static func extractName(from contact: CNContact) -> String? {
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
    }

    // MARK: - Device name fallback

    /// Fallback: reads device name set in iPhone Settings → General → AirDrop → Name.
    /// e.g. "Yezid's iPhone" → "Yezid"
    private func deviceNameFallback() -> String? {
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