import SevraPreviewUI
import SwiftUI

struct CapturedRequestContextView: View {
  let context: String
  @ObservedObject var state: WorkspaceState
  var body: some View {
    let captured = RequestContextPresentation(context)
    VStack(alignment: .leading, spacing: 8) {
      Text("Context when requested").font(.caption).foregroundStyle(.secondary)
      if let kind = captured.location, let id = captured.id, let title = captured.title {
        HStack {
          Text(kind.rawValue).foregroundStyle(.secondary)
          Button(title) {
            switch kind {
            case .space: state.navigate(.space(id))
            case .item: state.navigate(.item(id))
            case .table: state.navigate(.table(id))
            }
          }.buttonStyle(.link)
        }
        if let selection = captured.selection {
          Text("Selected text").font(.caption).foregroundStyle(.secondary)
          Text(selection).textSelection(.enabled)
        }
        DisclosureGroup("Original context") {
          Text(captured.original).textSelection(.enabled).font(.caption)
        }
      } else {
        Text(captured.original).textSelection(.enabled)
      }
    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
  }
}
