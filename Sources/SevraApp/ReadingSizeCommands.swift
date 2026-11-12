import SevraTableUI
import SwiftUI

struct ReadingSizeCommands: View {
  @AppStorage(ReadingStyle.preference) private var scale = 1.0
  private var current: Double { Double(ReadingStyle.scale(scale)) }
  var body: some View {
    Button("Larger text") { scale = min(2, current + 0.25) }
      .keyboardShortcut("+", modifiers: .command).disabled(current >= 2)
    Button("Smaller text") { scale = max(1, current - 0.25) }
      .keyboardShortcut("-", modifiers: .command).disabled(current <= 1)
    Button("Standard text size") { scale = 1 }.disabled(current == 1)
  }
}

struct ReadingWorkspaceCommands: View {
  @ObservedObject var state: WorkspaceState
  var body: some View {
    Button("Focus conversation") { state.requestReadingFocus(.conversation) }
      .keyboardShortcut("1", modifiers: [.command, .option])
    Button("Focus workspace") { state.requestReadingFocus(.workspace) }
      .keyboardShortcut("2", modifiers: [.command, .option])
    Button("Read last status") { state.requestReadingFocus(.status) }
      .keyboardShortcut("0", modifiers: [.command, .option])
      .disabled(state.error == nil && state.terminalStatus == nil)
  }
}
