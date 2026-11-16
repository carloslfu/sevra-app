import Foundation

/// One coherent window projection. Large source bodies and asset bytes are not
/// included in the recent catalog; the existing conversation window stays bounded.
public struct WorkspaceSnapshot: Sendable {
  public let revision: Int
  public let datasetSnapshot: String
  public let spaces: [Space]
  public let spaceNavigation: SpaceNavigationState
  public let items: [ItemSummary]
  public let datasets: [Dataset]
  public let archivedDatasets: [Dataset]
  public let messages: [Message]
  public let requestActivities: [RequestActivity]
  public let reviewQueue: ReviewQueuePage
  public let proposalReviews: [String: ProposalReviewState]
  public let hasEarlierMessages: Bool
  public let hasLaterMessages: Bool
  public let conversations: [Value]
  public let chapters: [Value]
  public let bookmarks: [Value]
  public let pendingExtractions: [Value]
  public let intakeStatus: [Value]
  public let homeDocuments: [ItemSummary]
  public let pendingWorkflows: [Value]
  public let chatApproval: ChatApproval?
  public let pendingInput: ConversationSurface?
  public let visuals: [String: [VisualResult]]
  public let resumableAnswer: String?
  public let excelImports: [Value]
}

extension Workbook {
  /// Resume documents rather than technical observations made while creating apps/tables.
  func homeRecentDocuments() throws -> [ItemSummary] {
    try db.execute(
      """
      SELECT i.id,i.category,i.kind,i.title,i.meaning,i.status,i.asset_id
      FROM items i JOIN heads h ON h.item_id=i.id
      WHERE i.status!='withdrawn' AND (i.asset_id IS NOT NULL OR i.kind='document'
        OR (i.kind='note' AND i.status='accepted'))
        AND i.kind NOT IN ('row',\(Item.technicalKindSQL))
      ORDER BY i.created DESC,i.id LIMIT 3
      """, maxRows: 3, maxBytes: 262_144
    ).map { row in
      ItemSummary(
        id: row["id"]!.text, category: row["category"]!.text,
        kind: row["kind"]!.text, title: row["title"]!.text, meaning: row["meaning"]!.text,
        status: row["status"]!.text, assetID: row["asset_id"]?.string)
    }
  }
  /// Bounded, factual attention. Completed runs never crowd out unresolved work.
  func homeWorkflowAttention() throws -> [Value] {
    try db.execute(
      """
      SELECT r.id,r.state,r.detail,d.title FROM workflow_runs r
      JOIN app_definitions d ON d.id=r.definition_id
      WHERE r.state IN ('waiting_review','needs_attention','queued')
      ORDER BY CASE r.state WHEN 'needs_attention' THEN 0 WHEN 'waiting_review' THEN 1 ELSE 2 END,
        r.updated DESC,r.id DESC LIMIT 4
      """, maxRows: 4, maxBytes: 262_144
    ).map(Value.object)
  }
  /// Call off the UI actor. A cancelled waiter must not remain queued behind an
  /// unrelated long search, and all fields must come from the same SQLite view.
  public func workspaceSnapshot(
    conversation: String, messageAnchor: String? = nil, ifChangedFrom revision: Int? = nil,
    ifSpaceNavigationMatches navigation: SpaceNavigationState? = nil,
    cancellation: Cancellation = .init(), deadlineSeconds: TimeInterval = 3
  ) throws -> WorkspaceSnapshot? {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: deadlineSeconds)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: deadlineSeconds) {
        try db.readTransaction {
          let current = try self.revision()
          let spaceNavigation = try readSpaceNavigation()
          if current == revision && (navigation == nil || navigation == spaceNavigation) {
            return nil
          }
          if let messageAnchor {
            try require(
              try messageLocation(messageAnchor)["conversation_id"].text == conversation,
              "history_scope", "The message is not in this conversation.")
          }
          let history = try readConversationWindow(
            conversation: conversation, around: messageAnchor, cancellation: control,
            reservedPresentationBytes: 128 * 1024)
          return try WorkspaceSnapshot(
            revision: current, datasetSnapshot: datasetReadSnapshot(), spaces: spaces(),
            spaceNavigation: spaceNavigation,
            items: recentItemSummaries(), datasets: datasets(),
            archivedDatasets: datasets(archived: true),
            messages: history.messages,
            requestActivities: requestActivities(
              messageIDs: history.messages.filter { $0.role == "user" }.map(\.id),
              conversation: conversation),
            reviewQueue: reviewQueue(limit: 5, cancellation: control),
            proposalReviews: proposalReviewStates(
              messages: history.messages, conversation: conversation, cancellation: control),
            hasEarlierMessages: history.hasEarlier,
            hasLaterMessages: history.hasLater,
            conversations: conversations(), chapters: chapters(),
            bookmarks: chapters(bookmarks: true),
            pendingExtractions: pendingExtractions(), intakeStatus: intakeStatus(),
            homeDocuments: homeRecentDocuments(), pendingWorkflows: homeWorkflowAttention(),
            chatApproval: pendingChatApproval(conversation: conversation),
            pendingInput: pendingConversationInput(conversation: conversation),
            visuals: conversationVisuals(
              history.messages, conversation: conversation, anchor: messageAnchor),
            resumableAnswer: resumableConversationAnswer(conversation: conversation),
            excelImports: excelConversionSummaries())
        }
      }
    }
  }
}
