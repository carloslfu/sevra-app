import SevraCore
import SevraPreviewUI
import SevraTableUI
import SwiftUI

/// A compact disclosure in the conversation. The answer and activity have
/// different authority: checked receipts describe execution, not business truth.
struct AgentActivityView: View {
  @ObservedObject var workspace: WorkspaceState
  let activity: RequestActivity?
  let live: LiveRequestActivity?
  /// The answer being written, or just written and not yet loaded as a saved message.
  var preview: String?
  @State private var expanded = false
  /// The run's saved thoughts, read when the finished activity is opened.
  @State private var savedThoughts: [ActivityThought]?
  /// The last thoughts seen while the run lasted, shown until the saved ones are read.
  @State private var lastLiveThoughts: [ActivityThought] = []

  private var title: String {
    if let live { return live.title }
    switch activity?.state {
    case "complete": return "Finished"
    case "needs_input": return "Waiting for your answer"
    case "needs_review": return "Needs your review"
    case "cancelled": return "Stopped"
    case "failed": return "Stopped with an error"
    case "interrupted": return "Interrupted"
    default: return "Unfinished run"
    }
  }
  private var start: Date { live?.started ?? activity?.started ?? Date() }
  private var thoughts: [ActivityThought] {
    if let live { return live.thoughts.isEmpty ? lastLiveThoughts : live.thoughts }
    return savedThoughts ?? lastLiveThoughts
  }
  /// The model's reasoning on the call it is making now.
  private var reasoning: String? { live?.stopping == false ? live?.reasoning : nil }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Button {
          expanded.toggle()
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
              .readingFont(size: 9, weight: .semibold).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
              ActivityShimmer(text: title, active: live != nil && live?.stopping == false)
                .readingFont(.callout)
                .multilineTextAlignment(.leading)
              if !expanded, live?.isReasoning == true, let reasoning {
                // While the model reasons, its latest words show without opening the activity.
                Text(ThoughtText.line(reasoning))
                  .readingFont(.caption).foregroundStyle(.tertiary)
                  .lineLimit(1).truncationMode(.head)
                  .accessibilityIdentifier("activity-thinking-line")
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
          .accessibilityLabel((expanded ? "Hide activity: " : "Show activity: ") + title)
          .accessibilityValue(expanded ? "Expanded" : "Collapsed")
          .help("See what the model thought, and its searches, reads and saved results")
        TimelineView(.animation(minimumInterval: 1, paused: live == nil)) { context in
          let end = live == nil ? activity?.updated ?? start : context.date
          Text(Self.duration(max(0, end.timeIntervalSince(start))))
            .readingFont(.caption).monospacedDigit().foregroundStyle(.secondary)
            .accessibilityLabel(
              "Elapsed time: " + Self.duration(max(0, end.timeIntervalSince(start))))
        }
        if let live {
          Button("Stop", action: workspace.stop).buttonStyle(.plain).readingFont(.caption)
            .disabled(live.stopping).accessibilityLabel("Stop this request")
        }
      }
      if expanded {
        let timeline = RequestActivity.timeline(
          steps: activity?.steps ?? [], thoughts: thoughts)
        VStack(alignment: .leading, spacing: 12) {
          ForEach(timeline) { entry in
            switch entry {
            case .thought(let thought):
              ActivityThoughtView(thought: thought)
            case .step(let step):
              ActivityStepView(
                workspace: workspace, step: step, conversation: activity?.conversation ?? "")
            }
          }
          if let reasoning {
            ActivityThinkingView(text: reasoning, active: live?.isReasoning == true)
          }
          if let activity {
            if activity.hasMoreSteps {
              Text("Showing the first 64 steps. Full results remain in the workbook journal.")
                .readingFont(.caption).foregroundStyle(.secondary)
            }
            if timeline.isEmpty && reasoning == nil {
              Text(live == nil ? "No tool calls were saved." : "No tool calls yet.")
                .readingFont(.caption).foregroundStyle(.secondary)
            }
          }
          // While the model reasons, the thought being written already says what it is doing.
          if let live, !live.isReasoning || reasoning == nil {
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: live.stopping ? "stop.circle" : "ellipsis")
                .frame(width: 14).accessibilityHidden(true)
              Text(live.status).readingFont(.caption).textSelection(.enabled)
            }.foregroundStyle(.secondary)
          }
          if thoughts.contains(where: \.isVisible) || reasoning != nil {
            Text("Thoughts are the model’s working notes. Sevra does not check them against your workbook.")
              .readingFont(.caption).foregroundStyle(.tertiary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }.padding(.leading, 15)
          .overlay(alignment: .leading) { Rectangle().fill(.quaternary).frame(width: 1) }
      }
      if let preview, !preview.isEmpty {
        // Laid out exactly like the saved reply that replaces it, so nothing moves when it lands.
        StreamingAnswerView(text: preview).padding(.top, 14)
      }
    }.accessibilityElement(children: .contain)
      .accessibilityIdentifier("agent-activity-" + (activity?.id ?? "preparing"))
      .onChange(of: live?.thoughts ?? []) { _, value in
        if !value.isEmpty { lastLiveThoughts = value }
      }
      .onAppear { if workspace.activityExpandedByDefault { expanded = true } }
      .task(id: "\(expanded)-\(activity?.id ?? "")-\(activity?.state ?? "")-\(live == nil)") {
        await loadThoughts()
      }
  }

  /// A finished run's thoughts come from the workbook, read only when the activity is open.
  private func loadThoughts() async {
    guard expanded, live == nil, let activity, let book = workspace.workbook else { return }
    let owner = workspace.interactionIdentity
    let run = activity.id
    let chat = activity.conversation
    let loaded = try? await Task.detached(priority: .utility) {
      try book.runThoughts(run, conversation: chat)
    }.value
    guard !Task.isCancelled, workspace.interactionIdentity == owner, workspace.workbook === book
    else { return }
    savedThoughts = loaded ?? []
  }

  static func duration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    return total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
  }
}

