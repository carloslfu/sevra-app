import SevraCore
import SwiftUI

/// The workbook's saved tools. Chat makes and changes them. Here the person sees what each one
/// runs, enables a tool that arrived with a copied workbook, turns one off on this Mac, or
/// removes it from the workbook (P5 of the general chat tools plan).
struct ToolsView: View {
  @ObservedObject var workspace: WorkspaceState
  @State private var tools: [Workbook.SavedTool] = []
  @State private var loaded = false
  @State private var failure: String?
  @State private var removing: Workbook.SavedTool?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        "Tools this workbook keeps, made in chat. A tool runs on this Mac only once it is enabled here. One that came with a copied workbook waits until you enable it."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      if let failure { Text(failure).foregroundStyle(.red) }
      if !loaded {
        ProgressView("Reading tools")
      } else if tools.isEmpty {
        ContentUnavailableView(
          "No saved tools", systemImage: "wrench.and.screwdriver",
          description: Text(
            "Ask in chat to save one, such as a report or a check you want to run again."))
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(tools, id: \.definitionID) { tool in
              ToolRow(
                tool: tool,
                enable: { change(tool) { try $0.enableTool(tool.definitionID) } },
                disable: { change(tool) { try $0.disableTool(tool.definitionID) } },
                remove: { removing = tool })
            }
          }
          .padding(.vertical, 4)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(maxWidth: 760, alignment: .leading)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task { await load() }
    .confirmationDialog(
      "Remove “\(removing?.name ?? "")” from this workbook?", isPresented: .init(
        get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove tool", role: .destructive) {
        if let tool = removing {
          change(tool) {
            _ = try $0.remove(tool.definitionID, actor: .human("SevraApp.tools"))
          }
        }
        removing = nil
      }
      Button("Cancel", role: .cancel) { removing = nil }
    } message: {
      Text(
        "It stops running everywhere this workbook is used. Removed in the workbook menu lists it, and Restore brings it back."
      )
    }
  }

  private func load() async {
    guard let book = workspace.workbook else { return }
    do {
      tools = try await Task.detached { try book.savedTools() }.value
      failure = nil
    } catch {
      failure = error.localizedDescription
    }
    loaded = true
  }

  private func change(
    _ tool: Workbook.SavedTool, _ operation: @escaping @Sendable (Workbook) throws -> Void
  ) {
    guard let book = workspace.workbook else { return }
    Task {
      do {
        try await Task.detached { try operation(book) }.value
        await load()
      } catch {
        failure = error.localizedDescription
      }
    }
  }
}

private struct ToolRow: View {
  let tool: Workbook.SavedTool
  let enable: () -> Void
  let disable: () -> Void
  let remove: () -> Void
  @State private var showsBody = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(tool.name).font(.headline).accessibilityAddTraits(.isHeader)
        Text(tool.language == "javascript" ? "Script" : "SQL")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Label(
          tool.enabled ? "Enabled on this Mac" : "Not enabled on this Mac",
          systemImage: tool.enabled ? "checkmark.circle" : "pause.circle"
        )
        .font(.callout)
        .foregroundStyle(tool.enabled ? Color.secondary : Color.orange)
      }
      if !tool.description.isEmpty {
        Text(tool.description).fixedSize(horizontal: false, vertical: true)
      }
      Text(
        tool.inputs.isEmpty
          ? "No inputs"
          : "Inputs: " + tool.inputs.map { $0.name + " (" + typeName($0.type) + ")" }
            .joined(separator: ", ")
      )
      .font(.callout).foregroundStyle(.secondary)
      DisclosureGroup("What it runs", isExpanded: $showsBody) {
        Text(tool.language == "javascript" ? tool.source : tool.statements.joined(separator: ";\n"))
          .font(.system(.callout, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
      }
      .font(.callout)
      HStack {
        if tool.enabled {
          Button("Turn off on this Mac", action: disable)
        } else {
          Button("Enable on this Mac", action: enable).buttonStyle(.borderedProminent)
        }
        Button("Remove…", role: .destructive, action: remove)
      }
      .controlSize(.small)
    }
    .padding(14)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
  }

  private func typeName(_ type: String) -> String {
    switch type {
    case "decimal": return "number"
    case "boolean": return "yes or no"
    default: return type
    }
  }
}
