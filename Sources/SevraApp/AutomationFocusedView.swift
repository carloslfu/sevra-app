import SevraCore
import SwiftUI

/// An exact saved-version handoff from the originating conversation. It opens
/// the same native review controls and never carries an execution capability.
struct AutomationFocusedView: View {
  let definitionID: String
  @ObservedObject var workspace: WorkspaceState
  @State private var definition: ApplicationDefinition?
  @State private var failure: String?
  @State private var presence: Presence?
  var body: some View {
    Group {
      if let presence, presence.gone {
        VStack(alignment: .leading, spacing: 16) {
          GoneBanner(presence: presence, noun: "automation", workspace: workspace)
          Button("All automations") { workspace.navigate(.automations) }
          Spacer(minLength: 0)
        }.padding(24).frame(maxWidth: 760, alignment: .leading)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else if let definition {
        AutomationScheduleDetail(
          definition: definition, workspace: workspace, onClose: { workspace.back() }
        )
        .id(definition.id)
      } else if let failure {
        VStack(alignment: .leading, spacing: 16) {
          Text(failure).textSelection(.enabled)
          Button("All automations") { workspace.navigate(.automations) }
        }.padding(24)
      } else {
        ProgressView("Reading saved automation")
      }
    }
    .task(id: definitionID + ":" + String(workspace.revision)) {
      // Removed from chat or another window while open: say so here too.
      guard let book = workspace.workbook else { return }
      let found = await Task.detached { [definitionID] in try? book.presence(definitionID) }.value
      guard !Task.isCancelled else { return }
      presence = found
    }
    .task(id: workspace.interactionIdentity.uuidString + definitionID) {
      definition = nil
      failure = nil
      guard let book = workspace.workbook else { return }
      do {
        let saved = try await Task.detached { try book.applicationDefinition(definitionID) }.value
        try require(
          saved.id == definitionID && saved.kind == "automation", "automation_binding",
          "Open an exact saved automation version.")
        guard !Task.isCancelled, workspace.workbook === book else { return }
        definition = saved
      } catch {
        guard !Task.isCancelled, workspace.workbook === book else { return }
        failure = error.localizedDescription
      }
    }
  }
}
