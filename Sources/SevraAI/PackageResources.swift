import Foundation
import Hub
import Metal
import SevraCore

/// Checks installed resources and explicit local tokenizer configuration without loading weights.
public enum PackageResources {
  public static func check() async throws -> Value {
    let resourceRoot =
      Bundle.main.bundleURL.pathExtension == "app"
      ? Bundle.main.resourceURL! : Bundle.main.bundleURL
    let bundle = resourceRoot.appendingPathComponent("swift-transformers_Hub.bundle")
    try require(
      FileManager.default.fileExists(atPath: bundle.path), "resources",
      "Tokenizer resources are missing from the installed product.")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-resource-check-" + identifier())
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(#"{"model_type":"gpt2"}"#.utf8).write(to: folder.appendingPathComponent("config.json"))
    try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer.json"))
    // The qualified Fast pack always supplies tokenizer_class. Do not invoke the
    // upstream generic fallback, whose SwiftPM accessor assumes a flat executable.
    try Data(#"{"tokenizer_class":"GPT2Tokenizer"}"#.utf8).write(
      to: folder.appendingPathComponent("tokenizer_config.json"))
    let config = try await LanguageModelConfigurationFromHub(modelFolder: folder).tokenizerConfig
    try require(
      config?.tokenizerClass?.string() == "GPT2Tokenizer", "resources",
      "Explicit local tokenizer configuration did not resolve.")
    guard let executable = Bundle.main.executableURL, let device = MTLCreateSystemDefaultDevice()
    else { throw SevraError("metal", "A Metal-capable device is required.") }
    let library = try device.makeLibrary(
      URL: executable.deletingLastPathComponent().appendingPathComponent("mlx.metallib"))
    try require(!library.functionNames.isEmpty, "metal", "The Metal kernel library is empty.")
    return .object([
      "tokenizerResources": .bool(true), "metalLibrary": .bool(true),
      "kernelCount": .number(Double(library.functionNames.count)),
    ])
  }
}
