import Foundation
import Contacts
import UIKit

final class ContactsService {
    static let shared = ContactsService()
    private let store = CNContactStore()

    /// Fetches the user's name from their "Me" contact card in Contacts.
    /// Falls back to device name → nil if unavailable.
    func fetchDeviceName() async -> String? {
        if let meName = await fetchMeCardName() {
            return meName
        }
        return fallbackDeviceName()
    }

    // MARK: - Me Card

    private func fetchMeCardName() async -> String? {
        // Request contacts permission if not determined
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            let granted = await requestContactsAccess()
            guard granted else { return nil }
        } else if status == .denied || status == .restricted {
            return nil
        }

        // Use the unifiedMeContactIdentifier on iOS 18+
        // For iOS 17, fall back to device name
        return await storeUnifiedMeName()
    }

    private func requestContactsAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    /// Attempts to read the Me card using iOS 18+ `unifiedMeContactIdentifier` property.
    /// Returns nil if unavailable (iOS < 18) so caller can use fallback.
    private func storeUnifiedMeName() async -> String? {
        // unifiedMeContactIdentifier is available on iOS 18+
        // We use optional chaining to safely access it on older versions
        let identifier: String? = await MainActor.run {
            // Check if the property exists via mirror or directly
            let mirror = Mirror(reflecting: store)
            for child in mirror.children {
                if child.label == "unifiedMeContactIdentifier" {
                    return child.value as? String
                }
            }
            return nil
        }

        guard let contactId = identifier, !contactId.isEmpty else {
            return nil
        }

        return await fetchName(for: contactId)
    }

    private func fetchName(for identifier: String) async -> String? {
        return await MainActor.run {
            do {
                let keys: [CNKeyDescriptor] = [
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor
                ]
                let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys)
                return displayName(from: contact)
            } catch {
                return nil
            }
        }
    }

    private func displayName(from contact: CNContact) -> String? {
        let given = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given }
        if !family.isEmpty { return family }
        return nil
    }

    // MARK: - Fallback device name

    private func fallbackDeviceName() -> String? {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericSuffixes = ["iPhone", "iPad", "Simulator", "Mac"]

        if !name.isEmpty {
            let lower = name.lowercased()
            let isGeneric = genericSuffixes.contains { lower.hasSuffix($0.lowercased()) || lower == $0.lowercased() }
            if !isGeneric {
                // "Yezid's iPhone" → "Yezid"
                if let apostropheIndex = name.firstIndex(of: "'") {
                    let firstName = String(name[..<apostropheIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !firstName.isEmpty { return firstName }
                }
                return name
            }
        }
        return nil
    }
}