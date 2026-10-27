import Foundation

/// One coherent window projection. Large source bodies and asset bytes are not
/// included in the recent catalog; the existing conversation window stays bounded.
public struct WorkspaceSnapshot: Sendable {
  public let revision: Int
  public let spaces: [Space]
  public let items: [ItemSummary]
  public let datasets: [Dataset]
  public let messages: [Message]
  public let hasEarlierMessages: Bool
  public let hasLaterMessages: Bool
  public let conversations: [Value]
  public let chapters: [Value]
  public let bookmarks: [Value]
  public let pendingExtractions: [Value]
  public let intakeStatus: [Value]
}

extension Workbook {
  /// Call off the UI actor. A cancelled waiter must not remain queued behind an
  /// unrelated long search, and all fields must come from the same SQLite view.
  public func workspaceSnapshot(
    conversation: String, messageAnchor: String? = nil, ifChangedFrom revision: Int? = nil,
    cancellation: Cancellation = .init(), deadlineSeconds: TimeInterval = 3
  ) throws -> WorkspaceSnapshot? {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: deadlineSeconds)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: deadlineSeconds) {
        try db.readTransaction {
          let current = try self.revision()
          if current == revision { return nil }
          if let messageAnchor {
            try require(
              try messageLocation(messageAnchor)["conversation_id"].text == conversation,
              "history_scope", "The message is not in this conversation.")
          }
          let history = try readConversationWindow(
            conversation: conversation, around: messageAnchor, cancellation: control)
          return try WorkspaceSnapshot(
            revision: current, spaces: spaces(), items: recentItemSummaries(), datasets: datasets(),
            messages: history.messages, hasEarlierMessages: history.hasEarlier,
            hasLaterMessages: history.hasLater,
            conversations: conversations(), chapters: chapters(),
            bookmarks: chapters(bookmarks: true),
            pendingExtractions: pendingExtractions(), intakeStatus: intakeStatus())
        }
      }
    }
  }
}
