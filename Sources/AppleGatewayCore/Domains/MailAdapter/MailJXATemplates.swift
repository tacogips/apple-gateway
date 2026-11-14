import Foundation

public enum MailJXATemplate: String, CaseIterable, Sendable {
  case setRead
  case setFlagged
  case move
  case delete

  public var source: String {
    Self.helpers + "\n\n" + operation
  }

  private var operation: String {
    switch self {
    case .setRead:
      """
      function run(argv) {
        const input = JSON.parse(argv[0]);
        const app = Application('Mail');
        const message = findTargetMessage(app, input.target);
        message.readStatus = input.value;
        return JSON.stringify({ success: true });
      }
      """
    case .setFlagged:
      """
      function run(argv) {
        const input = JSON.parse(argv[0]);
        const app = Application('Mail');
        const message = findTargetMessage(app, input.target);
        message.flaggedStatus = input.value;
        return JSON.stringify({ success: true });
      }
      """
    case .move:
      """
      function run(argv) {
        const input = JSON.parse(argv[0]);
        const app = Application('Mail');
        const message = findTargetMessage(app, input.target);
        const destination = findMailbox(app, input.destination);
        app.move(message, { to: destination });
        return JSON.stringify({ success: true });
      }
      """
    case .delete:
      """
      function run(argv) {
        const input = JSON.parse(argv[0]);
        const app = Application('Mail');
        const message = findTargetMessage(app, input.target);
        app.delete(message);
        return JSON.stringify({ success: true });
      }
      """
    }
  }

  private static let helpers = """
  function normalizedMailValue(value) {
    try {
      if (value === null || value === undefined) {
        return null;
      }
      const text = String(value).trim();
      if (!text || text.toLowerCase() === 'missing value') {
        return null;
      }
      return text;
    } catch (error) {
      return null;
    }
  }

  function accountCandidates(app, accountName) {
    const accounts = app.accounts();
    const exact = accounts.filter(account => {
      try {
        return String(account.name()) === accountName;
      } catch (error) {
        return false;
      }
    });
    return exact.length > 0 ? exact : accounts;
  }

  function walkMailboxes(mailboxes, parentPath, visit) {
    mailboxes.forEach(mailbox => {
      const name = String(mailbox.name());
      const path = parentPath ? parentPath + '/' + name : name;
      visit(mailbox, path);
      let children = [];
      try {
        children = mailbox.mailboxes();
      } catch (error) {
        children = [];
      }
      walkMailboxes(children, path, visit);
    });
  }

  function mailboxCandidates(app, target) {
    const matches = [];
    accountCandidates(app, target.accountName).forEach(account => {
      walkMailboxes(account.mailboxes(), '', (mailbox, path) => {
        if (path === target.mailboxPath || String(mailbox.name()) === target.mailboxPath) {
          matches.push(mailbox);
        }
      });
    });
    return matches;
  }

  function findMailbox(app, target) {
    const matches = mailboxCandidates(app, target);
    if (matches.length === 0) {
      throw new Error('APPLE_GATEWAY_MAILBOX_NOT_FOUND:' + target.mailboxId);
    }
    return matches[0];
  }

  function messageMatches(message, target) {
    const rfcMessageId = normalizedMailValue(message.messageId());
    if (target.rfcMessageId && rfcMessageId === target.rfcMessageId) {
      return true;
    }
    return normalizedMailValue(message.id()) === String(target.storeRowId);
  }

  function findTargetMessage(app, target) {
    const mailboxes = mailboxCandidates(app, {
      accountName: target.accountName,
      mailboxPath: target.mailboxPath
    });
    for (let mailboxIndex = 0; mailboxIndex < mailboxes.length; mailboxIndex += 1) {
      const messages = mailboxes[mailboxIndex].messages();
      for (let messageIndex = 0; messageIndex < messages.length; messageIndex += 1) {
        const message = messages[messageIndex];
        if (messageMatches(message, target)) {
          return message;
        }
      }
    }
    throw new Error('APPLE_GATEWAY_MESSAGE_NOT_FOUND:' + target.messageId);
  }
  """
}
