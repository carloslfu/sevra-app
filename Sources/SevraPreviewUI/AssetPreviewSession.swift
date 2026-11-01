import Foundation
import SevraCore
import SwiftUI

/// One preview owns one cancellable verification. Neither late results nor
/// progress from a superseded file may change the currently displayed preview.
@MainActor public final class AssetPreviewSession: ObservableObject {
  @Published public private(set) var file: URL?
  @Published public private(set) var failure: String?
  @Published public private(set) var loading = false
  @Published public private(set) var checkedBytes: Int64 = 0
  @Published public private(set) var totalBytes: Int64 = 0
  @Published public private(set) var reloadID = UUID()
  public private(set) var originalURL: URL?
  public var isExternal = false
  private var request = UUID()
  private var cancellation: Cancellation?

  public init() {}

  @discardableResult public func load(
    resolve:
      @escaping @Sendable (
        Cancellation, @escaping @Sendable (Int64, Int64) -> Void
      ) async throws -> URL
  ) async -> Bool {
    guard !Task.isCancelled else { return false }
    cancel()
    let identity = UUID()
    let token = Cancellation()
    request = identity
    cancellation = token
    failure = nil
    loading = true
    let relay = PreviewProgressRelay { [weak self] bytes, total in
      Task { @MainActor [weak self] in
        guard let self, self.request == identity, self.loading, !token.isCancelled else { return }
        self.checkedBytes = max(self.checkedBytes, bytes)
        self.totalBytes = max(0, total)
      }
    }
    defer {
      if request == identity {
        loading = false
        cancellation = nil
      }
    }
    do {
      let result = try await withTaskCancellationHandler {
        try token.check()
        return try await resolve(token) { relay.send($0, $1) }
      } onCancel: {
        token.cancel()
      }
      try Task.checkCancellation()
      try token.check()
      guard request == identity else { return false }
      file = result
      return true
    } catch {
      guard request == identity, !Task.isCancelled, !token.isCancelled else { return false }
      failure = error.localizedDescription
      // A refused original is not tried again. Retry reads the workbook's own file.
      originalURL = nil
      return false
    }
  }

  public func cancel() {
    request = UUID()
    cancellation?.cancel()
    cancellation = nil
    file = nil
    failure = nil
    loading = false
    checkedBytes = 0
    totalBytes = 0
  }

  public func stop() {
    cancel()
    failure = "Preview stopped. You can retry when you are ready."
  }

  public func retry() {
    cancel()
    reloadID = UUID()
  }

  public func reconnect(to url: URL) {
    originalURL = url
    retry()
  }

  public func didResolve(_ identity: UUID) {
    guard reloadID == identity else { return }
    originalURL = nil
  }
}

/// Explicit shell controls work without waiting for inference. Match complete
/// submissions only, so requests such as "don't stop" cannot become cancellation.
public enum WorkspaceControlCommand: Equatable {
  case stop, stopPreview, retryPreview, findOriginal, openCopy, showMentions, showLinks, goBack

  public static func parse(_ input: String) -> Self? {
    let text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    switch text {
    case "where is this mentioned", "show mentions", "show incoming links",
      "dónde se menciona esto":
      return .showMentions
    case "show links", "show links in this document", "show references", "mostrar enlaces":
      return .showLinks
    case "go back", "back", "volver", "atrás": return .goBack
    case "stop", "cancel", "stop work", "cancel operation", "detener", "cancelar": return .stop
    case "stop preview", "cancel preview", "stop opening this file": return .stopPreview
    case "retry preview", "retry this preview", "open this file again": return .retryPreview
    case "find original", "find the original", "find the original file": return .findOriginal
    case "open a copy", "open a copy in another app", "open in another app",
      "open this in another app", "open this file in another app":
      return .openCopy
    default: return nil
    }
  }

  /// A submission is a page to capture only when the whole of it is one URL.
  /// `URL(string:)` percent-encodes spaces, so prose after a link would parse too.
  public static func captureURL(_ input: String) -> URL? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
      let target = URL(string: text), ["http", "https"].contains(target.scheme ?? "")
    else { return nil }
    return target
  }

  public static func allowsSubmission(_ input: String, busy: Bool) -> Bool {
    guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    if !busy { return true }
    guard let command = parse(input) else { return false }
    // Copying owns the workspace operation slot; recovery/Stop stay available.
    return command != .openCopy
  }
}

/// Hashing reports each bounded chunk, but UI delivery stays bounded too.
private final class PreviewProgressRelay: @unchecked Sendable {
  private let lock = NSLock()
  private var last = -Double.infinity
  private let receive: @Sendable (Int64, Int64) -> Void
  init(receive: @escaping @Sendable (Int64, Int64) -> Void) { self.receive = receive }
  func send(_ bytes: Int64, _ total: Int64) {
    lock.lock()
    let now = ProcessInfo.processInfo.systemUptime
    let deliver = now - last >= 0.1
    if deliver { last = now }
    lock.unlock()
    if deliver { receive(bytes, total) }
  }
}
