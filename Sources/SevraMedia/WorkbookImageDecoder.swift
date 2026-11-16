import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import SevraCore

/// One process-wide decoder and cache. Input is read once into a bounded
/// buffer, and the very bytes passed to ImageIO must match the saved hash.
public actor WorkbookImageDecoder {
  public static let shared = WorkbookImageDecoder()
  private let cache = NSCache<NSString, ImageEntry>()
  public static let byteLimit = 32 * 1024 * 1024

  private init() {
    cache.totalCostLimit = 48 * 1024 * 1024
    cache.countLimit = 24
  }

  public func load(_ asset: ImageAssetRead, enlarged: Bool = false) async throws -> PreviewImage {
    let cancellation = Cancellation()
    return try await withTaskCancellationHandler {
      try load(asset, enlarged: enlarged, cancellation: cancellation)
    } onCancel: {
      cancellation.cancel()
    }
  }

  private func load(_ asset: ImageAssetRead, enlarged: Bool, cancellation: Cancellation) throws
    -> PreviewImage
  {
    try cancellation.check()
    try require(
      asset.bytes > 0 && asset.bytes <= Self.byteLimit, "visual_image_bytes",
      "This file is too large for an inline image. Open the original file to inspect it.")
    let descriptor = Darwin.open(asset.file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    try require(descriptor >= 0, "visual_image", "The included image file is unavailable.")
    let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? file.close() }

    var information = stat()
    try require(
      fstat(descriptor, &information) == 0 && (information.st_mode & S_IFMT) == S_IFREG
        && information.st_size == asset.bytes,
      "visual_image_size", "The included image file changed.")
    var data = Data()
    data.reserveCapacity(Int(asset.bytes))
    var hash = SHA256()
    while data.count < asset.bytes {
      try cancellation.check()
      guard let chunk = try file.read(upToCount: min(1_048_576, Int(asset.bytes) - data.count)),
        !chunk.isEmpty
      else { throw SevraError("visual_image_size", "The included image file changed.") }
      data.append(chunk)
      hash.update(data: chunk)
    }
    try require(
      try (file.read(upToCount: 1)?.isEmpty ?? true)
        && hash.finalize().map { String(format: "%02x", $0) }.joined() == asset.hash,
      "visual_image_hash", "The included image file changed.")
    let size = enlarged ? ImagePreviewPixels.maximumDimension : 1024
    let key = (asset.hash + "/" + String(size)) as NSString
    if let cached = cache.object(forKey: key) { return cached.preview }

    let pixels = try ExtractionWorker.previewImage(
      data, hash: asset.hash, enlarged: enlarged, cancellation: cancellation)
    try cancellation.check()
    guard (1...size).contains(pixels.width), (1...size).contains(pixels.height),
      pixels.rgba.count == pixels.width * pixels.height * 4,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: pixels.rgba as CFData),
      let image = CGImage(
        width: pixels.width, height: pixels.height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: pixels.width * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { throw SevraError("visual_image_decode", "The image preview returned invalid pixels.") }
    let preview = PreviewImage(
      image: image, points: CGSize(width: image.width, height: image.height))
    let cost = image.bytesPerRow * image.height
    if cost <= 16 * 1024 * 1024 {
      cache.setObject(ImageEntry(preview), forKey: key, cost: cost)
    }
    return preview
  }

  private final class ImageEntry: NSObject {
    let preview: PreviewImage
    init(_ preview: PreviewImage) { self.preview = preview }
  }
}