/// The answer while it is being written, in the place and shape of the finished Sevra message.
private struct StreamingAnswerView: View {
  let text: String
  var body: some View {
    let content = ConversationMessageContent(text)
    VStack(alignment: .leading, spacing: 6) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(content.blocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .text(let text):
            Text(text).textSelection(.enabled).lineSpacing(4)
          case .table(let table):
            ReadOnlyTableView(content: table, label: "Comparison table", inline: true, open: { _ in })
          case .code(let code):
            ConversationCodeBlock(code: code)
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .contain).accessibilityLabel("Sevra message, writing")
      .accessibilityIdentifier("answer-preview")
  }
}

/// How a thought reads in a line or a block.
enum ThoughtText {
  /// The last words, on one line.
  static func line(_ text: String) -> String {
    String(text.suffix(240)).split(whereSeparator: \.isNewline).joined(separator: " ")
  }
  /// The last part of a thought that is still being written, so the newest words show.
  static func tail(_ text: String, limit: Int = 480) -> String {
    guard text.count > limit else { return text }
    let start = text.index(text.endIndex, offsetBy: -limit)
    let rest = text[start...]
    let word = rest.firstIndex(where: \.isWhitespace).map { rest.index(after: $0) } ?? start
    return "…" + rest[word...]
  }
  static func isLong(_ text: String) -> Bool {
    text.count > 320 || text.filter(\.isNewline).count > 3
  }
}

