import SevraCore
import SwiftUI

struct IntakeChoice: Sendable, Identifiable {
  let job: IntakeJob
  let title: String
  let supportsTable: Bool
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
      Text("How would you like to use this?").font(.title2)
      Text(
        "Your originals are saved in this workbook. You can choose a use now or return to it from Home."
      )
      .foregroundStyle(.secondary)
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          ForEach(prompt.choices) { choice in
            VStack(alignment: .leading, spacing: 10) {
              Text(choice.title).font(.headline)
              Text(choice.job.detail).font(.callout).foregroundStyle(.secondary)
              if let index = choice.job.report["index"]["state"].string {
                Text("Indexing: " + index + ". " + choice.job.report["index"]["detail"].text)
                  .font(.caption).foregroundStyle(.secondary)
              }
              if let role = choice.job.role {
                Button("Continue selected use") { state.continueIntake(choice, role: role) }
              } else {
                HStack {
                  Button("Keep as reference") { state.continueIntake(choice, role: .reference) }
                  Button("Use for analysis") { state.continueIntake(choice, role: .analysis) }
                  if choice.supportsTable {
                    Button("Create tables from values") {
                      state.continueIntake(choice, role: .values)
                    }
                  }
                }
                if choice.supportsTable {
                  Text(
                    "CSV/TSV: first row becomes headings. Excel: saved values only; formulas will not recalculate. The original stays available."
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
        Button("Decide later") { state.intakePrompt = nil }.keyboardShortcut(.cancelAction)
      }
    }.padding(24).frame(width: 630, height: 430)
  }
}
