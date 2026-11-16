import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The parser returns bounded sRGB pixels, so the host does not parse an image
/// container supplied by a workbook. This is ephemeral transport data.
package struct ImagePreviewPixels: Codable, Sendable {
  package let width: Int
  package let height: Int
  package let rgba: Data

  static let maximumEncodedBytes = 32 * 1024 * 1024
  package static let maximumDimension = 3072

  static func decode(_ url: URL, dimension: Int, hash: String) throws -> ImagePreviewPixels {
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    try require(
      (1...maximumDimension).contains(dimension), "visual_image_bytes", "Invalid preview size.")
    guard let data = try input.read(upToCount: maximumEncodedBytes + 1),
      !data.isEmpty, data.count <= maximumEncodedBytes
    else { throw SevraError("visual_image_bytes", "This file exceeds the image preview limit.") }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    try require(digest == hash, "visual_image_hash", "The included image file changed.")
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, options),
      let format = CGImageSourceGetType(source) as String?,
      UTType(format)?.conforms(to: .image) == true,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, (1...20_000).contains(width),
      let height = properties[kCGImagePropertyPixelHeight] as? Int, (1...20_000).contains(height),
      width * height <= 48_000_000
    else {
      throw SevraError(
        "visual_image_format", "This image format or resolution cannot be previewed.")
    }
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
          kCGImageSourceThumbnailMaxPixelSize: dimension,
        ] as CFDictionary), let space = CGColorSpace(name: CGColorSpace.sRGB),
      let canvas = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let pixels = canvas.data
    else { throw SevraError("visual_image_decode", "The image could not be decoded.") }
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return ImagePreviewPixels(
      width: image.width, height: image.height,
      rgba: Data(bytes: pixels, count: canvas.bytesPerRow * image.height))
  }
}

extension ExtractionWorker {
  package static func previewImage(
    _ verified: Data, hash: String, enlarged: Bool, cancellation: Cancellation
  )
    throws -> ImagePreviewPixels
  {
    try cancellation.check()
    try require(
      verified.count <= ImagePreviewPixels.maximumEncodedBytes,
      "visual_image_bytes", "This file exceeds the image preview limit.")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-image-" + identifier())
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("original")
    try verified.write(to: input)
    let size = enlarged ? ImagePreviewPixels.maximumDimension : 1024
    let worker = ExtractionWorker(timeout: 3, maximumMemoryBytes: 384 * 1024 * 1024)
    return try worker.run(
      input, mode: ["--image-preview=\(size)", hash], cancellation: cancellation)
  }
}
