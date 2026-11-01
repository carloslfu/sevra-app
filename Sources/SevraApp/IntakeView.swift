import SevraCore
import SwiftUI

struct IntakeChoice: Sendable, Identifiable {
  /// Nil until a use is chosen, so looking at a saved file and leaving records nothing.
  let job: IntakeJob?
  let sourceID: String
  let title: String
  let supportsTable: Bool
  let supportsUpdate: Bool
  /// The job's ID, also when the job is still to come.
  let id: String
  init(job: IntakeJob, title: String, supportsTable: Bool, supportsUpdate: Bool) {
    self.job = job
    sourceID = job.sourceID
    self.title = title
    self.supportsTable = supportsTable
    self.supportsUpdate = supportsUpdate
    id = job.id
  }
  init(sourceID: String, title: String, supportsTable: Bool, supportsUpdate: Bool) {
    job = nil
    self.sourceID = sourceID
    self.title = title
    self.supportsTable = supportsTable
    self.supportsUpdate = supportsUpdate
    id = UUID().uuidString
  }
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
              if let job = choice.job {
                DisclosureGroup("File details") {
                  Text(job.detail).font(.callout).foregroundStyle(.secondary)
                  if let index = job.report["index"]["state"].string {
                    Text("Indexing: " + index + ". " + job.report["index"]["detail"].text)
                      .font(.caption).foregroundStyle(.secondary)
                  }
                }
              }
              if let role = choice.job?.role {
                Button("Continue selected use") { state.continueIntake(choice, role: role) }
              } else {
                HStack(spacing: 12) {
                  if choice.supportsTable {
                    Button("Create table from saved values") {
                      state.continueIntake(choice, role: .values)
                    }
                  } else {
                    Button("Inspect for analysis") {
                      state.continueIntake(choice, role: .analysis)
                    }
                  }
                  if choice.supportsTable {
                    Menu("Other uses") {
                      Button("Keep as reference") { state.continueIntake(choice, role: .reference) }
                      Button("Inspect for analysis") {
                        state.continueIntake(choice, role: .analysis)
                      }
                      if choice.supportsUpdate {
                        Button("Update a working table…") {
                          state.continueIntake(choice, role: .update)
                        }
                      }
                    }
                  } else {
                    Button("Keep as reference") { state.continueIntake(choice, role: .reference) }
                  }
                }
                if choice.supportsTable {
                  Text(
                    choice.title.lowercased().hasSuffix(".xlsx")
                      ? "Imports saved Excel values. Simple formulas recalculate after edits. Others keep their saved value and say so."
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
    }.padding(24).frame(width: 630, height: prompt.choices.count == 1 ? 360 : 430)
  }
}
