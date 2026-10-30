import SevraCore
import SevraPreviewUI
import SwiftUI

/// Native fields and progressive disclosure, never a serialized JSON dump.
struct StructuredValueView: View {
  let value: Value
  var inspect: (([String]) -> Void)?
  var depth = 0
  @State private var shown = 20
  @State private var textLimit = 2000
  @State private var showNested = false

  var body: some View {
    content(StructuredPresentation.embedded(value))
      .frame(maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
      .textSelection(.enabled)
  }

  @ViewBuilder private func content(_ value: Value) -> some View {
    if depth >= 8 {
      if showNested {
        AnyView(StructuredValueView(value: value, inspect: inspect))
      } else {
        Button("Explore nested content") { showNested = true }
      }
    } else if value["omitted"] == .bool(true), let inspect {
      Button {
        inspect(value["path"].array.compactMap(\.string))
      } label: {
        Label("Explore saved content", systemImage: "arrow.right.circle")
      }.buttonStyle(.link)
      Text(
        "\(value["count"].int ?? 0) \(value["type"] == .string("string") ? "characters" : "entries") saved"
      )
      .font(.caption).foregroundStyle(.secondary)
    } else {
      switch value {
      case .object(let fields):
        let ordinary = fields.keys.filter { !StructuredPresentation.isIdentifier($0) }.sorted()
        let identities = fields.keys.filter { StructuredPresentation.isIdentifier($0) }.sorted()
        VStack(alignment: .leading, spacing: 10) {
          if fields.isEmpty { Text("No fields").foregroundStyle(.secondary) }
          ForEach(Array(ordinary.prefix(shown)), id: \.self) { key in
            field(key, value: fields[key]!)
          }
          if ordinary.count > shown {
            Button("Show \(min(20, ordinary.count - shown)) more fields") { shown += 20 }
          }
          if !identities.isEmpty {
            DisclosureGroup("Identifiers") {
              VStack(alignment: .leading, spacing: 10) {
                ForEach(identities, id: \.self) { field($0, value: fields[$0]!) }
              }.padding(.top, 6)
            }
          }
        }
      case .array(let values):
        VStack(alignment: .leading, spacing: 10) {
          if values.isEmpty { Text("No entries").foregroundStyle(.secondary) }
          ForEach(Array(values.prefix(shown).enumerated()), id: \.offset) { index, child in
            if let scalar = StructuredPresentation.scalar(child),
              StructuredPresentation.embedded(child) == child
            {
              AnyView(
                StructuredValueView(value: .string(scalar), inspect: inspect, depth: depth + 1))
            } else {
              DisclosureGroup("Entry \(index + 1)") {
                AnyView(StructuredValueView(value: child, inspect: inspect, depth: depth + 1))
                  .padding(.top, 6)
              }
            }
          }
          if values.count > shown {
            Button("Show \(min(20, values.count - shown)) more entries") { shown += 20 }
          }
        }
      default:
        let text = StructuredPresentation.scalar(value) ?? "Unavailable"
        VStack(alignment: .leading, spacing: 6) {
          Text(String(text.prefix(textLimit))).fixedSize(horizontal: false, vertical: true)
          if text.count > textLimit {
            Button("Show more text") { textLimit += 4000 }
          }
        }
      }
    }
  }

  @ViewBuilder private func field(_ key: String, value: Value) -> some View {
    let presented = StructuredPresentation.embedded(value)
    if StructuredPresentation.scalar(presented) != nil {
      VStack(alignment: .leading, spacing: 3) {
        Text(StructuredPresentation.label(key)).font(.caption).foregroundStyle(.secondary)
        AnyView(StructuredValueView(value: presented, inspect: inspect, depth: depth + 1))
      }
    } else {
      DisclosureGroup(StructuredPresentation.label(key)) {
        AnyView(StructuredValueView(value: presented, inspect: inspect, depth: depth + 1))
          .padding(.top, 6)
      }
    }
  }
}

/// Prefer the document, result rows or search matches to a diagnostic tree.
struct ActivityResultView: View {
  let value: Value
  let openOriginal: (String) -> Void
  let inspect: ([String]) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let title = value["item"]["title"].string {
        Label(title, systemImage: "doc.text").font(.callout.weight(.medium))
        if let meaning = value["item"]["meaning"].string,
          let status = value["item"]["status"].string
        {
          Text(meaning.capitalized + " · " + status.capitalized)
            .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(value["chunks"].array.enumerated()), id: \.offset) { _, chunk in
          VStack(alignment: .leading, spacing: 6) {
            if let location = chunk["locator"].string {
              Text(location).font(.caption).foregroundStyle(.secondary)
            }
            StructuredValueView(value: chunk["body"])
          }
        }
        if value["chunkPage"]["hasMore"] == .bool(true) {
          Text("This saved read contains part of the document.").foregroundStyle(.secondary)
        }
        if !value["requestEvidence"]["originals"].array.isEmpty {
          DisclosureGroup("Related originals read") {
            ForEach(Array(value["requestEvidence"]["originals"].array.enumerated()), id: \.offset) {
              _, original in
              VStack(alignment: .leading, spacing: 6) {
                Button(original["item"]["title"].text) {
                  openOriginal(original["item"]["id"].text)
                }.buttonStyle(.link)
                Text("Matching excerpt").foregroundStyle(.secondary)
                ForEach(Array(original["chunks"].array.enumerated()), id: \.offset) { _, chunk in
                  StructuredValueView(value: chunk["body"])
                }
              }.padding(.top, 6)
            }
            Text("Selected excerpts, not complete document coverage.").foregroundStyle(.secondary)
          }
        }
        details
      } else if case .array(let rows) = value["rows"], !rows.isEmpty {
        let columns = value["dataset"]["columns"].array
        if !columns.isEmpty {
          ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
              GridRow {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                  Text(column["title"].text).fontWeight(.medium)
                }
              }
              ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                  ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    StructuredValueView(value: row["values"][column["id"].text])
                  }
                }
              }
            }.textSelection(.enabled)
          }
          details
        } else {
          StructuredValueView(value: value, inspect: inspect)
        }
      } else if case .array(let hits) = value["hits"] {
        if hits.isEmpty { Text("No matches on this saved page.").foregroundStyle(.secondary) }
        ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
          VStack(alignment: .leading, spacing: 5) {
            if let title = hit["title"].string, let id = hit["id"].string {
              Button(title) { openOriginal(id) }.buttonStyle(.link)
            } else {
              Text(hit["title"].string ?? "Match").fontWeight(.medium)
            }
            if let snippet = hit["snippet"].string {
              Text(StructuredPresentation.searchExcerpt(snippet, title: hit["title"].text))
                .textSelection(.enabled)
            }
          }
        }
        Text("Matches do not establish complete coverage.").font(.caption).foregroundStyle(
          .secondary)
        details
      } else {
        StructuredValueView(value: value, inspect: inspect)
      }
    }
  }

  private var details: some View {
    DisclosureGroup("All saved fields") {
      StructuredValueView(value: value, inspect: inspect).padding(.top, 6)
    }.font(.caption)
  }
}
