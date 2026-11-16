import SevraCore
import SwiftUI

/// Compact native inputs embedded in the transcript. Only the workspace host
/// may submit an answer and start the corresponding request.
public struct ConversationInputView: View {
  let input: ConversationSurface.Input
  let surface: ConversationSurface
  let book: Workbook
  let submit: (ConversationInputResponse, Int) -> Void
  @State private var values: [String: Value] = [:]
  @State private var editing = false
  @State private var saved: ConversationInputDraft?
  @State private var persistenceError: String?
  @State private var ready = false
  @State private var saving = false

  public init(
    input: ConversationSurface.Input, surface: ConversationSurface, book: Workbook,
    submit: @escaping (ConversationInputResponse, Int) -> Void
  ) {
    self.input = input
    self.surface = surface
    self.book = book
    self.submit = submit
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !editing {
        ForEach(input.choices) { choice in
          Button(choice.label) { submit(.choice(choice.id), saved?.revision ?? 0) }
            .controlSize(.regular).disabled(saving)
        }
      }
      if editing || input.choices.isEmpty {
        ForEach(input.fields) { field in
          if field.type == .boolean {
            Picker(
              field.label,
              selection: Binding<Bool?>(
                get: {
                  if case .bool(let flag) = values[field.id] { return flag }
                  return nil
                },
                set: { values[field.id] = $0.map(Value.bool) })
            ) {
              Text("Choose").tag(nil as Bool?)
              Text("Yes").tag(true as Bool?)
              Text("No").tag(false as Bool?)
            }
            .pickerStyle(.menu)
          } else {
            VStack(alignment: .leading, spacing: 4) {
              Text(field.label).font(.callout)
              TextField(
                field.type == .date ? "YYYY-MM-DD" : field.label,
                text: Binding(
                  get: { values[field.id]?.text ?? "" },
                  set: { values[field.id] = $0.isEmpty ? nil : .string($0) })
              )
              .textFieldStyle(.roundedBorder)
              .accessibilityLabel(field.label)
            }
          }
        }
      }
      HStack {
        if editing || input.choices.isEmpty {
          Button("Send answer") { submit(.fields(values), saved?.revision ?? 0) }
            .buttonStyle(.borderedProminent)
            .disabled(
              saving || input.fields.contains { $0.required && values[$0.id] == nil }
                || values.isEmpty)
        } else {
          Button("Enter an answer") { editing = true }
        }
        if !values.isEmpty { Button("Clear fields") { values = [:] }.buttonStyle(.link) }
        Button("Cancel question") { submit(.cancel, saved?.revision ?? 0) }.buttonStyle(.link)
          .disabled(saving)
      }
      if let persistenceError {
        Text(persistenceError).font(.callout).foregroundStyle(.secondary)
      }
    }
    .disabled(!ready)
    .task {
      do {
        let draft = try await Task.detached { try book.conversationInputDraft(surface) }.value
        try Task.checkCancellation()
        saved = draft
        values = draft?.values ?? [:]
        editing = !values.isEmpty
        ready = true
      } catch {
        if !Task.isCancelled { persistenceError = error.localizedDescription }
      }
    }
    .onChange(of: values) { _, newValues in
      guard ready, !saving, (saved?.values ?? [:]) != newValues else { return }
      saving = true
      Task {
        defer { saving = false }
        do {
          while (saved?.values ?? [:]) != values {
            let draftValues = values
            let revision = saved?.revision ?? 0
            saved = try await Task.detached {
              try book.saveConversationInputDraft(
                surface, values: draftValues, expectedRevision: revision)
            }.value
          }
          persistenceError = nil
        } catch {
          persistenceError = error.localizedDescription
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(input.purpose)
  }
}
