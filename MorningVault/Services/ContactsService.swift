import Foundation
import Contacts
import UIKit

final class ContactsService {
    static let shared = ContactsService()
    private let store = CNContactStore()

    /// Fetches the user's personal name from Contacts Me card or device.
    func fetchDeviceName() async -> String? {
        if let meName = await fetchMeCardName() {
            return meName
        }
        return fallbackDeviceName()
    }

    // MARK: - Me Card

    private func fetchMeCardName() async -> String? {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            let granted = await requestContactsAccess()
            guard granted else { return nil }
        } else if status == .denied || status == .restricted {
            return nil
        }

        return await fetchMeCardOnMainActor()
    }

    private func requestContactsAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    @MainActor
    private func fetchMeCardOnMainActor() -> String? {
        // Use Mirror to read the unifiedMeContactIdentifier property
        // On iOS 18+ it's a real property; on iOS 17 and below it's absent
        let identifier: String? = {
            let mirror = Mirror(reflecting: store)
            for child in mirror.children {
                if child.label == "unifiedMeContactIdentifier" {
                    return child.value as? String
                }
            }
            return nil
        }()

        guard let contactId = identifier, !contactId.isEmpty else {
            return nil
        }

        do {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor
            ]
            let contact = try store.unifiedContact(withIdentifier: contactId, keysToFetch: keys)
            return displayName(from: contact)
        } catch {
            return nil
        }
    }

    private func displayName(from contact: CNContact) -> String? {
        let given = contact.givenName.trimmingCharacters(in: .whitespacesAndNewlines)
        let family = contact.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !given.isEmpty { return given }
        if !family.isEmpty { return family }
        return nil
    }

    // MARK: - Device name fallback

    private func fallbackDeviceName() -> String? {
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericSuffixes = ["iPhone", "iPad", "Simulator", "Mac"]

        if !name.isEmpty {
            let lower = name.lowercased()
            let isGeneric = genericSuffixes.contains { lower.hasSuffix($0.lowercased()) || lower == $0.lowercased() }
            if !isGeneric {
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