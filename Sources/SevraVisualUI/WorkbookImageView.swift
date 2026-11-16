import AppKit
import SevraCore
import SevraMedia
import SwiftUI

/// Shows an exact included image with proportional fit and separate original
/// navigation. The captured source stays the same across chat history reads.
public struct WorkbookImageView: View {
  let book: Workbook
  let presentation: ImagePresentation
  let openOriginal: () -> Void
  @State private var preview: PreviewImage?
  @State private var error: String?
  @State private var expanded = false
  @State private var retry = 0

  public init(book: Workbook, presentation: ImagePresentation, openOriginal: @escaping () -> Void) {
    self.book = book
    self.presentation = presentation
    self.openOriginal = openOriginal
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.45))
        if let preview {
          Button {
            expanded = true
          } label: {
            Image(decorative: preview.image, scale: 1)
              .resizable().scaledToFit()
              .accessibilityLabel(presentation.accessibilityDescription)
          }.buttonStyle(.plain).help("Enlarge image")
        } else if let error {
          VStack(spacing: 8) {
            Label(error, systemImage: "photo.badge.exclamationmark")
              .font(.callout).foregroundStyle(.secondary)
            Button("Retry image") { retry &+= 1 }
          }.padding(12)
        } else {
          ProgressView().controlSize(.small).accessibilityLabel("Loading image")
        }
      }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8))
      if !presentation.caption.isEmpty {
        Text(presentation.caption).font(.callout).textSelection(.enabled)
      }
      Button("Open original", action: openOriginal).buttonStyle(.link).font(.callout)
    }
    .task(id: presentation.reference.assetID + "/" + String(retry)) {
      preview = nil
      error = nil
      expanded = false
      do {
        let image = try await load(enlarged: false)
        try Task.checkCancellation()
        preview = image
      } catch {
        guard !Task.isCancelled else { return }
        self.error = error.localizedDescription
      }
    }
    .sheet(isPresented: $expanded) {
      ExpandedWorkbookImage(
        title: presentation.accessibilityDescription,
        load: { try await load(enlarged: true) })
    }
  }

  private func load(enlarged: Bool) async throws -> PreviewImage {
    let read = try await Task.detached { try book.imageAssetRead(presentation.reference) }.value
    return try await WorkbookImageDecoder.shared.load(read, enlarged: enlarged)
  }
}

private struct ExpandedWorkbookImage: View {
  let title: String
  let load: () async throws -> PreviewImage
  @Environment(\.dismiss) private var dismiss
  @State private var image: PreviewImage?
  @State private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(title).font(.headline).lineLimit(1)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }.padding(16)
      Divider()
      if let image {
        ImageViewer(
          image: NSImage(cgImage: image.image, size: image.points), title: title, fitInitially: true
        )
      } else if let error {
        Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ProgressView("Opening image…").frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minWidth: 480, idealWidth: 720, minHeight: 360, idealHeight: 560)
    .task {
      do { image = try await load() } catch {
        if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
}
