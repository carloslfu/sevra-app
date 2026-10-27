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
  #if SEVRA_NATIVE_CANDIDATE
    private var native: NativeWorkbookModel?
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
    #if SEVRA_NATIVE_CANDIDATE
      return try await Task.detached {
        try NativeProductResources.check(validateMetal: validateMetal)
      }.value
    #else
      return try await PackageResources.check(validateMetal: validateMetal)
    #endif
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
    try require(!active, "busy", "Wait for the current local model operation.")
    active = true
    defer { active = false }
    #if SEVRA_NATIVE_CANDIDATE
      if let native {
        let released = await native.unload()
        try require(released, "busy", "The native model has not stopped yet. Retry setup.")
      }
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

  @discardableResult public func unload() async -> Bool {
    guard !active else { return false }
    active = true
    defer { active = false }
    #if SEVRA_NATIVE_CANDIDATE
      return await native?.unload() ?? true
    #else
      return await LocalModel.shared.unload()
    #endif
  }

  public func run(
    _ prompt: String, workbook: Workbook, conversation: String = "main", context: String = "",
    modelDirectory: URL = ProductAI.defaultDirectory, cancellation: Cancellation = .init(),
    progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws -> AgentResult {
    try require(!active, "busy", "Sevra is already using its local model.")
    active = true
    defer { active = false }
    #if SEVRA_NATIVE_CANDIDATE
      if native == nil {
        let configuration = try NativeProductResources.configuration(modelsRoot: modelDirectory)
        native = NativeWorkbookModel(configuration: configuration)
      }
      return try await WorkbookAgent.run(
        prompt, workbook: workbook, conversation: conversation, context: context,
        modelDirectory: modelDirectory, cancellation: cancellation, progress: progress,
        model: native!)
    #else
      return try await WorkbookAgent.run(
        prompt, workbook: workbook, conversation: conversation, context: context,
        modelDirectory: modelDirectory, cancellation: cancellation, progress: progress)
    #endif
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
