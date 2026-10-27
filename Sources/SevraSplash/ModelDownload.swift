import CryptoKit
import Darwin
import Foundation

/// A single pinned file. The caller serializes access to its private cache.
/// Bytes go straight to disk; no weight shard is accumulated in memory.
package enum PinnedModelDownload {
  package static func permitted(_ url: URL) -> Bool {
    url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil
  }

  package static func fetch(
    _ url: URL, to destination: URL, bytes: Int64, sha256: String,
    configuration: URLSessionConfiguration = .ephemeral,
    cancelled: @escaping () -> Bool = { false }, progress: @escaping (Int64) -> Void = { _ in }
  ) throws {
    guard permitted(url), bytes > 0 else { throw SplashError("Invalid model download") }
    if cancelled() { throw SplashError("Model setup cancelled") }
    let fd = open(destination.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw SplashError("Cannot open model download") }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var st = stat()
    guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_nlink == 1,
      st.st_size <= bytes
    else { throw SplashError("Unsafe or oversized partial model file") }
    if st.st_size < bytes {
      let delegate = ModelDownloadDelegate(
        handle: handle, total: bytes, offset: st.st_size, progress: progress)
      configuration.urlCache = nil
      configuration.httpCookieStorage = nil
      configuration.urlCredentialStorage = nil
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.timeoutIntervalForRequest = 60
      configuration.timeoutIntervalForResource = 6 * 60 * 60
      let queue = OperationQueue()
      queue.maxConcurrentOperationCount = 1
      let session = URLSession(
        configuration: configuration, delegate: delegate, delegateQueue: queue)
      defer { session.invalidateAndCancel() }
      var request = URLRequest(url: url)
      request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
      if st.st_size > 0 { request.setValue("bytes=\(st.st_size)-", forHTTPHeaderField: "Range") }
      let task = session.dataTask(with: request)
      task.resume()
      while delegate.done.wait(timeout: .now() + 0.1) == .timedOut {
        if cancelled() { task.cancel() }
      }
      // Completion is serialized after every write, so cleanup never races a
      // callback still using the file. Network failure preserves resumable bytes.
      if cancelled() { throw SplashError("Model setup cancelled; downloaded bytes are kept") }
      if let error = delegate.failure {
        if let error = error as? SplashError { throw error }
        // Foundation errors can contain temporary signed redirect URLs.
        // Keep those out of user messages and persisted setup reports.
        throw SplashError(
          "Model transfer failed (code \((error as NSError).code)); retry keeps downloaded bytes")
      }
      guard delegate.received == bytes else { throw SplashError("Incomplete model download") }
    }
    try handle.synchronize()
    try handle.seek(toOffset: 0)
    var hash = SHA256()
    var count: Int64 = 0
    while true {
      if cancelled() { throw SplashError("Model verification cancelled") }
      let amount: Int = try autoreleasepool {
        let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
        hash.update(data: data)
        return data.count
      }
      if amount == 0 { break }
      count += Int64(amount)
      guard count <= bytes else { throw SplashError("Model file changed during verification") }
    }
    guard count == bytes, hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha256
    else {
      // Only this setup-owned partial file is reset. Published selections and
      // user-supplied model folders are never modified here.
      try handle.truncate(atOffset: 0)
      throw SplashError("Model download failed SHA-256 verification; retry downloads a fresh copy")
    }
    progress(bytes)
  }
}

private final class ModelDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  let handle: FileHandle
  let total: Int64
  let offset: Int64
  let progress: (Int64) -> Void
  let done = DispatchSemaphore(value: 0)
  // Accessed only on the serial delegate queue, then after done is signaled.
  var received: Int64
  var failure: Error?
  init(handle: FileHandle, total: Int64, offset: Int64, progress: @escaping (Int64) -> Void) {
    self.handle = handle
    self.total = total
    self.offset = offset
    self.received = offset
    self.progress = progress
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let url = request.url, PinnedModelDownload.permitted(url) else {
      failure = SplashError("Model download refused an insecure redirect")
      completionHandler(nil)
      return
    }
    var next = request
    next.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    if offset > 0 { next.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
    completionHandler(next)
  }
  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    do {
      guard let http = response as? HTTPURLResponse,
        http.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" })
          ?? true
      else { throw SplashError("Invalid model download response") }
      switch http.statusCode {
      case 200:
        // A server may ignore Range. Restart rather than append duplicate bytes.
        guard http.value(forHTTPHeaderField: "Content-Range") == nil else {
          throw SplashError("Invalid full-file response")
        }
        received = 0
      case 206:
        guard
          http.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(total - 1)/\(total)"
        else {
          throw SplashError("Model server returned an unexpected byte range")
        }
      default:
        throw SplashError(
          "Model download HTTP \(http.statusCode); retry keeps prior verified setup")
      }
      if let length = http.value(forHTTPHeaderField: "Content-Length") {
        guard Int64(length) == total - received else {
          throw SplashError("Model response size mismatch")
        }
      }
      // Validate headers before replacing any resumable prefix.
      if http.statusCode == 200 { try handle.truncate(atOffset: 0) }
      try handle.seek(toOffset: UInt64(received))
      completionHandler(.allow)
    } catch {
      failure = error
      completionHandler(.cancel)
    }
  }
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard failure == nil else { return }
    do {
      guard Int64(data.count) <= total - received else {
        throw SplashError("Model response exceeds pinned size")
      }
      try handle.write(contentsOf: data)
      received += Int64(data.count)
      progress(received)
    } catch {
      failure = error
      dataTask.cancel()
    }
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if failure == nil { failure = error }
    done.signal()
  }
}
