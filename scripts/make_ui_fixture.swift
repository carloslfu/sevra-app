// Synthetic native intake/viewer fixtures. Run with: swift scripts/make_ui_fixture.swift NEW_DIRECTORY
import CoreGraphics
import CoreText
import Foundation
import ImageIO

guard CommandLine.arguments.count == 2 else {
  fatalError("Usage: swift scripts/make_ui_fixture.swift NEW_DIRECTORY")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
guard !FileManager.default.fileExists(atPath: root.path) else {
  fatalError("Choose a new fixture directory; existing files are never replaced.")
}
let imports = root.appendingPathComponent("imports", isDirectory: true)
let paging = root.appendingPathComponent("paging", isDirectory: true)
try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: paging, withIntermediateDirectories: true)

func draw(_ lines: [String], in context: CGContext) {
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 1000, height: 600))
  for (index, text) in lines.enumerated() {
    context.textPosition = CGPoint(x: 50, y: 510 - index * 65)
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(
        string: text,
        attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String):
            CTFontCreateWithName("Helvetica" as CFString, 34, nil),
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
            gray: 0, alpha: 1),
        ]))
    CTLineDraw(line, context)
  }
}

let pdf = imports.appendingPathComponent("Delivery_Ñandú_2026.pdf")
var box = CGRect(x: 0, y: 0, width: 1000, height: 600)
let context = CGContext(pdf as CFURL, mediaBox: &box, nil)!
for lines in [
  [
    "SYNTHETIC INVOICE SIERRA 1042", "20 brass bolts", "Unit price: 2.50", "Total: 50.00",
    "No currency specified",
  ],
  [
    "SYNTHETIC DELIVERY TERMS", "Quartz delivery deadline: 30 November 2026",
    "Pickup at the north warehouse", "No customer or personal data",
  ],
] {
  context.beginPDFPage(nil)
  draw(lines, in: context)
  context.endPDFPage()
}
context.closePDF()

let bitmap = CGContext(
  data: nil, width: 1000, height: 600, bitsPerComponent: 8, bytesPerRow: 4000,
  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
draw(
  [
    "SYNTHETIC RECEIPT VEGA 2043", "2 brass bolts handed over", "Fulfillment evidence only",
    "No automatic inventory acceptance",
  ], in: bitmap)
let png = imports.appendingPathComponent("Receipt_Vega_2043.png")
let destination = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else {
  fatalError("Could not write the image fixture.")
}

try "supplier,item,quantity,unit_cost\nSierra,Brass bolts,20,2.50\nVega,Brass bolts,20,2.75\n"
  .write(
    to: imports.appendingPathComponent("Supplier_quotes.csv"), atomically: true, encoding: .utf8)
for number in 1...35 {
  let name = String(format: "Amber_%02d.txt", number)
  try "Synthetic pagination marker amber, note \(number). No business effect.\n"
    .write(to: paging.appendingPathComponent(name), atomically: true, encoding: .utf8)
}
print("Created three intake files and 35 pagination notes in \(root.path)")
