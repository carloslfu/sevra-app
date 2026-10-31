#if SEVRA_NATIVE_CANDIDATE
  import CryptoKit
  import Darwin
  import Foundation
  import Metal
  import SevraAI
  import SevraCore
  import SevraNativeAI
  import SevraSplash

  enum NativeProductResources {
    private struct Manifest: Decodable {
      let schemaVersion: Int
      let release: String
      let commit: String
      let engineFiles: [String: String]
      let grammarSHA256: String
    }
    private static var executable: URL {
      (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
        .resolvingSymlinksInPath().deletingLastPathComponent()
    }
    private static var resourceRoot: URL {
      Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.resourceURL! : executable
    }
    private static func layout() throws -> (Manifest, URL, URL) {
      let data = try Data(contentsOf: resourceRoot.appendingPathComponent("native-runtime.json"))
      try require(data.count < 16384, "resources", "The native runtime manifest is oversized.")
      let manifest = try JSONDecoder().decode(Manifest.self, from: data)
      try require(
        manifest.schemaVersion == 1 && manifest.release == "1.4.1"
          && manifest.commit == "1744cfafee415fb463b289449cec59a864e768e9"
          && Set(manifest.engineFiles.keys) == ["splash", "splash.metallib", "host-step.metallib"],
        "resources", "The installed runtime does not match this version of Sevra.")
      let app = Bundle.main.bundleURL.pathExtension == "app"
      let engine =
        app
        ? executable.deletingLastPathComponent().appendingPathComponent("Helpers/Splash/splash")
        : executable.appendingPathComponent("NativeRuntime/engine/splash")
      let grammar =
        app
        ? executable.deletingLastPathComponent().appendingPathComponent(
          "Frameworks/libllguidance.dylib")
        : executable.appendingPathComponent("NativeRuntime/libllguidance.dylib")
      return (manifest, engine, grammar)
    }
    static func configuration(modelsRoot: URL) throws -> NativeWorkbookModel.Configuration {
      try SplashModelSetup.checkHardware()
      let (manifest, engine, grammar) = try layout()
      return .init(
        engine: engine, engineFiles: manifest.engineFiles, grammarLibrary: grammar,
        grammarSHA256: manifest.grammarSHA256, modelsRoot: modelsRoot,
        memoryBytes: 12 * 1024 * 1024 * 1024,
        contextBudget: .init(profile: .evaluation32K), reasoning: .bounded512,
        modelLayout: .installed, contextMaintenanceEnabled: true)
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
        "backend": .string("splash-native-candidate"), "runtimeDigests": .bool(true),
        "tokenizerResources": .bool(true), "grammarLibrary": .bool(true),
        "metalLibrary": validateMetal ? .bool(true) : .null,
        "kernelCount": .number(Double(kernels)), "selectedModel": .string(pack.name),
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
#endif
