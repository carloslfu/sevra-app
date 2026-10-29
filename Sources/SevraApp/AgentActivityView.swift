import SevraCore
import SevraPreviewUI
import SwiftUI

/// A compact disclosure in the conversation. The answer and activity have
/// different authority: checked receipts describe execution, not business truth.
struct AgentActivityView: View {
  @ObservedObject var workspace: WorkspaceState
  let activity: RequestActivity?
  let live: LiveRequestActivity?
  @State private var expanded = false

  private var title: String {
    if let live { return live.title }
    switch activity?.state {
    case "complete": return "Finished"
    case "needs_review": return "Needs your review"
    case "cancelled": return "Stopped"
    case "failed": return "Stopped with an error"
    case "continued": return "Continued in a thread"
    case "interrupted": return "Interrupted"
    default: return "Unfinished run"
    }
  }
  private var start: Date { live?.started ?? activity?.started ?? Date() }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Button {
          expanded.toggle()
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
              .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            ActivityShimmer(text: title, active: live != nil && live?.stopping == false)
              .font(.callout)
              .multilineTextAlignment(.leading)
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
          .accessibilityLabel((expanded ? "Hide activity: " : "Show activity: ") + title)
          .accessibilityValue(expanded ? "Expanded" : "Collapsed")
          .help("Inspect the actual searches, reads and saved results")
        TimelineView(.animation(minimumInterval: 1, paused: live == nil)) { context in
          let end = live == nil ? activity?.updated ?? start : context.date
          Text(Self.duration(max(0, end.timeIntervalSince(start))))
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            .accessibilityLabel(
              "Elapsed time: " + Self.duration(max(0, end.timeIntervalSince(start))))
        }
        if let live {
          Button("Stop", action: workspace.stop).buttonStyle(.plain).font(.caption)
            .disabled(live.stopping).accessibilityLabel("Stop this request")
        }
      }
      if expanded {
        VStack(alignment: .leading, spacing: 12) {
          if let activity {
            ForEach(activity.steps) { step in
              ActivityStepView(
                workspace: workspace, step: step, conversation: activity.conversation)
            }
            if activity.hasMoreSteps {
              Text("Showing the first 64 steps. Full results remain in the workbook journal.")
                .font(.caption).foregroundStyle(.secondary)
            }
            if activity.steps.isEmpty {
              Text(live == nil ? "No tool calls were saved." : "No tool calls yet.")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          if let live {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: live.stopping ? "stop.circle" : "ellipsis")
                .frame(width: 14).accessibilityHidden(true)
              Text(live.status).font(.caption).textSelection(.enabled)
            }.foregroundStyle(.secondary)
          }
          if let model = activity?.model {
            DisclosureGroup("Model details") {
              Text(model).font(.caption).textSelection(.enabled)
              Text("Tool results describe saved execution. Search coverage may be partial.")
                .font(.caption).foregroundStyle(.secondary)
            }.font(.caption)
          }
        }.padding(.leading, 15)
          .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 1) }
      }
    }.accessibilityElement(children: .contain)
      .accessibilityIdentifier("agent-activity-" + (activity?.id ?? "preparing"))
  }

  static func duration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    return total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
  }
}

