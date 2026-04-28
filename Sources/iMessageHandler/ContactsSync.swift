import Contacts
import Foundation

final class ContactsSync: @unchecked Sendable {
    private let store = CNContactStore()

    func loadContacts() throws -> [ContactIdentity] {
        try ensureAccess()

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        var identities: [ContactIdentity] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let name = displayName(for: contact)
            guard !name.isEmpty else {
                return
            }

            for phone in contact.phoneNumbers {
                for value in phoneVariants(phone.value.stringValue) {
                    identities.append(ContactIdentity(
                        identityValue: value,
                        kind: "phone",
                        displayName: name,
                        givenName: emptyToNil(contact.givenName),
                        familyName: emptyToNil(contact.familyName),
                        organizationName: emptyToNil(contact.organizationName)
                    ))
                }
            }

            for email in contact.emailAddresses {
                let value = String(email.value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !value.isEmpty else {
                    continue
                }
                identities.append(ContactIdentity(
                    identityValue: value,
                    kind: "email",
                    displayName: name,
                    givenName: emptyToNil(contact.givenName),
                    familyName: emptyToNil(contact.familyName),
                    organizationName: emptyToNil(contact.organizationName)
                ))
            }
        }

        var seen = Set<String>()
        return identities.filter { identity in
            let key = "\(identity.kind):\(identity.identityValue)"
            guard !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func ensureAccess() throws {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            let result = ContactAccessResult()
            store.requestAccess(for: .contacts) { ok, error in
                result.granted = ok
                result.error = error
                semaphore.signal()
            }
            semaphore.wait()
            if let requestError = result.error {
                throw requestError
            }
            if result.granted {
                return
            }
            throw AppError.server("contacts access was not granted")
        default:
            throw AppError.server("contacts access is not authorized for this app")
        }
    }
}

private final class ContactAccessResult: @unchecked Sendable {
    var granted = false
    var error: Error?
}

private func displayName(for contact: CNContact) -> String {
    let personal = [contact.givenName, contact.familyName]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    if !personal.isEmpty {
        return personal
    }
    return contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func phoneVariants(_ raw: String) -> [String] {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = trimmed.filter(\.isNumber)
    guard !digits.isEmpty else {
        return []
    }

    var values = Set<String>()
    values.insert(trimmed.lowercased())
    values.insert(digits)
    values.insert("+\(digits)")

    if digits.hasPrefix("0"), digits.count >= 9 {
        let withoutLeadingZero = String(digits.dropFirst())
        values.insert("+61\(withoutLeadingZero)")
        values.insert("61\(withoutLeadingZero)")
    }

    return Array(values)
}

private func emptyToNil(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
