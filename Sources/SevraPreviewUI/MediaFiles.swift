import Foundation
import SevraMedia
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

public typealias PreviewImage = SevraMedia.PreviewImage