private struct ActivityStepView: View {
  @ObservedObject var workspace: WorkspaceState
  let step: ToolActivity
  let conversation: String
  @State private var inspection: Value?
  @State private var savedInputs: Value?
  @State private var failure: String?
  @State private var loading = false
  @State private var showReceipt = false
  @State private var offset = 0
  @State private var resultPath: [String] = []
  private var icon: String {
    step.state == "completed"
      ? "checkmark" : step.state == "failed" ? "exclamationmark.circle" : "circle.dotted"
  }
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon).font(.caption).frame(width: 14)
        .foregroundStyle(step.state == "failed" ? Color.orange : .secondary)
        .accessibilityLabel(step.state == "prepared" ? "No final receipt" : step.state)
      VStack(alignment: .leading, spacing: 4) {
        Text(step.title).font(.caption.weight(.medium)).textSelection(.enabled)
        Text(step.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        if step.state == "completed", let id = step.originalID {
          Button("Open original") { workspace.openEvidence(id) }.buttonStyle(.link).font(.caption)
        }
        DisclosureGroup("Saved details", isExpanded: $showReceipt) {
          VStack(alignment: .leading, spacing: 6) {
            if let savedInputs {
              DisclosureGroup("Request fields") {
                StructuredValueView(value: savedInputs).padding(.top, 6)
              }
            }
            if loading { ProgressView("Reading saved receipt").controlSize(.small) }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            if let inspection {
              if !resultPath.isEmpty {
                Button("Back to result") {
                  resultPath = []
                  offset = 0
                }
                Text(resultPath.map(StructuredPresentation.label).joined(separator: " › "))
                  .font(.caption).foregroundStyle(.secondary)
              }
              ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                  if step.state == "prepared" {
                    StructuredValueView(value: inspection)
                  } else if inspection["complete"] == .bool(true) {
                    ActivityResultView(
                      value: inspection["value"], openOriginal: { workspace.openEvidence($0) },
                      inspect: explore)
                  } else if let segment = inspection["textSegment"].string {
                    StructuredValueView(value: .string(segment))
                    Text("Showing part of the saved text.").foregroundStyle(.secondary)
                  } else {
                    ForEach(Array(inspection["entries"].array.enumerated()), id: \.offset) {
                      _, entry in
                      VStack(alignment: .leading, spacing: 4) {
                        Text(
                          entry["key"].string.map(StructuredPresentation.label)
                            ?? "Entry \((entry["index"].int ?? 0) + 1)"
                        )
                        .font(.caption.weight(.medium))
                        StructuredValueView(value: entry["value"], inspect: explore)
                      }
                    }
                    Text("Showing part of the saved result.").foregroundStyle(.secondary)
                  }
                }.font(.caption).padding(.vertical, 4)
              }.frame(maxHeight: 300).id(resultPath.joined(separator: "/") + String(offset))
              if let next = inspection["nextOffset"].int {
                Button("Next result page") { offset = next }.font(.caption)
              }
              if offset > 0 { Button("First result page") { offset = 0 }.font(.caption) }
            }
          }.padding(.top, 4)
        }.font(.caption).task(id: "\(showReceipt)-\(offset)-\(resultPath)-\(step.state)") {
          guard showReceipt, let book = workspace.workbook else { return }
          let owner = workspace.interactionIdentity
          let requestedOffset = offset
          let requestedPath = resultPath
          let cancellation = Cancellation()
          loading = true
          inspection = nil
          failure = nil
          defer { loading = false }
          do {
            let (inputs, value) = try await withTaskCancellationHandler {
              try await Task.detached(priority: .utility) {
                try cancellation.check()
                let call = try book.toolCall(step.id, conversation: conversation)
                if step.state == "prepared" {
                  return (call["arguments"], call)
                }
                let result = try book.toolResultPage(
                  step.id, conversation: conversation, path: requestedPath, offset: requestedOffset,
                  cancellation: cancellation)
                return (call["arguments"], result)
              }.value
            } onCancel: {
              cancellation.cancel()
            }
            guard !Task.isCancelled, workspace.interactionActive,
              workspace.interactionIdentity == owner, workspace.workbook === book,
              workspace.conversation == conversation
            else { return }
            inspection = value
            savedInputs = inputs
            failure = nil
          } catch {
            guard !Task.isCancelled, workspace.interactionIdentity == owner else { return }
            failure = error.localizedDescription
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func explore(_ path: [String]) {
    resultPath = path
    offset = 0
  }
}

/// Animate only the glyph highlight, keeping layout and VoiceOver text stable.
/// A static, fully legible label remains with Reduce Motion or increased contrast.
private struct ActivityShimmer: View {
  let text: String
  let active: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    Text(text).foregroundStyle(.secondary)
      .overlay {
        if active && !reduceMotion && contrast != .increased && scenePhase == .active {
          TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let phase =
              context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
            Text(text).foregroundStyle(.primary).mask {
              GeometryReader { geometry in
                LinearGradient(
                  colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing
                )
                .frame(width: max(40, geometry.size.width * 0.4))
                .offset(x: geometry.size.width * (phase * 1.8 - 0.4))
              }
            }
          }.accessibilityHidden(true).allowsHitTesting(false)
        }
      }
  }
}
