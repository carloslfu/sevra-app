import Foundation
import UniformTypeIdentifiers

final class CaptureDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let maximum: Int64
  let cancellation: Cancellation
  let progress: @Sendable (Int64, Int64) -> Void
  private let lock = NSLock()
  private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
  private var saved: (URL, URLResponse)?
  private var failure: Error?
  private var redirects = 0
  init(
    maximum: Int64, cancellation: Cancellation, progress: @escaping @Sendable (Int64, Int64) -> Void
  ) {
    self.maximum = maximum
    self.cancellation = cancellation
    self.progress = progress
  }
  static func validate(_ url: URL) throws {
    try require(
      ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
        && url.user == nil && url.password == nil, "url",
      "Use an HTTP or HTTPS URL without embedded credentials.")
  }
  func fetch(_ url: URL) async throws -> (URL, URLResponse) {
    try Self.validate(url)
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.httpShouldSetCookies = false
    config.urlCache = nil
    config.timeoutIntervalForRequest = 45
    config.timeoutIntervalForResource = 600
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    defer { session.invalidateAndCancel() }
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let task = session.downloadTask(with: url)
      task.resume()
      Task {
        while task.state == .running || task.state == .suspended {
          if self.cancellation.isCancelled {
            task.cancel()
            return
          }
          try? await Task.sleep(nanoseconds: 100_000_000)
        }
      }
    }
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    redirects += 1
    do {
      guard let url = request.url else { throw SevraError("url", "Redirect has no URL.") }
      try Self.validate(url)
      try require(redirects <= 6, "redirect", "Too many redirects.")
      completionHandler(request)
    } catch {
      failure = error
      completionHandler(nil)
      task.cancel()
    }
  }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    if totalBytesWritten > maximum || totalBytesExpectedToWrite > maximum {
      failure = SevraError(
        "download_limit",
        "This capture exceeds the 512 MB download limit. Download the file yourself and include it from disk."
      )
      downloadTask.cancel()
    }
    if cancellation.isCancelled { downloadTask.cancel() }
    progress(totalBytesWritten, totalBytesExpectedToWrite)
  }
  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    do {
      guard let response = downloadTask.response as? HTTPURLResponse,
        (200...299).contains(response.statusCode)
      else {
        throw SevraError(
          "http", "The source could not be retrieved. Authentication or access may be required.")
      }
      let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      try require(Int64(size) <= maximum, "download_limit", "The capture exceeds its size limit.")
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "sevra-capture-" + identifier())
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      var name = URL(fileURLWithPath: response.suggestedFilename ?? "Captured source")
        .lastPathComponent
      if URL(fileURLWithPath: name).pathExtension.isEmpty, let mime = response.mimeType,
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension
      {
        name += "." + ext
      }
      let dest = folder.appendingPathComponent(name)
      try FileManager.default.moveItem(at: location, to: dest)
      saved = (dest, response)
    } catch { failure = error }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    lock.lock()
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()
    if failure != nil || error != nil || cancellation.isCancelled {
      if let saved { try? FileManager.default.removeItem(at: saved.0.deletingLastPathComponent()) }
    }
    if let failure {
      continuation?.resume(throwing: failure)
    } else if cancellation.isCancelled {
      continuation?.resume(throwing: SevraError("cancelled", "Capture cancelled."))
    } else if let error {
      continuation?.resume(throwing: error)
    } else if let saved {
      continuation?.resume(returning: saved)
    } else {
      continuation?.resume(throwing: SevraError("download", "No captured file was produced."))
    }
  }
}
extension Workbook {
  @discardableResult public func captureURL(
    _ url: URL, cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }
  ) async throws -> Item {
    try CaptureDownload.validate(url)
    try cancellation.check()
    let file: URL
    let response: URLResponse
    do {
      (file, response) = try await CaptureDownload(
        maximum: 512_000_000, cancellation: cancellation, progress: progress
      ).fetch(url)
    } catch {
      try cancellation.check()
      let reason = (error as? SevraError)?.message ?? "The download could not be completed."
      let reference = try addItem(
        category: "source", kind: "link", title: "Uncaptured source: " + (url.host ?? "Website"),
        text: Self.safeOrigin(url) + "\n\nReference only. No file was captured. " + reason,
        data: .object([
          "url": .string(Self.safeOrigin(url)), "captureState": .string("failed"),
          "detail": .string(reason),
        ]), status: "accepted")
      try index(
        reference.id, chunks: [], state: "failed",
        detail: "Reference preserved; source content is not searchable. " + reason)
      return reference
    }
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let origin = Self.safeOrigin(response.url ?? url)
    let captured = try importFile(file, origin: origin, cancellation: cancellation)
    do { try extract(captured.id, cancellation: cancellation) } catch { try cancellation.check() }
    return captured
  }
  @discardableResult public func linkURL(_ url: URL, title: String) throws -> Item {
    try CaptureDownload.validate(url)
    return try addItem(
      category: "source", kind: "link", title: title, text: Self.safeOrigin(url),
      data: .object(["url": .string(Self.safeOrigin(url)), "captureState": .string("reference")]),
      status: "accepted")
  }
  public static func safeOrigin(_ url: URL) -> String {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let query = components?.queryItems
    components?.queryItems = query?.map { item in
      let name = item.name.lowercased()
      let sensitive =
        [
          "token", "signature", "sig", "key", "api_key", "access_token", "authorization",
          "password", "credential",
        ].contains(name) || name.hasPrefix("x-amz-") || name.hasPrefix("x-goog-")
      return sensitive ? URLQueryItem(name: item.name, value: "REDACTED") : item
    }
    components?.fragment = nil
    components?.user = nil
    components?.password = nil
    return components?.url?.absoluteString ?? "URL unavailable"
  }
  @discardableResult public func includeLinked(_ id: String, cancellation: Cancellation = .init())
    throws -> Item
  {
    let old = try item(id)
    guard let asset = old.assetID else { throw SevraError("asset", "This record has no asset.") }
    let source = try assetURL(asset, verify: true, cancellation: cancellation)
    let imported = try importFile(source, cancellation: cancellation)
    try extract(imported.id, cancellation: cancellation)
    let included = try addItem(
      category: old.category, kind: old.kind, title: old.title, text: old.text, data: old.data,
      meaning: old.meaning, status: old.status, scenario: old.scenario,
      inputs: [old.id, imported.id], transformation: "include-external-v1",
      assetID: imported.assetID, supersedes: old.id)
    try extract(included.id, cancellation: cancellation)
    return included
  }
  @discardableResult public func relinkAsset(
    _ id: String, to file: URL, cancellation: Cancellation = .init(),
    progress: (Int64, Int64) -> Void = { _, _ in }
  ) throws -> URL {
    try cancellation.check()
    let a = try asset(id)
    try require(a.mode == "linked", "asset", "Only external references can be relinked.")
    try require(
      try Self.hashFile(file, cancellation: cancellation) { progress($0, a.bytes) } == a.hash,
      "changed_asset",
      "These bytes differ from the recorded original. Import it as a new version instead.")
    let bookmark = try file.bookmarkData(
      options: [], includingResourceValuesForKeys: nil, relativeTo: nil
    ).base64EncodedString()
    _ = try mutation("relink", request: .object(["asset": .string(id), "hash": .string(a.hash)])) {
      try cancellation.check()
      try db.execute(
        "UPDATE assets SET path=?,bookmark=? WHERE id=?",
        [.string(file.path), .string(bookmark), .string(id)])
      return .string(id)
    }
    return file
  }
}
