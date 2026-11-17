import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import SevraCore

/// One process-wide decoder and cache. Input is read once into a bounded
/// buffer, and the very bytes passed to ImageIO must match the saved hash.
public actor WorkbookImageDecoder {
  public static let shared = WorkbookImageDecoder()
  private var cache: [String: PreviewImage] = [:]
  private var recency: [String] = []
  private nonisolated let ledger = ImageLedger()
  public static let byteLimit = 32 * 1024 * 1024

  private init() {}

  public nonisolated func load(_ asset: ImageAssetRead, enlarged: Bool = false) async throws
    -> PreviewImage
  {
    try require(ledger.enter(), "visual_image_limit", "Image previews are busy. Retry this image.")
    defer { ledger.leave() }
    let cancellation = Cancellation()
    return try await withTaskCancellationHandler {
      try await load(asset, enlarged: enlarged, cancellation: cancellation)
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
    let key = asset.hash + "/" + String(size)
    if let cached = cache[key] {
      recency.removeAll { $0 == key }
      recency.append(key)
      return cached
    }

    // Reserve before launching the helper. References retained by mounted
    // views remain charged after their entries are evicted from the cache.
    let maximumCost = size * size * 4
    var memory = ledger.reserve(maximumCost)
    while memory == nil, !recency.isEmpty {
      cache.removeValue(forKey: recency.removeFirst())
      memory = ledger.reserve(maximumCost)
    }
    guard let memory else {
      throw SevraError("visual_image_limit", "Too many images are open. Close an image and retry.")
    }
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
    let cost = image.bytesPerRow * image.height
    memory.shrink(to: cost)
    let preview = PreviewImage(
      image: image, points: CGSize(width: image.width, height: image.height), memory: memory)
    if cost <= 16 * 1024 * 1024 {
      if recency.count == 24 { cache.removeValue(forKey: recency.removeFirst()) }
      cache[key] = preview
      recency.append(key)
    }
    return preview
  }

}

final class ImageLedger: @unchecked Sendable {
  private let lock = NSLock()
  private var callers = 0
  private var bytes = 0

  func enter() -> Bool {
    lock.withLock {
      guard callers < 8 else { return false }
      callers += 1
      return true
    }
  }

  func leave() { lock.withLock { callers -= 1 } }

  func reserve(_ cost: Int) -> ImageMemoryLease? {
    lock.withLock {
      guard bytes + cost <= 48 * 1024 * 1024 else { return nil }
      bytes += cost
      return ImageMemoryLease(cost: cost, ledger: self)
    }
  }

  func release(_ cost: Int) { lock.withLock { bytes -= cost } }
}

final class ImageMemoryLease: @unchecked Sendable {
  private var cost: Int
  private let ledger: ImageLedger
  init(cost: Int, ledger: ImageLedger) {
    self.cost = cost
    self.ledger = ledger
  }

  // Called once by the decoder before publishing the preview.
  func shrink(to bytes: Int) {
    ledger.release(cost - bytes)
    cost = bytes
  }

  deinit { ledger.release(cost) }
}
