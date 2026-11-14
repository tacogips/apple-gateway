import Foundation

#if canImport(Contacts)
import Contacts
#endif

protocol PhoneContactResolving: Sendable {
  func resolve(name: String, phoneLabel: String?) throws -> ResolvedPhoneTarget
}

struct LivePhoneContactResolver: PhoneContactResolving {
  func resolve(name: String, phoneLabel: String?) throws -> ResolvedPhoneTarget {
    #if canImport(Contacts)
    let store = CNContactStore()
    switch CNContactStore.authorizationStatus(for: .contacts) {
    case .authorized:
      break
    case .notDetermined:
      throw AppleGatewayError(
        code: .permissionNotDetermined,
        message: "Contacts permission has not been requested",
        details: ["hint": "Run apple-gateway permissions request --domain phone-calls"]
      )
    case .denied, .restricted:
      throw AppleGatewayError(
        code: .permissionDenied,
        message: "Contacts permission is required to call a contact by name"
      )
    case .limited:
      break
    @unknown default:
      throw AppleGatewayError(code: .permissionDenied, message: "Contacts access is unavailable")
    }

    let requestedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requestedName.isEmpty else {
      throw AppleGatewayError(code: .invalidArgument, message: "contactName must not be empty")
    }
    let keys = [
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor
    ]
    let contacts = try store.unifiedContacts(
      matching: CNContact.predicateForContacts(matchingName: requestedName),
      keysToFetch: keys
    )
    let exactMatches = contacts.filter { contact in
      let fullName = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
      return fullName.localizedCaseInsensitiveCompare(requestedName) == .orderedSame
        || contact.organizationName.localizedCaseInsensitiveCompare(requestedName) == .orderedSame
    }
    let matches = exactMatches.isEmpty ? contacts : exactMatches
    guard matches.count == 1, let contact = matches.first else {
      throw AppleGatewayError(
        code: .invalidArgument,
        message: matches.isEmpty ? "Contact was not found" : "Contact name is ambiguous",
        details: ["contactName": requestedName, "matches": "\(matches.count)"]
      )
    }

    let selected = try selectPhoneNumber(contact.phoneNumbers, requestedLabel: phoneLabel)
    let displayName = CNContactFormatter.string(from: contact, style: .fullName)
      ?? (contact.organizationName.isEmpty ? requestedName : contact.organizationName)
    return ResolvedPhoneTarget(phoneNumber: selected.value.stringValue, displayName: displayName)
    #else
    throw AppleGatewayError(code: .unsupportedOSVersion, message: "Contacts is unavailable on this platform")
    #endif
  }

  #if canImport(Contacts)
  private func selectPhoneNumber(
    _ numbers: [CNLabeledValue<CNPhoneNumber>],
    requestedLabel: String?
  ) throws -> CNLabeledValue<CNPhoneNumber> {
    guard !numbers.isEmpty else {
      throw AppleGatewayError(code: .invalidArgument, message: "Contact has no phone number")
    }
    if let requestedLabel {
      let normalizedLabel = requestedLabel.trimmingCharacters(in: .whitespacesAndNewlines)
      let matches = numbers.filter { number in
        let rawLabel = number.label ?? ""
        let localizedLabel = CNLabeledValue<NSString>.localizedString(forLabel: rawLabel)
        return rawLabel.localizedCaseInsensitiveCompare(normalizedLabel) == .orderedSame
          || localizedLabel.localizedCaseInsensitiveCompare(normalizedLabel) == .orderedSame
      }
      guard matches.count == 1, let match = matches.first else {
        throw AppleGatewayError(
          code: .invalidArgument,
          message: matches.isEmpty ? "Contact phone label was not found" : "Contact phone label is ambiguous",
          details: ["phoneLabel": normalizedLabel, "matches": "\(matches.count)"]
        )
      }
      return match
    }
    guard numbers.count == 1, let number = numbers.first else {
      let labels = numbers.map { CNLabeledValue<NSString>.localizedString(forLabel: $0.label ?? "other") }
      throw AppleGatewayError(
        code: .invalidArgument,
        message: "Contact has multiple phone numbers; phoneLabel is required",
        details: ["availableLabels": labels.joined(separator: ", ")]
      )
    }
    return number
  }
  #endif
}
