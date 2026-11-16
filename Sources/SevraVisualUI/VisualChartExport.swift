import AppKit
import CoreGraphics
import SevraCore
import SwiftUI

public enum VisualChartExport {
  @MainActor public static func data(
    chart: VisualChart, captured: VisualChartData, format: String
  ) throws -> Data {
    if format == "csv" { return captured.csv(chart) }
    let size = CGSize(width: 820, height: 400)
    let renderer = ImageRenderer(
      content:
        VStack(alignment: .leading, spacing: 14) {
          VisualChartView(definition: chart, data: captured, showsInspection: false)
          Spacer(minLength: 0)
          Text("Captured " + captured.captured)
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(.white).environment(\.colorScheme, .light)
    )
    renderer.proposedSize = ProposedViewSize(size)
    switch format {
    case "png":
      renderer.scale = 2
      guard let image = renderer.cgImage,
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
      else { throw SevraError("visual_export", "The chart could not be rendered as PNG.") }
      return png
    case "pdf":
      let output = NSMutableData()
      var box = CGRect(origin: .zero, size: size)
      guard let destination = CGDataConsumer(data: output),
        let context = CGContext(consumer: destination, mediaBox: &box, nil)
      else { throw SevraError("visual_export", "The PDF renderer is unavailable.") }
      renderer.render { _, paint in
        context.beginPDFPage(nil)
        paint(context)
        context.endPDFPage()
      }
      context.closePDF()
      guard output.length > 0 else {
        throw SevraError("visual_export", "The chart could not be rendered as PDF.")
      }
      return output as Data
    default:
      throw SevraError("visual_export", "Save the chart as PNG, PDF or CSV.")
    }
  }
}
