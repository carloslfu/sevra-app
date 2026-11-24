import CryptoKit
import Darwin
import Foundation
import Metal
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashText

enum NativeProductResources {
  private struct Manifest: Decodable {
    let schemaVersion: Int
    let release: String
    let commit: String
    let engineFiles: [String: String]
    let grammarSHA256: String
  }
  private static var resourceRoot: URL {
    SplashRuntimeResources.resourceRoot
  }
  private static func layout() throws -> (Manifest, URL, URL) {
    let data = try Data(contentsOf: resourceRoot.appendingPathComponent("native-runtime.json"))
    try require(data.count < 16384, "resources", "The native runtime manifest is oversized.")
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)
    try require(
      manifest.schemaVersion == 1 && manifest.release == "1.7.1"
        && manifest.commit == "1988a72f26a6031127efc29f861bfb46d36286c4"
        && Set(manifest.engineFiles.keys) == ["splash", "splash.metallib", "host-step.metallib"],
      "resources", "The installed runtime does not match this version of Sevra.")
    let contents = SplashRuntimeResources.installedBundleContents
    let executable = SplashRuntimeResources.executableDirectory
    let engine =
      contents?.appendingPathComponent("Helpers/Splash/splash")
      ?? executable.appendingPathComponent("NativeRuntime/engine/splash")
    let grammar =
      contents?.appendingPathComponent("Frameworks/libllguidance.dylib")
      ?? executable.appendingPathComponent("NativeRuntime/libllguidance.dylib")
    return (manifest, engine, grammar)
  }
  static func configuration(modelsRoot: URL) throws -> NativeWorkbookModel.Configuration {
    try SplashModelSetup.checkHardware()
    let (manifest, engine, grammar) = try layout()
    // The two capacities were compared at the same engine budget on a 48 GiB Mac.
    let context: ContextBudget.Profile =
      ProcessInfo.processInfo.physicalMemory >= 48 * 1024 * 1024 * 1024
      ? .evaluation64K : .evaluation32K
    return .init(
      engine: engine, engineFiles: manifest.engineFiles, grammarLibrary: grammar,
      grammarSHA256: manifest.grammarSHA256, modelsRoot: modelsRoot,
      memoryBytes: 12 * 1024 * 1024 * 1024,
      contextBudget: .init(profile: context), reasoning: .bounded512,
      modelLayout: .installed, contextMaintenanceEnabled: true)
  }
  /// What a prepared header has to match in this build, known without the model.
  static func headerIdentity() throws -> PromptHeader.Identity {
    let (manifest, _, _) = try layout()
    return try .init(
      engineSHA256: manifest.engineFiles["splash"] ?? "",
      activations: NativeWorkbookModel.Activations.bf16.rawValue, reasoning: .bounded512)
  }
  /// Present and matching, absent or mismatched. A development build may have none.
  static func headerState() throws -> PromptHeader.State {
    PromptHeader.state(at: PromptHeader.location(), identity: try headerIdentity())
  }
  /// `sevra header make`: finds the header for this build in `output`, or makes it there with
  /// the installed model and this build's engine and launch values.
  static func makeHeader(output: URL, modelsRoot: URL, progress: (String) -> Void) throws -> Value {
    let identity = try headerIdentity()
    let configuration = try Self.configuration(modelsRoot: modelsRoot)
    let pack = try SplashModelPack.selected()
    guard
      FileManager.default.fileExists(
        atPath: modelsRoot.appendingPathComponent(pack.name + "/model.json").path)
    else {
      if case .present(let folder, let manifest) = PromptHeader.state(at: output, identity: identity) {
        return report(folder, manifest, made: false)
      }
      throw SevraError(
        "model_missing",
        "The local model is not installed, so no prompt header can be made. Download it in Sevra's Model Settings or with sevra model-setup, then run this again."
      )
    }
    let assembly = try SplashModelPreparation.installed(pack: pack, modelsRoot: modelsRoot)
    if case .present(let folder, let manifest) = PromptHeader.state(at: output, identity: identity),
      manifest.assemblyKey == PromptHeader.assemblyKey(assembly)
    {
      return report(folder, manifest, made: false)
    }
    // The app's own lock: no Sevra process loads a model while this one holds it.
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/Sevra")
    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
    let lock = Darwin.open(
      support.appendingPathComponent("inference.lock").path,
      O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    try require(lock >= 0, "model_lock", "Cannot open the local inference lock.")
    defer { Darwin.close(lock) }
    try require(
      flock(lock, LOCK_EX | LOCK_NB) == 0, "model_busy",
      "Another Sevra process has the model loaded. Quit it or unload the model, then try again.")
    let frontend = try SplashTextFrontend(modelFolder: assembly.appendingPathComponent("tokenizer"))
    let (folder, manifest) = try PromptHeader.make(
      identity: identity, output: output, engine: configuration.engine, assembly: assembly,
      frontend: frontend, reasoning: configuration.reasoning,
      activations: configuration.activations.rawValue,
      contextTokens: configuration.contextBudget.contextTokens,
      memoryBytes: configuration.memoryBytes, progress: progress)
    return report(folder, manifest, made: true)
  }
  private static func report(_ folder: URL, _ manifest: PromptHeader.Manifest, made: Bool) -> Value {
    .object([
      "folder": .string(folder.path), "made": .bool(made), "inputs": .string(manifest.inputs),
      "tokens": .number(Double(manifest.tokens)), "bytes": .number(Double(manifest.dataBytes)),
      "cacheName": .string(manifest.cacheName),
    ])
  }
  static func check(validateMetal: Bool) throws -> Value {
    let (manifest, engine, grammar) = try layout()
    for (name, hash) in manifest.engineFiles {
      try verify(engine.deletingLastPathComponent().appendingPathComponent(name), hash)
    }
    try verify(grammar, manifest.grammarSHA256)
    let pack = try SplashModelPack.selected()
    try pack.validate()
    for (name, bundle) in [
      ("template-patch", "Sevra_SevraSplashText"),
      ("json-slices", "Sevra_SevraSplashGrammar"),
    ] {
      _ = try SplashRuntimeResources.resource(name, extension: "json", bundle: bundle)
    }
    let hub = resourceRoot.appendingPathComponent("swift-transformers_Hub.bundle")
    try require(
      FileManager.default.fileExists(atPath: hub.path), "resources",
      "Tokenizer resources are missing.")
    guard let library = dlopen(grammar.path, RTLD_NOW | RTLD_LOCAL) else {
      throw SevraError("resources", "The installed grammar library cannot be loaded.")
    }
    defer { dlclose(library) }
    guard let symbol = dlsym(library, "llg_get_version") else {
      throw SevraError("resources", "The installed grammar library is incompatible.")
    }
    let version = unsafeBitCast(symbol, to: (@convention(c) () -> UnsafePointer<CChar>?).self)
    try require(
      version().map { String(cString: $0).contains("llguidance@1.8.0") } == true,
      "resources", "The installed grammar version is incompatible.")
    var kernels = 0
    if validateMetal {
      try SplashModelSetup.checkHardware()
      guard let device = MTLCreateSystemDefaultDevice() else {
        throw SevraError("resources", "A Metal-capable device is required.")
      }
      for name in ["splash.metallib", "host-step.metallib"] {
        let loaded = try device.makeLibrary(
          URL: engine.deletingLastPathComponent().appendingPathComponent(name))
        try require(
          !loaded.functionNames.isEmpty, "resources", "An installed Metal library is empty.")
        kernels += loaded.functionNames.count
      }
    }
    return .object([
      "backend": .string("splash"), "runtimeDigests": .bool(true),
      "tokenizerResources": .bool(true), "grammarLibrary": .bool(true),
      "metalLibrary": validateMetal ? .bool(true) : .null,
      "kernelCount": .number(Double(kernels)), "selectedModel": .string(pack.name),
      "promptHeader": try headerState().report,
    ])
  }
  private static func verify(_ file: URL, _ digest: String) throws {
    try require(digest.count == 64, "resources", "A runtime digest is missing.")
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hash = SHA256()
    var count = 0
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty {
      count += bytes.count
      try require(count <= 128 * 1024 * 1024, "resources", "A native runtime file is oversized.")
      hash.update(data: bytes)
    }
    try require(
      hash.finalize().map { String(format: "%02x", $0) }.joined() == digest,
      "resources", "Installed runtime verification failed: " + file.lastPathComponent)
  }
}
