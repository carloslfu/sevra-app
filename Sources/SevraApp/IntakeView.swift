import SevraCore
import SwiftUI

struct IntakeChoice: Sendable, Identifiable {
  let job: IntakeJob
  let title: String
  let supportsTable: Bool
  let supportsUpdate: Bool
  var id: String { job.id }
}
struct IntakePrompt: Identifiable {
  let id = UUID()
  var choices: [IntakeChoice]
}
struct IntakeAttempt: Sendable {
  let job: IntakeJob
  let failure: String?
}
struct IntakeView: View {
  @ObservedObject var state: WorkspaceState
  let prompt: IntakePrompt
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Use saved files").font(.title2.weight(.medium))
      Text(
        "Tell Sevra what you need in the conversation, or choose a use below. Your originals stay available."
      )
      .foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          ForEach(prompt.choices) { choice in
            VStack(alignment: .leading, spacing: 10) {
              Text(choice.title).font(.headline)
              DisclosureGroup("File details") {
                Text(choice.job.detail).font(.callout).foregroundStyle(.secondary)
                if let index = choice.job.report["index"]["state"].string {
                  Text("Indexing: " + index + ". " + choice.job.report["index"]["detail"].text)
                    .font(.caption).foregroundStyle(.secondary)
                }
              }
              if let role = choice.job.role {
                Button("Continue selected use") { state.continueIntake(choice, role: role) }
              } else {
                HStack(spacing: 12) {
                  if choice.supportsTable {
                    Button("Create table from saved values") {
                      state.continueIntake(choice, role: .values)
                    }
                  }
                  Menu("Other uses") {
                    Button("Keep as reference") { state.continueIntake(choice, role: .reference) }
                    Button("Inspect for analysis") { state.continueIntake(choice, role: .analysis) }
                    if choice.supportsUpdate {
                      Button("Update a working table…") {
                        state.continueIntake(choice, role: .update)
                      }
                    }
                  }
                }
                if choice.supportsTable {
                  Text(
                    choice.title.lowercased().hasSuffix(".xlsx")
                      ? "Imports saved Excel values. Original formulas are kept as evidence and will not recalculate."
                      : "The first row becomes column headings. Check the resulting table before using it."
                  )
                  .font(.caption).foregroundStyle(.secondary)
                }
              }
            }.disabled(state.busy)
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      if state.busy {
        HStack {
          ProgressView().controlSize(.small)
          Text(state.status)
          Button("Stop", action: state.stop)
        }
      }
      if let error = state.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
      HStack {
        Spacer()
        Button("Done") {
          state.intakePrompt = nil
          state.composerFocusRequest = UUID()
        }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 630, height: 430)
  }
}
