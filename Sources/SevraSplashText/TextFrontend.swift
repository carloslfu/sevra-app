import CryptoKit
import Foundation
import Hub
import SevraSplash
import Tokenizers

/// Native text frontend for the one pinned model. Call from an inference worker.
/// Workbook dictionaries use sorted keys, including historical tool arguments.
/// Images and arbitrary templates are deliberately outside this adapter.
public final class SplashTextFrontend {
  public struct Prompt: Sendable {
    public let tokens: [UInt32]
    public let generationTokens: UInt32
  }
  private struct Patch: Decodable {
    let originalSHA256: String
    let patchedSHA256: String
    let before: String
    let after: String
  }
  private let tokenizer: any Tokenizer
  private let template: String

  public init(modelFolder: URL) throws {
    let pack = try SplashModelPack.selected()
    func readVerified(_ name: String) throws -> Data {
      guard let file = pack.target.files.first(where: { $0.path == name }),
        file.bytes < 32 * 1024 * 1024
      else {
        throw SplashError("Unknown tokenizer resource")
      }
      let handle = try FileHandle(forReadingFrom: modelFolder.appendingPathComponent(name))
      defer { try? handle.close() }
      var bytes = Data()
      while let part = try handle.read(upToCount: 1024 * 1024), !part.isEmpty {
        guard bytes.count + part.count <= file.bytes else {
          throw SplashError("Tokenizer resource is oversized")
        }
        bytes.append(part)
      }
      guard bytes.count == file.bytes, Self.sha256(bytes) == file.sha256 else {
        throw SplashError("Tokenizer resource does not match the selected model: " + name)
      }
      return bytes
    }
    let configuration = try readVerified("tokenizer_config.json")
    let vocabulary = try readVerified("tokenizer.json")
    let source = try readVerified("chat_template.jinja")
    guard let patchURL = Bundle.module.url(forResource: "template-patch", withExtension: "json")
    else {
      throw SplashError("Selected template adaptation is missing")
    }
    let patch = try JSONDecoder().decode(Patch.self, from: Data(contentsOf: patchURL))
    let original = String(decoding: source, as: UTF8.self)
    guard Self.sha256(source) == patch.originalSHA256,
      original.components(separatedBy: patch.before).count == 2
    else {
      throw SplashError("Selected chat template changed")
    }
    let adapted = original.replacingOccurrences(of: patch.before, with: patch.after)
    guard Self.sha256(Data(adapted.utf8)) == patch.patchedSHA256 else {
      throw SplashError("Selected template adaptation is invalid")
    }
    template = adapted
    // Use the maintained yyjson-backed loader, preserving byte-distinct vocabulary keys.
    // Load local files only. Recheck exact bytes to detect changes between verification and parsing.
    let hub = HubApi.shared
    let tokenizerConfig = try hub.configuration(
      fileURL: modelFolder.appendingPathComponent("tokenizer_config.json"))
    let tokenizerData = try hub.configuration(
      fileURL: modelFolder.appendingPathComponent("tokenizer.json"))
    guard try readVerified("tokenizer_config.json") == configuration,
      try readVerified("tokenizer.json") == vocabulary
    else {
      throw SplashError("Tokenizer changed while loading")
    }
    tokenizer = try AutoTokenizer.from(
      tokenizerConfig: tokenizerConfig, tokenizerData: tokenizerData, strict: true)
  }

  public func prepare(
    messages: [Message], tools: [ToolSpec]? = nil,
    thinking: Bool = false, preserveThinking: Bool = false, contextLimit: Int = 8192
  ) throws -> Prompt {
    guard !messages.isEmpty, messages.count <= 512, contextLimit > 0,
      contextLimit <= SplashWire.maxTokens
    else {
      throw SplashError("Invalid conversation or context limit")
    }
    var bytes = 0
    var nodes = 0
    func account(_ value: any Sendable, depth: Int = 0) throws {
      nodes += 1
      guard depth <= 32, nodes <= 65536 else {
        throw SplashError("Conversation structure is too complex")
      }
      if let string = value as? String {
        bytes += string.utf8.count
      } else if let object = value as? [String: any Sendable] {
        for (key, child) in object {
          bytes += key.utf8.count
          try account(child, depth: depth + 1)
        }
      } else if let array = value as? [any Sendable] {
        for child in array { try account(child, depth: depth + 1) }
      } else if let number = value as? NSNumber {
        guard number.doubleValue.isFinite else {
          throw SplashError("Conversation has a non-finite number")
        }
        bytes += 32
      } else if value is NSNull {
        bytes += 4
      } else {
        throw SplashError("Conversation contains an unsupported value")
      }
      guard bytes <= 2 * 1024 * 1024 else {
        throw SplashError("Conversation exceeds the preparation limit")
      }
    }
    for message in messages {
      guard let role = message["role"] as? String,
        ["system", "user", "assistant", "tool"].contains(role),
        let content = message["content"] as? String
      else {
        throw SplashError("Text frontend requires text message content and a supported role")
      }
      _ = content
      try account(message)
    }
    if let tools { try account(tools) }
    let context: [String: any Sendable] = [
      "enable_thinking": thinking, "preserve_thinking": preserveThinking,
    ]
    func render(_ generation: Bool) throws -> [Int] {
      try tokenizer.applyChatTemplate(
        messages: messages, chatTemplate: .literal(template),
        addGenerationPrompt: generation, truncation: false, maxLength: nil, tools: tools,
        additionalContext: context)
    }
    let tokens = try render(true)
    guard tokens.count <= contextLimit, !tokens.isEmpty else {
      throw SplashError("Prompt exceeds the native context limit")
    }
    guard tokens.allSatisfy({ $0 >= 0 && $0 <= Int(UInt32.max) }) else {
      throw SplashError("Tokenizer produced an invalid token")
    }
    let without = try render(false)
    let prefix = tokens.starts(with: without) ? tokens.count - without.count : 0
    return Prompt(tokens: tokens.map(UInt32.init), generationTokens: UInt32(prefix))
  }

  public func decode(_ tokens: [UInt32], skipSpecialTokens: Bool = false) -> String {
    tokenizer.decode(tokens: tokens.map(Int.init), skipSpecialTokens: skipSpecialTokens)
  }
  private static func sha256(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
