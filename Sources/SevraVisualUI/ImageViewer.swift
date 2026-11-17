import AppKit
import SwiftUI

public struct ImageViewer: View {
  private let image: NSImage
  private let title: String
  private let fitInitially: Bool
  private let imageHint: String
  @State private var scale = 1.0

  public init(
    image: NSImage, title: String, fitInitially: Bool = false, imageHint: String = "",
    initialScale: Double = 1
  ) {
    self.image = image
    self.title = title
    self.fitInitially = fitInitially
    self.imageHint = imageHint
    _scale = State(initialValue: min(6, max(0.25, initialScale)))
  }

  public var body: some View {
    VStack {
      HStack {
        Button("Zoom out") { scale = max(0.25, scale / 1.25) }
          .disabled(scale <= 0.25)
        Button("Zoom in") { scale = min(6, scale * 1.25) }
          .disabled(scale >= 6)
        if scale != 1 { Button("Reset zoom") { scale = 1 } }
        Spacer()
      }.padding(12)
      if fitInitially {
        GeometryReader { viewport in
          let aspect = image.size.width / max(1, image.size.height)
          let width = max(
            1, min(viewport.size.width - 40, (viewport.size.height - 40) * aspect))
          zoomedImage(width: min(image.size.width, width), viewport: viewport.size)
        }
      } else {
        zoomedImage(width: min(1000, image.size.width))
      }
    }
  }

  private func zoomedImage(width: CGFloat, viewport: CGSize = .zero) -> some View {
    ScrollView([.horizontal, .vertical]) {
      Image(nsImage: image).resizable().scaledToFit().frame(width: width * scale)
        .padding(20).accessibilityLabel("Image: " + title)
        .accessibilityHint(imageHint)
        .frame(minWidth: viewport.width, minHeight: viewport.height)
    }
  }
}
