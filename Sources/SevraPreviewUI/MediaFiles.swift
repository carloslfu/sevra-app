import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaFile {
  /// Audio and video by type, so FLAC, AAC and AIF get the player and Transcribe too.
  public static func isPlayable(_ file: URL) -> Bool {
    let suffix = file.pathExtension.lowercased()
    // The system reads .ts as an MPEG stream. In a workbook it is far more often TypeScript.
    return suffix != "ts"
      && UTType(filenameExtension: suffix)?.conforms(to: .audiovisualContent) == true
  }

  /// The position a citation names. Evidence locators keep other fields beside `time=`.
  public static func seconds(_ locator: String?) -> Double? {
    guard let locator, let range = locator.range(of: "time=[0-9.]+", options: .regularExpression),
      let seconds = Double(locator[range].dropFirst(5)), seconds.isFinite
    else { return nil }
    return seconds
  }
}

/// A picture decoded to a bounded size, because a 6,000 pixel square photo takes 178 MB in full.
public struct PreviewImage: @unchecked Sendable {
  public static let maximumPixels = 4096
  public let image: CGImage
  /// The size the original would have on screen, whatever size it was decoded at.
  public let points: CGSize

  /// Call off the main thread. An unreadable file returns nil.
  public static func load(_ file: URL) -> PreviewImage? {
    let cached = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(file as CFURL, cached),
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
