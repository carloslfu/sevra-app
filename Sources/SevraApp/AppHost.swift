import AppKit
import SevraCore
import SevraProduct
import SevraVoice

/// App-owned effects. The catalog compiles a controlled host; product defaults remain native.
@MainActor enum AppHost {
  #if SEVRA_UI_CATALOG
    static let allowsBackgroundServices = false
    static var ai = ProductAI(qualifying: CatalogInference())
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-catalog-" + UUID().uuidString)
    static var automationDirectory: URL? { root.appendingPathComponent("schedules") }
    static var events: [String] = []
    static func openPanel(for workbook: Workbook? = nil) -> NSOpenPanel {
      let panel = CatalogOpenPanel()
      panel.selection =
        workbook?.url.deletingLastPathComponent().appendingPathComponent("Quotes.csv")
        ?? Bundle.main.resourceURL?.appendingPathComponent("CatalogAssets/Quote.pdf")
      return panel
    }
    static func savePanel() -> NSSavePanel { CatalogSavePanel() }
    @discardableResult static func openExternal(_ url: URL) -> Bool {
      events.append("External open requested: " + url.lastPathComponent)
      return false
    }
    static func speech() -> SpeechInput { SpeechInput(driverFactory: { CatalogDictation() }) }
    static func dictationCleaner() -> (any DictationCleaner)? { CatalogDictationCleaner() }
    static func installed(at: URL) async -> Bool { false }
    static func setup(
      at: URL, reusing: URL?, cancellation: Cancellation,
      progress: @escaping @Sendable (String) -> Void
    ) async throws {
      progress("Catalog: model download simulated.")
      throw SevraError(
        "catalog_service", "Model setup is simulated in the catalog. No files were downloaded.")
    }
  #else
    static let allowsBackgroundServices = true
    static var ai: ProductAI { .shared }
    static var automationDirectory: URL? { nil }
    static func openPanel(for workbook: Workbook? = nil) -> NSOpenPanel { NSOpenPanel() }
    static func savePanel() -> NSSavePanel { NSSavePanel() }
    @discardableResult static func openExternal(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    static func speech() -> SpeechInput {
      SpeechInput(pausePlayback: { PlaybackRegistry.shared.pauseAll() })
    }
    /// The Mac's on-device model, when it has one. Without it dictation is kept as said.
    static func dictationCleaner() -> (any DictationCleaner)? {
      OnDeviceDictationCleaner.available ? OnDeviceDictationCleaner() : nil
    }
    static func installed(at url: URL) async -> Bool { await ai.installed(at: url) }
    static func setup(
      at url: URL, reusing source: URL?, cancellation: Cancellation,
      progress: @escaping @Sendable (String) -> Void
    ) async throws {
      try await ai.setup(at: url, reusing: source, cancellation: cancellation, progress: progress)
    }
  #endif
}

@MainActor extension AppHost {
  static func transcribe(
    _ book: Workbook, id: String, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void = { _ in }
  ) async throws {
    #if SEVRA_UI_CATALOG
      try cancellation.check()
      throw SevraError(
        "catalog_service",
        "File transcription is controlled in the catalog. No speech service or permission was requested."
      )
    #else
      try await book.transcribe(id, cancellation: cancellation, progress: progress)
    #endif
  }
  static func templateURL(_ name: String) -> URL? {
    let panel = savePanel()
    panel.nameFieldStringValue = name + ".sevraapp"
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }
}
