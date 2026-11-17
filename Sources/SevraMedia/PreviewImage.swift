import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picture decoded to a bounded size, because a 6,000 pixel square photo takes 178 MB in full.
public struct PreviewImage: @unchecked Sendable {
  public static let maximumPixels = 4096
  public let image: CGImage
  /// The size the original would have on screen, whatever size it was decoded at.
  public let points: CGSize
  let memory: ImageMemoryLease?

  init(image: CGImage, points: CGSize, memory: ImageMemoryLease? = nil) {
    self.image = image
    self.points = points
    self.memory = memory
  }

  /// Call off the main thread. An unreadable file returns nil.
  public static func load(
    _ file: URL, maximumPixels: Int = maximumPixels, requireImageType: Bool = false
  ) -> PreviewImage? {
    let cached = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(file as CFURL, cached) else { return nil }
    if requireImageType {
      guard let type = CGImageSourceGetType(source) as String?,
        UTType(type)?.conforms(to: .image) == true
      else { return nil }
    }
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, cached) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int, width > 0,
      let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0,
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ] as CFDictionary)
    else { return nil }
    let resolution = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil }
    let scale =
      Double(max(width, height)) / Double(max(image.width, image.height))
      * (72 / (resolution ?? 72))
    return PreviewImage(
      image: image,
      points: CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale))
  }
}
