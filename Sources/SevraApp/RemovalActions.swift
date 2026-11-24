import Foundation
import SevraCore

extension WorkspaceState {
  /// The person's own Remove or Restore, from a button or a menu. Clicking is the confirmation.
  func removeOrRestore(_ id: String, removing: Bool) {
    guard let (book, ticket) = beginOperation(removing ? "Removing" : "Restoring") else { return }
    let chat = conversation
    let route = self.route
    let navigationID = itemPreviewIdentity
    Task {
      defer {
        finishOperation(
          ticket, in: book,
          successStatus: removing ? "Removed. Restore brings it back." : "Restored.")
      }
      do {
        let (result, link) = try await Task.detached { () -> (Value, String) in
          try ticket.cancellation.check()
          let actor = ChangeActor.human("SevraApp.review")
          let result =
            removing ? try book.remove(id, actor: actor) : try book.restore(id, actor: actor)
          let title = "“" + result["title"].text + "”"
          let link =
            result["type"] == .string("item")
            ? (try? book.item(result["id"].text).referenceMarkdown) ?? title : title
          return (result, link)
        }.value
        _ = try book.addMessage(
          (removing ? "Removed " : "Restored ") + link
            + (removing ? ". History keeps it, and Restore brings it back." : ".")
            + (result["note"].string.map { " " + $0 } ?? ""),
          role: "event", conversation: chat)
        guard owns(ticket, in: book) else { return }
        refresh()
        guard conversation == chat, self.route == route else { return }
        let target = result["id"].text
        switch result["type"].text {
        case "item":
          if itemPreviewIdentity == navigationID,
            let current = try? book.item(target)
          {
            navigate(.item(current.id), replacing: true)
          }
        case "table": navigate(.table(target), replacing: true)
        case "view", "app": navigate(.space(removing ? "home" : target), replacing: true)
        default: break
        }
      } catch { report(error, for: ticket, in: book) }
    }
  }
}
