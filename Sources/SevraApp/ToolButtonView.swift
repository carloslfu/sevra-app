import SevraCore
import SevraTableUI
import SwiftUI

/// A view's button: it runs one saved tool. Inputs the button does not set itself appear as
/// fields beside it, and the values it does set are shown under it. After a press that changed
/// something, Undo takes that press back. A tool that returns rows shows them under the button.
struct ToolButtonView: View {
  let component: Component
  @ObservedObject var state: WorkspaceState
  let owner: Space?
  @State private var tool: Workbook.SavedTool?
  @State private var loaded = false
  @State private var text: [String: String] = [:]
  @State private var flags: [String: Bool] = [:]
  @State private var lastUndo: String?
  /// This button's own press or Undo is running. Only this button shows it.
  @State private var pressing = false
  /// A press that lasts a moment shows nothing; a slow one shows a spinner after a beat.
  @State private var slow = false
  /// Whether the press Undo takes back also ran a script's actions, which Undo does not cover.
  @State private var undoLeavesActions = false
  @State private var output: Value?
  @State private var failure: String?

  private var button: ViewButton? { try? ViewButton(component) }
  /// What the button is: its tool and the values it sets. A change to either is a new button.
  private var identity: String {
    component.id + "\n" + ((try? component.definitionBinding?.json()) ?? "") + "\n"
      + ((try? component.arguments?.json()) ?? "")
  }
  private var open: [(name: String, type: String, required: Bool)] {
    guard let button, let tool else { return [] }
    return button.open(tool)
  }
  // A required input needs a value. An optional one left empty runs as NULL.
  private var missing: Bool {
    open.contains { $0.required && $0.type != "boolean" && filled($0.name).isEmpty }
  }
  private var canPress: Bool {
    owner != nil && tool?.enabled == true && !missing && !state.busy
  }
  private func filled(_ name: String) -> String {
    (text[name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }
  private func label(_ name: String) -> String {
    let words = name.replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
  }
  private func prompt(_ type: String, required: Bool) -> String {
    let shape = type == "decimal" ? "Number" : type == "date" ? "YYYY-MM-DD" : ""
    return required ? shape : shape.isEmpty ? "Optional" : shape + ", optional"
  }
  private var controlSize: ControlSize {
    component.size == "large" ? .extraLarge : component.size == "small" ? .regular : .large
  }
  /// The values the button sets itself, so the person sees what a press will use.
  private var fixedSummary: String? {
    guard let button, !button.fixed.isEmpty else { return nil }
    return "Uses "
      + button.fixed.keys.sorted().map { label($0) + ": " + button.fixed[$0]!.text }
      .joined(separator: ", ") + "."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(open, id: \.name) { input in
        if input.type == "boolean" {
          Toggle(
            label(input.name),
            isOn: Binding(get: { flags[input.name] ?? false }, set: { flags[input.name] = $0 }))
        } else {
          LabeledContent(label(input.name)) {
            TextField(
              label(input.name),
              text: Binding(get: { text[input.name] ?? "" }, set: { text[input.name] = $0 }),
              prompt: Text(prompt(input.type, required: input.required))
            )
            .labelsHidden().textFieldStyle(.roundedBorder).frame(maxWidth: 320)
            .onSubmit { if canPress { press() } }
          }
        }
      }
      HStack(spacing: 12) {
        Button(component.title, action: press)
          .buttonStyle(.borderedProminent).controlSize(controlSize)
          .disabled(!canPress)
        if let lastUndo {
          Button("Undo") { undo(lastUndo) }
            .disabled(state.busy).accessibilityLabel("Undo " + component.title)
        }
        if slow {
          ProgressView().controlSize(.small).accessibilityLabel("Running " + component.title)
        }
      }.task(id: pressing) {
        guard pressing else { return slow = false }
        try? await Task.sleep(for: .milliseconds(400))
        if !Task.isCancelled { slow = pressing }
      }
      // What a press does: the tool's own description and the values the button sets.
      if let about = [tool?.description, fixedSummary].compactMap({ $0 }).filter({ !$0.isEmpty })
        .joined(separator: " ") as String?, !about.isEmpty
      {
        Text(about).readingFont(.caption).foregroundStyle(.secondary)
          .help(
            tool.map { $0.language == "javascript" ? $0.source : $0.statements.joined(separator: "\n") }
              ?? "")
      }
      if loaded, let button {
        if tool == nil {
          Text("This button runs the tool \(button.tool), which is not in this workbook.")
            .readingFont(.callout).foregroundStyle(.secondary)
        } else if tool?.enabled == false {
          HStack(spacing: 8) {
            Text("The tool \(button.tool) came with this workbook. Enable it to use this button.")
              .readingFont(.callout).foregroundStyle(.secondary)
            Button("Open Tools") { state.navigate(.tools) }
          }
        }
      } else if loaded {
        Text("This button names no saved tool.").readingFont(.callout).foregroundStyle(.secondary)
      }
      if let output { ToolOutputView(result: output) }
      if let failure { Text(failure).readingFont(.callout).foregroundStyle(.red) }
    }
    .task(id: identity + String(state.revision)) {
      guard let book = state.workbook, let name = button?.tool else {
        loaded = true
        return
      }
      tool = try? await Task.detached { try book.savedTools().first { $0.name == name } }.value
      loaded = true
    }
    .onChange(of: identity) {
      text = [:]
      flags = [:]
      lastUndo = nil
      undoLeavesActions = false
      output = nil
      failure = nil
    }
  }

  private func values() -> [String: Value] {
    var values: [String: Value] = [:]
    for input in open {
      if input.type == "boolean" {
        values[input.name] = .bool(flags[input.name] ?? false)
      } else if !filled(input.name).isEmpty {
        values[input.name] = .string(filled(input.name))
      }
    }
    return values
  }

  private func press() {
    guard canPress, !pressing, let owner, let (book, operation) = state.beginQuietOperation()
    else { return }
    pressing = true
    let spaceID = owner.id
    let componentID = component.id
    let submitted = values()
    Task {
      var status: String?
      defer {
        pressing = false
        state.finishQuietOperation(operation, in: book, status: status)
      }
      do {
        let cancellation = operation.cancellation
        let result = try await Task.detached {
          try book.pressButton(
            spaceID: spaceID, componentID: componentID, values: submitted,
            cancellation: cancellation, actor: .human("Sevra view button"))
        }.value
        // A press that changed nothing leaves the earlier one to Undo.
        if let undo = result["undo"].string {
          lastUndo = undo
          undoLeavesActions = !result["actions"].array.isEmpty
        }
        output = result
        // Clear what was used, and keep anything typed while the press ran.
        for (name, value) in submitted where filled(name) == value.text { text[name] = nil }
        if let problem = Workbook.runProblem(result) {
          failure = problem
          state.report(SevraError("tool", problem), for: operation, in: book)
        } else {
          failure = nil
          status = Workbook.describeRun(result)
        }
      } catch {
        failure = failureDescription(error)
        state.report(error, for: operation, in: book)
      }
    }
  }

  private func undo(_ token: String) {
    guard !pressing, let (book, operation) = state.beginQuietOperation() else { return }
    pressing = true
    Task {
      var status: String?
      defer {
        pressing = false
        state.finishQuietOperation(operation, in: book, status: status)
      }
      do {
        let cancellation = operation.cancellation
        _ = try await Task.detached {
          try book.undoButtonPress(
            token, cancellation: cancellation, actor: .human("Sevra view button"))
        }.value
        status =
          undoLeavesActions
          ? "Table changes undone. The script's other actions are not undone." : "Change undone."
        lastUndo = nil
        output = nil
        failure = nil
      } catch {
        failure = failureDescription(error)
        state.report(error, for: operation, in: book)
      }
    }
  }
}

/// What a tool returned: the rows of its last query, or a script's value.
private struct ToolOutputView: View {
  let result: Value
  var body: some View {
    if let table = result["results"].array.last(where: { $0["columns"] != .null }) {
      let columns = table["columns"].array.map(\.text)
      let rows = table["rows"].array.prefix(20)
      VStack(alignment: .leading, spacing: 4) {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
          GridRow {
            ForEach(columns.indices, id: \.self) { index in
              Text(columns[index]).readingFont(.caption, weight: .semibold)
            }
          }
          ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            GridRow {
              ForEach(columns.indices, id: \.self) { index in
                Text(row.array.indices.contains(index) ? row.array[index].text : "")
                  .textSelection(.enabled)
              }
            }
          }
        }
        let total = table["rowCount"].int ?? rows.count
        if total == 0 {
          Text("No rows.").readingFont(.caption).foregroundStyle(.secondary)
        } else if total > rows.count {
          Text("Showing \(rows.count) of \(total) rows.").readingFont(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } else if result["value"] != .null, let text = try? result["value"].json() {
      Text(text.count > 600 ? String(text.prefix(600)) + "…" : text)
        .readingFont(.callout).textSelection(.enabled)
    }
  }
}
