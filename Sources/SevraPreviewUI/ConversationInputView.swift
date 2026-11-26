import SevraCore
import SwiftUI

/// The one-tap answers of a question in the transcript. Typed answers go through the chat
/// composer, which replies to the open question, so this view never shows a text field.
/// Only the workspace host may submit an answer and start the corresponding request.
public struct ConversationInputView: View {
  let input: ConversationSurface.Input
  let surface: ConversationSurface
  let book: Workbook
  let submit: (ConversationInputResponse, Int) -> Void
  @State private var revision = 0

  public init(
    input: ConversationSurface.Input, surface: ConversationSurface, book: Workbook,
    submit: @escaping (ConversationInputResponse, Int) -> Void
  ) {
    self.input = input
    self.surface = surface
    self.book = book
    self.submit = submit
  }

  /// The buttons that answer the question in one tap: the model's choices, or the options of
  /// a single yes-or-no or record field. Empty when the answer has to be typed.
  public static func options(_ input: ConversationSurface.Input) -> [(
    label: String, response: ConversationInputResponse
  )] {
    if !input.choices.isEmpty {
      return input.choices.map { ($0.label, .choice($0.id)) }
    }
    guard input.fields.count == 1, let field = input.fields.first else { return [] }
    if field.type == .boolean {
      return [("Yes", .fields([field.id: .bool(true)])), ("No", .fields([field.id: .bool(false)]))]
    }
    if let records = field.records {
      return records.rowIDs.map { (records.labels?[$0] ?? $0, .fields([field.id: .string($0)])) }
    }
    return []
  }

  public var body: some View {
    let options = Self.options(input)
    VStack(alignment: .leading, spacing: 8) {
      if !options.isEmpty {
        FlowButtons(count: options.count) { index in
          Button(options[index].label) { submit(options[index].response, revision) }
            .controlSize(.regular)
        }
      }
      HStack(spacing: 12) {
        Text(options.isEmpty ? "Reply in the message box." : "Or reply in the message box.")
          .font(.caption).foregroundStyle(.secondary)
        Button("Skip") { submit(.decline, revision) }.buttonStyle(.link).font(.caption)
          .help("Sevra goes on without it and does not make it up")
        Button("Cancel question") { submit(.cancel, revision) }.buttonStyle(.link).font(.caption)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(input.purpose)
    .task(id: surface.id) {
      // A question answered by an earlier build may carry saved fields. Answer against them
      // so the saved revision does not block a tap.
      let draft = try? await Task.detached { try book.conversationInputDraft(surface) }.value
      revision = draft?.revision ?? 0
    }
  }
}

/// Buttons that wrap onto more lines when the row is narrow.
private struct FlowButtons<Content: View>: View {
  let count: Int
  @ViewBuilder let content: (Int) -> Content
  var body: some View {
    FlowLayout(spacing: 8) {
      ForEach(0..<count, id: \.self) { content($0) }
    }
  }
}

private struct FlowLayout: Layout {
  var spacing: CGFloat
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    var y = bounds.minY
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }
  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }
  private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
    var rows: [Row] = [Row()]
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
      if rows[rows.count - 1].width + needed > width, !rows[rows.count - 1].indices.isEmpty {
        rows.append(Row())
      }
      let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
      rows[rows.count - 1].indices.append(index)
      rows[rows.count - 1].width += added
      rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
    }
    return rows.filter { !$0.indices.isEmpty }
  }
}
