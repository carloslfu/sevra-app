import Foundation
import SevraCore

extension WorkspaceState {
  /// The person's own Remove or Restore on an open item. Clicking is the confirmation.
  func removeOrRestore(_ id: String, removing: Bool) {
    guard let (book, ticket) = beginOperation(removing ? "Removing" : "Restoring") else { return }
    let chat = conversation
    let navigationID = itemPreviewIdentity
    Task {
      defer {
        finishOperation(
          ticket, in: book,
          successStatus: removing ? "Removed. Restore brings it back." : "Restored.")
      }
      do {
        let (result, current) = try await Task.detached {
          try ticket.cancellation.check()
          let actor = ChangeActor.human("SevraApp.review")
          let result =
            removing ? try book.remove(id, actor: actor) : try book.restore(id, actor: actor)
          return (result, try book.item(result["id"].text))
        }.value
        _ = try book.addMessage(
          (removing ? "Removed " : "Restored ") + current.referenceMarkdown
            + (removing ? ". History keeps it, and Restore brings it back." : "."),
          role: "event", conversation: chat)
        guard owns(ticket, in: book), result["status"] != .null else { return }
        refresh()
        if conversation == chat, itemPreviewIdentity == navigationID {
          navigate(.item(current.id), replacing: true)
        }
      } catch { report(error, for: ticket, in: book) }
    }
  }
}
