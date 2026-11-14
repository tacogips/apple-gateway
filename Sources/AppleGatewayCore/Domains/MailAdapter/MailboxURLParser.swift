import CryptoKit
import Foundation

struct MailboxURLInfo: Equatable, Sendable {
  var accountKey: String
  var accountId: String
  var accountKind: MailAccountKind
  var fallbackAccountName: String
  var path: String
  var name: String
}

enum MailStableIdentifier {
  static func accountId(accountKey: String) -> String {
    "mail-account-\(shortHash(accountKey))"
  }

  static func mailboxId(rowId: Int64, accountKey: String) -> String {
    "mailbox-\(rowId)-\(shortHash(accountKey))"
  }

  static func messageId(rowId: Int64) -> String {
    "message-\(rowId)"
  }

  static func messageRowId(_ messageId: String) -> Int64? {
    guard messageId.hasPrefix("message-") else {
      return nil
    }
    let value = String(messageId.dropFirst("message-".count))
    guard let rowId = Int64(value), rowId > 0 else {
      return nil
    }
    return rowId
  }

  private static func shortHash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
  }
}

enum MailboxURLParser {
  static func parse(_ value: String, rowId: Int64) -> MailboxURLInfo {
    guard let components = URLComponents(string: value), let scheme = components.scheme?.lowercased() else {
      return unknown(value, rowId: rowId)
    }

    let kind = kind(for: scheme)
    let accountKey = key(components: components, scheme: scheme, kind: kind, rawValue: value)
    let accountId = MailStableIdentifier.accountId(accountKey: accountKey)
    let path = mailboxPath(components: components, rowId: rowId)
    return MailboxURLInfo(
      accountKey: accountKey,
      accountId: accountId,
      accountKind: kind,
      fallbackAccountName: fallbackAccountName(components: components, kind: kind, rawValue: value),
      path: path,
      name: path.split(separator: "/").last.map(String.init) ?? "Mailbox \(rowId)"
    )
  }

  private static func unknown(_ value: String, rowId: Int64) -> MailboxURLInfo {
    let accountKey = "unknown:\(value.lowercased())"
    let path = value.isEmpty ? "Mailbox \(rowId)" : value
    return MailboxURLInfo(
      accountKey: accountKey,
      accountId: MailStableIdentifier.accountId(accountKey: accountKey),
      accountKind: .unknown,
      fallbackAccountName: "Unknown Account",
      path: path,
      name: path.split(separator: "/").last.map(String.init) ?? path
    )
  }

  private static func kind(for scheme: String) -> MailAccountKind {
    switch scheme {
    case "imap", "imaps":
      return .imap
    case "ews", "exchange":
      return .exchange
    case "local", "file":
      return .local
    case "pop", "pops":
      return .pop
    default:
      return .unknown
    }
  }

  private static func key(
    components: URLComponents,
    scheme: String,
    kind: MailAccountKind,
    rawValue: String
  ) -> String {
    if kind == .local {
      return "local"
    }
    let user = components.user?.removingPercentEncoding
    let host = components.host?.lowercased()
    let authority = [user, host].compactMap { $0 }.joined(separator: "@")
    if !authority.isEmpty {
      return "\(scheme)://\(authority)"
    }
    return "\(scheme):\(rawValue.lowercased())"
  }

  private static func fallbackAccountName(
    components: URLComponents,
    kind: MailAccountKind,
    rawValue: String
  ) -> String {
    if kind == .unknown {
      return "Unknown Account"
    }
    if kind == .local {
      return "On My Mac"
    }
    if let user = components.user?.removingPercentEncoding, let host = components.host, !user.isEmpty {
      return "\(user)@\(host)"
    }
    if let host = components.host, !host.isEmpty {
      return host
    }
    return rawValue
  }

  private static func mailboxPath(components: URLComponents, rowId: Int64) -> String {
    let rawPath = components.percentEncodedPath.removingPercentEncoding ?? components.path
    let components = rawPath
      .split(separator: "/")
      .map { component -> String in
        let value = String(component)
        if value.hasSuffix(".mbox") {
          return String(value.dropLast(5))
        }
        return value
      }
      .filter { !$0.isEmpty }
    return components.isEmpty ? "Mailbox \(rowId)" : components.joined(separator: "/")
  }
}