/// One saved thought, and what Sevra did with the call when it did not become a step.
private struct ActivityThoughtView: View {
  let thought: ActivityThought
  @State private var open = false
  @State private var noteOpen = false
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !thought.text.isEmpty {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "brain").readingFont(.caption).frame(width: 14)
            .foregroundStyle(.secondary).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text("Thought").readingFont(.caption, weight: .medium).foregroundStyle(.secondary)
            Text(thought.text).readingFont(.caption).foregroundStyle(.secondary)
              .lineSpacing(2).lineLimit(open || !ThoughtText.isLong(thought.text) ? nil : 4)
              .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if ThoughtText.isLong(thought.text) {
              Button(open ? "Show less" : "Show more") { open.toggle() }
                .buttonStyle(.link).readingFont(.caption)
                .accessibilityLabel(open ? "Show less of this thought" : "Show all of this thought")
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .contain).accessibilityLabel("Thought")
      }
      if let outcome = thought.outcome {
        HStack(alignment: .top, spacing: 8) {
          Image(systemName: "arrow.uturn.backward.circle").readingFont(.caption).frame(width: 14)
            .foregroundStyle(Color.orange).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text(Self.title(outcome)).readingFont(.caption, weight: .medium)
            if let draft = thought.draft, !draft.isEmpty {
              Text("The model wrote: “\(draft)”").readingFont(.caption)
                .foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(noteOpen || !ThoughtText.isLong(draft) ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let note = thought.note, !note.isEmpty {
              Text("Sevra replied: “\(note)”").readingFont(.caption)
                .foregroundStyle(.secondary).textSelection(.enabled)
                .lineLimit(noteOpen || !ThoughtText.isLong(note) ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            }
            if ThoughtText.isLong(thought.note ?? "") || ThoughtText.isLong(thought.draft ?? "") {
              Button(noteOpen ? "Show less" : "Show more") { noteOpen.toggle() }
                .buttonStyle(.link).readingFont(.caption)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .contain)
      }
    }
  }
  static func title(_ outcome: String) -> String {
    switch outcome {
    case "answer_refused": return "Answer sent back"
    case "too_long": return "Reply ran past the length limit"
    default: return "Reply sent back"
    }
  }
}

/// The thought the model is writing now. The newest words stay in view as it grows. Once
/// the model moves on to its call or answer, the thought stays, finished.
private struct ActivityThinkingView: View {
  let text: String
  let active: Bool
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "brain").readingFont(.caption).frame(width: 14)
        .foregroundStyle(.secondary).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        ActivityShimmer(text: active ? "Thinking" : "Thought", active: active)
          .readingFont(.caption, weight: .medium)
        Text(ThoughtText.tail(text)).readingFont(.caption).foregroundStyle(.secondary)
          .lineSpacing(2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.accessibilityElement(children: .combine)
      .accessibilityIdentifier("activity-thinking")
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
      Image(systemName: icon).readingFont(.caption).frame(width: 14)
        .foregroundStyle(step.state == "failed" ? Color.orange : .secondary)
        .accessibilityLabel(step.state == "prepared" ? "No final receipt" : step.state)
      VStack(alignment: .leading, spacing: 4) {
        Text(step.title).readingFont(.caption, weight: .medium).textSelection(.enabled)
        Text(step.detail).readingFont(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        if step.state == "completed", let id = step.originalID {
          Button("Open original") { workspace.openEvidence(id) }.buttonStyle(.link).readingFont(
            .caption)
        }
        DisclosureGroup("Saved details", isExpanded: $showReceipt) {
          VStack(alignment: .leading, spacing: 6) {
            if let savedInputs {
              DisclosureGroup("Request fields") {
                StructuredValueView(value: savedInputs).padding(.top, 6)
              }
            }
            if loading { ProgressView("Reading saved receipt").controlSize(.small) }
            if let failure { Text(failure).readingFont(.caption).foregroundStyle(.red) }
            if let inspection {
              if !resultPath.isEmpty {
                Button("Back to result") {
                  resultPath = []
                  offset = 0
                }
                Text(resultPath.map(StructuredPresentation.label).joined(separator: " › "))
                  .readingFont(.caption).foregroundStyle(.secondary)
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
                        .readingFont(.caption, weight: .medium)
                        StructuredValueView(value: entry["value"], inspect: explore)
                      }
                    }
                    Text("Showing part of the saved result.").foregroundStyle(.secondary)
                  }
                }.readingFont(.caption).padding(.vertical, 4)
              }.frame(maxHeight: 300).id(resultPath.joined(separator: "/") + String(offset))
              if let next = inspection["nextOffset"].int {
                Button("Next result page") { offset = next }.readingFont(.caption)
              }
              if offset > 0 { Button("First result page") { offset = 0 }.readingFont(.caption) }
            }
          }.padding(.top, 4)
        }.readingFont(.caption).task(id: "\(showReceipt)-\(offset)-\(resultPath)-\(step.state)") {
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
