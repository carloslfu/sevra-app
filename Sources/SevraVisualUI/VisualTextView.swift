import SevraCore
import SwiftUI

public struct VisualTextView: View {
  let definition: VisualText
  let openOriginal: ((String) -> Void)?

  public init(definition: VisualText, openOriginal: ((String) -> Void)? = nil) {
    self.definition = definition
    self.openOriginal = openOriginal
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(definition.title).font(.headline).accessibilityAddTraits(.isHeader)
      ForEach(Array(definition.blocks.enumerated()), id: \.offset) { _, block in
        switch block.kind {
        case .paragraph: content(block)
        case .bullet:
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").accessibilityHidden(true)
            content(block)
          }
        case .callout:
          content(block).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
      }
    }
  }

  private func content(_ block: VisualText.Block) -> some View {
    var formatted = AttributedString()
    for (index, run) in block.runs.enumerated() {
      var part = AttributedString(run.text)
      if run.strong == true { part.inlinePresentationIntent = .stronglyEmphasized }
      if run.sourceID != nil && openOriginal != nil {
        part.link = URL(string: "sevra-source://text/" + String(index))
      }
      formatted.append(part)
    }
    return Text(formatted).font(.callout).textSelection(.enabled)
      .environment(
        \.openURL,
        OpenURLAction { url in
          guard url.scheme == "sevra-source", url.host == "text",
            let index = Int(url.lastPathComponent), block.runs.indices.contains(index),
            let id = block.runs[index].sourceID
          else { return .discarded }
          openOriginal?(id)
          return .handled
        })
  }
}
