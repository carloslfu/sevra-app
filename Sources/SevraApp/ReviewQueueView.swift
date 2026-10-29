import SevraCore
import SevraPreviewUI
import SwiftUI

struct DraftReviewRow: View {
  let item: ItemSummary
  let open: () -> Void
  var body: some View {
    Button(action: open) {
      VStack(alignment: .leading, spacing: 4) {
        Text(item.title).font(.headline)
        Text(
          item.kind.replacingOccurrences(of: "-", with: " ").capitalized
            + " · " + item.meaning.capitalized
        )
        .font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }.buttonStyle(.plain)
      .accessibilityLabel("Review " + item.title + ", " + item.meaning)
  }
}

struct ReviewQueueView: View {
  @ObservedObject var state: WorkspaceState
  @ObservedObject var results: ReviewQueueSession
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(
        "Open a draft to check its evidence before accepting. Drafts appear oldest first."
      )
      .foregroundStyle(.secondary)
      HStack {
        if results.hasPrevious || results.nextCursor != nil {
          Button("Previous") { Task { await load(direction: -1) } }
            .disabled(!results.hasPrevious || results.loading)
          Text("Page \(results.pageNumber)").font(.callout).foregroundStyle(.secondary)
          Button("Next") { Task { await load(direction: 1) } }
            .disabled(results.nextCursor == nil || results.loading)
        }
        Spacer()
        if results.loading { ProgressView().controlSize(.small) }
        Button("Refresh") { Task { await load(force: true) } }.disabled(results.loading)
      }
      if let failure = results.failure { Text(failure).foregroundStyle(.red) }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          ForEach(results.items) { item in
            DraftReviewRow(item: item) { state.navigate(.item(item.id)) }
            Divider()
          }
          if results.items.isEmpty && !results.loading && results.failure == nil {
            Text("No drafts waiting for review.").foregroundStyle(.secondary).padding(.top, 20)
          }
        }
      }
    }.padding(22)
      .task(id: state.pendingReview?.revision) { await load() }
      .onDisappear { results.cancel() }
  }
  func load(direction: Int = 0, force: Bool = false) async {
    guard let book = state.workbook else { return }
    await results.load(
      scope: book.url.path, revision: state.pendingReview?.revision ?? -1, direction: direction,
      force: force
    ) { cursor, cancellation in
      try await Task.detached(priority: .userInitiated) {
        try book.reviewQueue(cursor: cursor, cancellation: cancellation)
      }.value
    }
  }
}
