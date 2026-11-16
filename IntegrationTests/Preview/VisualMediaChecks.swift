import AppKit
import ImageIO
import SevraCore
import SevraMedia
import SevraVisualUI
import UniformTypeIdentifiers

@MainActor func checkVisualMedia() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier())
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: directory) }
  let workbook = try Workbook.create(
    at: directory.appendingPathComponent("Pixels.sevra"), title: "Pixels")
  func capture(_ name: String, _ data: Data) throws -> (ImageAssetRead, String) {
    let file = directory.appendingPathComponent(name)
    try data.write(to: file)
    return try captureVisualImage(file, workbook: workbook)
  }

  let red = try solidPNG(red: 1, blue: 0)
  let blue = try solidPNG(red: 0, blue: 1)
  let (redAsset, sourceID) = try capture("Red.png", red)
  let (blueAsset, _) = try capture("Blue.png", blue)
  // Same-sized files reach the hash check rather than failing on length.
  let equalSize = max(red.count, blue.count) + 16
  var paddedRed = red
  paddedRed.append(contentsOf: repeatElement(0, count: equalSize - red.count))
  var paddedBlue = blue
  paddedBlue.append(contentsOf: repeatElement(0, count: equalSize - blue.count))
  let (cachedAsset, _) = try capture("Cached.png", paddedRed)

  let first = try await WorkbookImageDecoder.shared.load(redAsset)
  let second = try await WorkbookImageDecoder.shared.load(blueAsset, enlarged: true)
  let cached = try await WorkbookImageDecoder.shared.load(cachedAsset)
  try assertPixel(first.image, red: 1, blue: 0)
  try assertPixel(second.image, red: 0, blue: 1)
  try assertPixel(cached.image, red: 1, blue: 0)
  try paddedBlue.write(to: cachedAsset.file, options: .atomic)
  do {
    _ = try await WorkbookImageDecoder.shared.load(cachedAsset)
    throw SevraError("preview_check", "A cached image hid a same-size source change.")
  } catch let error as SevraError where error.code == "visual_image_hash" {}
  try paddedRed.write(to: cachedAsset.file, options: .atomic)
  let restored = try await WorkbookImageDecoder.shared.load(cachedAsset)
  try assertPixel(restored.image, red: 1, blue: 0)
  print("PASS included image pixel identities, same-size corruption refusal and restored original")
  try checkGroupedChartExport(workbook, sourceID: sourceID)

}

@MainActor private func checkGroupedChartExport(_ workbook: Workbook, sourceID: String) throws {
  let table = try workbook.createDataset(
    title: "Stock",
    columns: [
      Column(id: "item", title: "Item"), Column(id: "site", title: "Site"),
      Column(id: "quantity", title: "Quantity", type: "decimal", unit: "units"),
    ],
    rows: [
      ["item": .string("Bolts"), "site": .string("Main"), "quantity": .string("9.125")],
      ["item": .string("Bolts"), "site": .string("West"), "quantity": .string("8.5")],
    ], sourceID: sourceID)
  let query = try Value.parse(
    """
    {"sources":[{"datasetID":"\(table.id)","definitionID":"\(table.definitionID)"}],
    "select":[{"id":"item","column":{"source":0,"column":"item"}},
    {"id":"site","column":{"source":0,"column":"site"}},
    {"id":"quantity","column":{"source":0,"column":"quantity"}}],"sort":[{"field":"site"}],"limit":10}
    """)
  let chart = VisualChart(
    title: "Stock by site", style: .bar, query: query, x: "item", y: "quantity",
    threshold: "10", series: "site")
  let captured = try workbook.chartData(chart)
  try require(
    captured.points.map(\.series) == ["Main", "West"]
      && captured.points.map(\.amount) == ["9.125", "8.5"],
    "preview_check", "Chart lost a series or a decimal.")
  let png = try VisualChartExport.data(chart: chart, captured: captured, format: "png")
  let pdf = try VisualChartExport.data(chart: chart, captured: captured, format: "pdf")
  let pngImage = CGImageSourceCreateWithData(png as CFData, nil).flatMap {
    CGImageSourceCreateImageAtIndex($0, 0, nil)
  }
  try require(
    pngImage?.width == 1640 && pngImage?.height == 800
      && CGDataProvider(data: pdf as CFData).flatMap({ CGPDFDocument($0) })?.numberOfPages == 1,
    "preview_check", "The captured chart did not export to readable PNG and PDF.")
  print("PASS grouped values and rendered captured chart PNG/PDF exports")
}

private func solidPNG(red: CGFloat, blue: CGFloat) throws -> Data {
  guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: 7, height: 5, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  else { throw SevraError("preview_check", "Could not create pixel fixture.") }
  context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: 7, height: 5))
  let output = NSMutableData()
  guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithData(
      output, UTType.png.identifier as CFString, 1, nil)
  else { throw SevraError("preview_check", "Could not encode pixel fixture.") }
  CGImageDestinationAddImage(destination, image, nil)
  try require(
    CGImageDestinationFinalize(destination), "preview_check", "Could not finalize pixel fixture.")
  return output as Data
}

private func captureVisualImage(_ file: URL, workbook: Workbook) throws -> (ImageAssetRead, String)
{
  let job = try workbook.captureIntake(file, role: .reference)
  let definition = try workbook.imageDefinition(sourceID: job.sourceID)
  guard let reference = definition.image?.reference else {
    throw SevraError("preview_check", "Image reference was missing.")
  }
  return (try workbook.imageAssetRead(reference), job.sourceID)
}

private func assertPixel(_ image: CGImage, red: CGFloat, blue: CGFloat) throws {
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
    let canvas = CGContext(
      data: nil, width: 7, height: 5, bitsPerComponent: 8,
      bytesPerRow: 28, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
    let bytes = canvas.data?.assumingMemoryBound(to: UInt8.self)
  else { throw SevraError("preview_check", "Decoded pixel was missing.") }
  canvas.draw(image, in: CGRect(x: 0, y: 0, width: 7, height: 5))
  let pixel = Array(UnsafeBufferPointer(start: bytes + 2 * 28 + 3 * 4, count: 4))
  try require(
    image.width == 7 && image.height == 5 && abs(Int(pixel[0]) - Int(red * 255)) < 3
      && abs(Int(pixel[2]) - Int(blue * 255)) < 3 && pixel[1] < 3 && pixel[3] >= 252,
    "preview_check",
    "Expected a 7 × 5 opaque sRGB image with red \(red), blue \(blue). Received \(image.width) × \(image.height), \(pixel)."
  )
}
