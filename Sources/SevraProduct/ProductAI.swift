import Foundation
import SevraAI
import SevraCore

#if SEVRA_NATIVE_CANDIDATE
  import SevraNativeAI
  import SevraSplash
#else
  import SevraBaseline
#endif

/// One application model, shared by the native UI and CLI. The baseline adapter
/// remains available to qualification tests without entering a native product.
public actor ProductAI {
  public static let shared = ProductAI()
  private var active = false
  private var activeCancellation: Cancellation?
  private var releaseRequested = false
  private var model: (any WorkbookInference)?
  private var pressureSource: DispatchSourceMemoryPressure?
  private let observesSystemPressure: Bool

  private init() {
    observesSystemPressure = true
    #if !SEVRA_NATIVE_CANDIDATE
      model = LocalModel.shared
    #endif
  }
  /// Internal qualification seam, shared with the workbook agent's synthetic and native checks.
  package init(qualifying model: any WorkbookInference) {
    self.model = model
    observesSystemPressure = false
  }

  deinit {
    pressureSource?.cancel()
    pressureSource?.setEventHandler(handler: nil)
  }

  private func observeMemoryPressure() {
    guard observesSystemPressure, pressureSource == nil else { return }
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.warning, .critical], queue: .global(qos: .utility))
    source.setEventHandler { [weak self] in
      let critical = source.data.contains(.critical)
      Task { await self?.handleMemoryPressure(critical: critical) }
    }
    pressureSource = source
    source.resume()
  }

  public enum PressureResponse: String, Sendable {
    case released, deferred, stopping, releasePending
  }
  #if SEVRA_NATIVE_CANDIDATE
    public static let name = "Local AI · Native preview"
    public static let detail = "Qwen3.6 35B · Splash · DFlash 2"
    public static let revision = "splash-1.4.1-native-candidate"
    public static let preferenceKey = "nativeModelsRoot"
    public static let canReuseModel = true
    public static var defaultDirectory: URL {
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support/Sevra/Models")
    }
    public static var downloadBytes: Int64 {
      guard let pack = try? SplashModelPack.selected() else { return 0 }
      return (pack.target.files + pack.draft.files).reduce(0) { $0 + $1.bytes }
    }
  #else
    public static let name = "Slotstream Fast"
    public static let detail = "Qwen3.6 35B · MLX · DFlash 2"
    public static let revision = LocalModel.revision
    public static let preferenceKey = "modelDirectory"
    public static let canReuseModel = false
    public static var defaultDirectory: URL { LocalModel.defaultDirectory }
    public static var downloadBytes: Int64 { LocalModel.downloadBytes }
  #endif

  public static var suggestedReuseDirectory: URL? {
    #if SEVRA_NATIVE_CANDIDATE
      guard let name = try? SplashModelPack.selected().name else { return nil }
      let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".slotstream/models/" + name)
      return FileManager.default.fileExists(atPath: directory.path) ? directory : nil
    #else
      return nil
    #endif
  }

  public static func checkResources(validateMetal: Bool = true) async throws -> Value {
    try require(
      FileManager.default.isExecutableFile(atPath: ExtractionWorker.bundledExecutable.path),
      "resources", "The installed document extractor is missing.")
    let result: Value
    #if SEVRA_NATIVE_CANDIDATE
      result = try await Task.detached {
        try NativeProductResources.check(validateMetal: validateMetal)
      }.value
    #else
      result = try await PackageResources.check(validateMetal: validateMetal)
    #endif
    var fields = result.object
    fields["extractionWorker"] = .bool(true)
    return .object(fields)
  }

  /// Presence is a quick UI hint. Setup and every new native session perform
  /// verification; this never claims that file existence proves usable weights.
  public func installed(at directory: URL = ProductAI.defaultDirectory) async -> Bool {
    #if SEVRA_NATIVE_CANDIDATE
      guard let pack = try? SplashModelPack.selected() else { return false }
      return FileManager.default.fileExists(
        atPath: directory.appendingPathComponent(pack.name + "/model.json").path)
    #else
      return await LocalModel.shared.installed(at: directory)
    #endif
  }

  public func setup(
    at directory: URL = ProductAI.defaultDirectory, reusing source: URL? = nil,
    cancellation: Cancellation, progress: @escaping @Sendable (String) -> Void
  ) async throws {
    try await perform(cancellation: cancellation) {
      let released = await model?.releaseResources() ?? true
      releaseRequested = !released
      try require(released, "busy", "The model has not stopped yet. Retry setup.")
      #if SEVRA_NATIVE_CANDIDATE
        try await Task.detached(priority: .userInitiated) {
          let updates = SetupProgress(progress)
          _ = try SplashModelSetup.install(
            modelsRoot: directory, reusingTarget: source,
            reusingDraft: source?.appendingPathComponent("dflash"),
            cancelled: { cancellation.isCancelled || cancellation.isExpired },
            progress: updates.receive)
          try cancellation.check()
        }.value
      #else
        try require(
          source == nil, "model_setup", "Choose the existing model folder before verification.")
        try await LocalModel.shared.setup(
          at: directory, cancellation: cancellation, progress: progress)
      #endif
    }
  }

  /// Ordinary user unload does not interrupt an active job.
  @discardableResult public func unload() async -> Bool {
    guard !active else { return false }
    active = true
    let released = await model?.releaseResources() ?? true
    releaseRequested = !released
    active = false
    return released
  }

  /// Warnings defer release until the current transaction/job finishes. Critical
  /// pressure reaches the existing cancellation path, then releases after endRun.
  @discardableResult public func handleMemoryPressure(critical: Bool) async -> PressureResponse {
    if active {
      releaseRequested = true
      if critical, let cancellation = activeCancellation {
        cancellation.cancel(
          reason:
            "Local AI stopped because this Mac is low on memory. Completed workbook changes are saved. Close other apps and try again."
        )
        return .stopping
      }
      return .deferred
    }
    return await unload() ? .released : .releasePending
  }

  private func perform<T>(cancellation: Cancellation, operation: () async throws -> T) async throws
    -> T
  {
    try require(!active, "busy", "Sevra is already using its local model.")
    active = true
    activeCancellation = cancellation
    observeMemoryPressure()
    // If the prior helper could not be reaped, no new operation may reuse it.
    if releaseRequested {
      let released = await model?.releaseResources() ?? true
      releaseRequested = !released
      if !released {
        activeCancellation = nil
        active = false
        throw SevraError(
          "model_release", "The previous local model has not stopped yet. Retry after it finishes.")
      }
    }
    do {
      try cancellation.check()
      let result = try await operation()
      await finishOperation()
      return result
    } catch {
      await finishOperation()
      if cancellation.isCancelled { try cancellation.check() }
      throw error
    }
  }

  private func finishOperation() async {
    activeCancellation = nil
    if releaseRequested {
      let released = await model?.releaseResources() ?? true
      releaseRequested = !released
    }
    active = false
  }

  public func run(
    _ prompt: String, workbook: Workbook, conversation: String = "main", context: String = "",
    modelDirectory: URL = ProductAI.defaultDirectory, cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (String) -> Void = { _ in }, openSpace: SpaceOpener? = nil
  ) async throws -> AgentResult {
    try await perform(cancellation: cancellation) {
      #if SEVRA_NATIVE_CANDIDATE
        if model == nil {
          model = NativeWorkbookModel(
            configuration:
              try NativeProductResources.configuration(modelsRoot: modelDirectory))
        }
      #endif
      guard let model else { throw SevraError("model", "The local model is unavailable.") }
      return try await WorkbookAgent.run(
        prompt, workbook: workbook, conversation: conversation, context: context,
        modelDirectory: modelDirectory, cancellation: cancellation, progress: progress,
        model: model,
        openSpace: openSpace
      )
    }
  }

}

#if SEVRA_NATIVE_CANDIDATE
  /// Network callbacks may arrive many times per frame. Keep UI updates bounded
  /// without delaying cancellation or disk writes.
  private final class SetupProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var lastTime = -Double.infinity
    private var lastFile = ""
    private let report: @Sendable (String) -> Void
    init(_ report: @escaping @Sendable (String) -> Void) { self.report = report }
    func receive(_ update: SplashModelSetup.Progress) {
      lock.lock()
      let now = ProcessInfo.processInfo.systemUptime
      let key = update.phase + "/" + update.file
      let emit =
        key != lastFile || now - lastTime >= 0.2 || update.completedBytes == update.totalBytes
      if emit {
        lastTime = now
        lastFile = key
      }
      lock.unlock()
      if emit {
        if update.totalBytes == 0 {
          report("\(update.phase): \(update.file)")
          return
        }
        let amount = ByteCountFormatter.string(
          fromByteCount: update.completedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: update.totalBytes, countStyle: .file)
        report("\(update.phase): \(update.file) · \(amount) of \(total)")
      }
    }
  }
#endif
