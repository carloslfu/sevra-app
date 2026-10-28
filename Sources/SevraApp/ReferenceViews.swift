import SevraCore
import SevraDocumentUI
import SevraSearchUI
import SwiftUI

enum ReferenceModal: Identifiable {
  case browser(ReferenceDirection)
  case choice(ReferenceOccurrence)
  var id: String {
    switch self {
    case .browser: return "browser"
    case .choice(let value): return value.id
    }
  }
}

struct ReferenceReadingText: View {
  let presentation: ReferencePresentation
  let open: (ReferenceOccurrence) -> Void
  private var attributed: AttributedString {
    var result = AttributedString()
    for part in presentation.parts {
      var text = AttributedString(part.text)
      if let occurrence = part.occurrence {
        text.link = occurrence.url
        if occurrence.reference.resolution != .bound { text.foregroundColor = .orange }
      }
      result += text
    }
    return result
  }
  var body: some View {
    Text(attributed).textSelection(.enabled)
      .environment(
        \.openURL,
        OpenURLAction { url in
          guard let occurrence = presentation.occurrences.first(where: { $0.url == url }) else {
            return .discarded
          }
          open(occurrence)
          return .handled
        })
  }
}

struct ReferencesPanel: View {
  let item: Item
  let workbook: Workbook
  @ObservedObject var session: ReferenceDocumentSession
  @ObservedObject var state: WorkspaceState
  let open: (ReferenceOccurrence) -> Void
  @StateObject private var incoming = ReferenceBrowserSession()
  @State private var historical = false
  @State private var exact = false
  @Environment(\.dismiss) private var dismiss
  private var showingIncoming: Bool { state.referencePanel == .incoming }
  private var query: ReferenceBrowserQuery {
    .init(origin: item.id, revision: state.revision, historical: historical, exact: exact)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(item.title).font(.headline).lineLimit(2)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Picker(
        "Connections",
        selection: Binding(
          get: { showingIncoming },
          set: {
            state.referencePanel = $0 ? .incoming : .outgoing
          })
      ) {
        Text("Links in this document").tag(false)
        Text("Mentioned in").tag(true)
      }.pickerStyle(.segmented)
      if showingIncoming {
        Toggle("Include earlier document versions", isOn: $historical)
        Toggle("Only mentions of this exact version", isOn: $exact)
        if incoming.loading { ProgressView("Finding saved mentions") }
        if let failure = incoming.failure {
          Text(failure).foregroundStyle(.red).textSelection(.enabled)
        }
        List(incoming.hits, id: \.text) { hit in
          Button {
            state.referenceModal = nil
            state.openEvidence(hit["evidence"]["id"].text, locator: hit["locator"].text)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(hit["evidence"]["title"].text).foregroundStyle(.primary)
              Text(
                "\(hit["mentionCount"].int ?? 0) mentions · " + hit["evidence"]["meaning"].text
                  + " · " + hit["evidence"]["status"].text
              ).font(.caption).foregroundStyle(.secondary)
              Text(hit["label"].text).lineLimit(2).foregroundStyle(.secondary)
            }
          }.buttonStyle(.plain)
            .accessibilityLabel("Open mentioning document: " + hit["evidence"]["title"].text)
        }
        if !incoming.loading && incoming.hits.isEmpty && incoming.failure == nil {
          Text("No saved mentions were found in this scope. Other content may be unindexed.")
            .foregroundStyle(.secondary)
        }
        HStack {
          Button("Previous") { Task { await incoming.load(query, workbook: workbook, step: -1) } }
            .disabled(!incoming.canGoBack || incoming.loading)
          Text("Page \(incoming.page)").font(.caption)
          Button("Next") { Task { await incoming.load(query, workbook: workbook, step: 1) } }
            .disabled(incoming.nextCursor == nil || incoming.loading)
          Spacer()
          Button("Start over") { Task { await incoming.load(query, workbook: workbook) } }
            .disabled(incoming.loading)
        }
      } else {
        if session.loading { ProgressView("Reading saved links") }
        if let failure = session.failure {
          Text(failure).foregroundStyle(.red).textSelection(.enabled)
        }
        List(session.document?.occurrences ?? []) { occurrence in
          HStack(alignment: .top) {
            Button {
              open(occurrence)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.reference.label).foregroundStyle(.primary)
                Text(
                  occurrence.kind == .body
                    ? "In document text"
                    : (DisplayText.location(occurrence.locator) ?? "In extracted file text")
                )
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if occurrence.reference.resolution != .bound {
                  Text(
                    occurrence.reference.resolution == .external
                      ? "Another workbook" : "Choose a destination"
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }
            }.buttonStyle(.plain)
              .accessibilityLabel("Open link: " + occurrence.reference.label)
            Spacer()
            if canChoose(occurrence) {
              Button("Choose destination") {
                state.referenceChoice = occurrence
              }.buttonStyle(.link).disabled(state.busy)
                .accessibilityLabel("Choose destination for " + occurrence.reference.label)
            }
          }
        }
        if let document = session.document {
          if document.body.coverage == "not_indexed" {
            Button("Check document text for links") {
              state.run("Checking saved links") { book, cancel in
                _ = try book.indexReferences(item.id, cancellation: cancel)
              }
            }.disabled(state.busy)
          }
          if document.body.coverage != "ready"
            || (item.assetID != nil && document.file["coverage"].text != "ready")
          {
            Text("Some text has not been checked for links. The original remains available.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Text(
        "Mentions help you navigate. They do not establish a business relationship. Saved links cover indexed text; embedded file links and unextracted content may be missing."
      )
      .font(.caption).foregroundStyle(.secondary)
    }.padding(20).frame(
      minWidth: 360, idealWidth: 520, maxWidth: 680, minHeight: 400, idealHeight: 560
    )
    .task(id: "\(showingIncoming):\(historical):\(exact):\(state.revision)") {
      if showingIncoming { await incoming.load(query, workbook: workbook) }
    }
    .onDisappear { incoming.cancel() }
  }
  private func canChoose(_ occurrence: ReferenceOccurrence) -> Bool {
    item.category == "source"
      || (occurrence.kind == .body && item.kind == "document" && item.assetID == nil)
  }
}

struct ReferenceTargetPicker: View {
  let item: Item
  let occurrence: ReferenceOccurrence
  let workbook: Workbook
  let revision: Int
  let choose: (ReferenceTarget?, String) async throws -> Void
  @State private var queryText = ""
  @State private var pinned = false
  @State private var working = false
  @State private var failure: String?
  @State private var operation: (key: String, token: String)?
  @StateObject private var search = SearchSession()
  @Environment(\.dismiss) private var dismiss
  private var query: SearchQuery {
    .init(workbook: workbook.url, revision: revision, text: queryText)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Choose a destination").font(.title3)
      Text(occurrence.reference.label).textSelection(.enabled)
      Text("Choose the item this passage refers to. A matching title alone does not create a link.")
        .font(.callout).foregroundStyle(.secondary)
      TextField("Search the workbook", text: $queryText).textFieldStyle(.roundedBorder)
        .accessibilityLabel("Search link destinations")
      Toggle("Keep this exact version", isOn: $pinned)
      Text(
        pinned
          ? "This link will keep the chosen version."
          : "This link will follow the item's latest version."
      )
      .font(.caption).foregroundStyle(.secondary)
      if search.loading || working { ProgressView(working ? "Saving link" : "Searching") }
      List(search.hits) { hit in
        Button {
          save(hit)
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(hit.title).foregroundStyle(.primary)
            Text(hit.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }
        }.buttonStyle(.plain).disabled(working)
          .accessibilityLabel("Link to " + hit.title)
      }
      if let failure = failure ?? search.failure {
        Text(failure).foregroundStyle(.red).textSelection(.enabled)
      }
      HStack {
        if occurrence.reference.resolution == .bound {
          Button("Leave unresolved") { apply(nil, key: "unresolved") }.disabled(working)
        }
        if search.nextCursor != nil {
          Button("More results") { Task { await load(more: true) } }.disabled(
            search.loading || working)
        }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
      }
    }.padding(20).frame(minWidth: 360, idealWidth: 500, minHeight: 400, idealHeight: 540)
      .task(id: query) { await load() }
      .onDisappear { search.cancelRead() }
      .interactiveDismissDisabled(working)
  }
  private func load(more: Bool = false) async {
    let text = query.text
    await search.load(query, more: more, debounce: !more) { cursor, cancel in
      try await Task.detached {
        try workbook.search(text, limit: 20, cursor: cursor, cancellation: cancel)
      }.value
    }
  }
  private func save(_ hit: SearchHit) {
    let mode: ReferenceTargetMode = pinned ? .pinned : .live
    let version = hit.itemID
    let key = version + ":" + mode.rawValue
    if operation?.key != key { operation = (key, identifier()) }
    let token = operation!.token
    working = true
    failure = nil
    Task {
      defer { working = false }
      do {
        let metadata = try await Task.detached { try workbook.citationVersions([version]) }.value
        guard let exact = metadata["versions"].array.first?["cited"],
          exact["id"].string == version, !exact["logicalID"].text.isEmpty
        else { throw SevraError("citation_version", "Choose an existing workbook item.") }
        try await choose(
          .init(mode: mode, identity: mode == .pinned ? version : exact["logicalID"].text), token)
        dismiss()
      } catch { failure = error.localizedDescription }
    }
  }
  private func apply(_ target: ReferenceTarget?, key: String) {
    if operation?.key != key { operation = (key, identifier()) }
    let token = operation!.token
    working = true
    failure = nil
    Task {
      defer { working = false }
      do {
        try await choose(target, token)
        dismiss()
      } catch { failure = error.localizedDescription }
    }
  }
}
