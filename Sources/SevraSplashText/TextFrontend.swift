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
  private var generationSuffixes: [Bool: [Int]] = [:]
  private var promptCache: [(key: Data, prompt: Prompt, bytes: Int)] = []
  private var promptCacheBytes = 0
  private var promptCacheHits = 0
  private static let promptCacheBudget = 8 * 1024 * 1024
  private let lock = NSLock()
  private var addedGrammarTokens: [UInt32: [UInt8]] = [:]
  private var addedLiterals: [String] = []
  private var grammarVocabularyCache: ByteVocabulary?
  private var outputSpecialTokens: Set<UInt32> = []
  public struct ByteVocabulary {
    public let lengths: [UInt32]
    public let bytes: [UInt8]
    let offsets: [Int]
  }
  public var templateIdentity: String { Self.sha256(Data(template.utf8)) }
  public static let vocabularySize: UInt32 = 248320
  public static let stopTokens: [UInt32] = [248044, 248046]

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
    let patchURL = try SplashRuntimeResources.resource(
      "template-patch", extension: "json", bundle: "Sevra_SevraSplashText")
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
    guard tokenizerData.decoder.type.string() == "ByteLevel" else {
      throw SplashError("Selected tokenizer byte decoder changed")
    }
    for entry in tokenizerData["addedTokens"].array(or: []) {
      guard let id = entry.id.integer(), id >= 0, id < Self.vocabularySize,
        let content = entry.content.string()
      else {
        throw SplashError("Selected tokenizer has an invalid added token")
      }
      // LLGuidance's HF adapter treats every added <...> token as special,
      // including the model's non-special tool and reasoning markers. Its C
      // tokenizer_json path differs, so supply this exact byte vocabulary.
      let special =
        entry.special.boolean(or: false)
        || (content.hasPrefix("<") && content.hasSuffix(">"))
      addedGrammarTokens[UInt32(id)] = (special ? [0xff] : []) + Array(content.utf8)
      if entry.special.boolean(or: false) { outputSpecialTokens.insert(UInt32(id)) }
      guard content.hasPrefix("<") else {
        throw SplashError("Selected tokenizer has an unsupported added token")
      }
      addedLiterals.append(content)
    }
    for (text, id) in [
      "<|endoftext|>": 248044, "<|im_end|>": 248046,
      "</think>": 248069, "<tool_call>": 248058,
    ] {
      guard tokenizer.convertTokenToId(text) == id,
        tokenizer.encode(text: text, addSpecialTokens: false) == [id]
      else {
        throw SplashError("Tokenizer special tokens do not match the native model")
      }
    }
    guard let eos = tokenizer.eosTokenId, Self.stopTokens.contains(UInt32(eos)) else {
      throw SplashError("Tokenizer EOS does not match the native model")
    }
    // Probe the pinned template's generation suffix once, as Splash does.
    // Re-tokenizing the entire occupied conversation to find this short suffix
    // doubles preparation work. Each full request still verifies its suffix.
    for thinking in [false, true] {
      var suffix: [Int]?
      for preserve in [false, true] {
        for canary: [Message] in [
          [["role": "user", "content": "Generation suffix probe."]],
          [["role": "system", "content": "Follow this probe."],
           ["role": "user", "content": "A different message: Bogotá 日本語."]],
        ] {
          func probe(_ generation: Bool) throws -> [Int] {
            try tokenizer.applyChatTemplate(
              messages: canary, chatTemplate: .literal(template), addGenerationPrompt: generation,
              truncation: false, maxLength: nil, tools: nil,
              additionalContext: ["enable_thinking": thinking, "preserve_thinking": preserve])
          }
          let without = try probe(false)
          let with = try probe(true)
          guard with.starts(with: without), with.count > without.count else {
            throw SplashError("Selected template has no stable generation suffix")
          }
          let candidate = Array(with.dropFirst(without.count))
          guard suffix == nil || suffix == candidate else {
            throw SplashError("Selected generation suffix changes with conversation history")
          }
          suffix = candidate
        }
      }
      generationSuffixes[thinking] = suffix
    }
  }

  public func prepare(
    messages: [Message], tools: [ToolSpec]? = nil,
    thinking: Bool = false, preserveThinking: Bool = false, contextLimit: Int = 8192
  ) throws -> Prompt {
    lock.lock()
    defer { lock.unlock() }
    guard !messages.isEmpty, messages.count <= 512, contextLimit > 0,
      contextLimit <= SplashWire.maxTokens
    else {
      throw SplashError("Invalid conversation or context limit")
    }
    var bytes = 0
    var nodes = 0
    var numericIdentity: [[String]] = []
    func account(_ value: any Sendable, depth: Int = 0) throws {
      nodes += 1
      guard depth <= 32, nodes <= 65536 else {
        throw SplashError("Conversation structure is too complex")
      }
      if let string = value as? String {
        bytes += string.utf8.count
      } else if let object = value as? [String: any Sendable] {
        for (key, child) in object.sorted(by: { $0.key < $1.key }) {
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
        // Foundation JSON can serialize 1 and 1.0 identically even when the
        // template renders their types differently. Preserve scalar identity
        // in the cache key, including signed zero and exact large integers.
        numericIdentity.append([
          String(reflecting: type(of: value)), String(cString: number.objCType),
          number.stringValue, String(number.doubleValue.bitPattern),
        ])
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
        message["content"] is String
      else {
        throw SplashError("Text frontend requires text message content and a supported role")
      }
      try account(message)
    }
    if let tools { try account(tools) }
    // The workbook's context planner and inference request may prepare the
    // same large envelope. Reuse only exact bytes, after all input checks, in
    // this frontend's bounded memory. Changed histories still render normally.
    // Splash likewise keeps a four-entry, 8 MiB tokenizer cache, though its
    // cache can also reuse message prefixes. No cache is written to disk.
    let cacheKey: Data? = bytes >= 4096
      ? try JSONSerialization.data(withJSONObject: [
        "messages": messages, "tools": tools as Any? ?? NSNull(),
        "thinking": thinking, "preserveThinking": preserveThinking,
        "numericIdentity": numericIdentity,
      ], options: [.sortedKeys]) : nil
    if let cacheKey, let index = promptCache.firstIndex(where: { $0.key == cacheKey }) {
      let cached = promptCache[index]
      guard cached.prompt.tokens.count <= contextLimit else {
        throw SplashError("Prompt exceeds the native context limit")
      }
      promptCache.remove(at: index)
      promptCache.append(cached)
      promptCacheHits += 1
      return cached.prompt
    }
    // swift-jinja represents JSON null through a boxed nil optional. NSNull
    // reaches its unsupported-object path, including in nested tool history.
    func templateValue(_ value: any Sendable) -> any Sendable {
      if value is NSNull { return Optional<String>.none as any Sendable }
      if let object = value as? [String: any Sendable] { return object.mapValues(templateValue) }
      if let array = value as? [any Sendable] { return array.map(templateValue) }
      return value
    }
    // Tool definitions are the host's own. Everything in a message is not.
    let templateMessages = messages.map(messageWithoutAddedLiterals).map {
      $0.mapValues(templateValue)
    }
    let templateTools = tools?.map { $0.mapValues(templateValue) }
    let context: [String: any Sendable] = [
      "enable_thinking": thinking, "preserve_thinking": preserveThinking,
    ]
    let tokens = try tokenizer.applyChatTemplate(
      messages: templateMessages, chatTemplate: .literal(template),
      addGenerationPrompt: true, truncation: false, maxLength: nil, tools: templateTools,
      additionalContext: context)
    guard tokens.count <= contextLimit, !tokens.isEmpty else {
      throw SplashError("Prompt exceeds the native context limit")
    }
    guard tokens.allSatisfy({ $0 >= 0 && $0 < Self.vocabularySize }) else {
      throw SplashError("Tokenizer produced an invalid token")
    }
    guard let suffix = generationSuffixes[thinking], tokens.suffix(suffix.count).elementsEqual(suffix)
    else { throw SplashError("Request does not end with the selected generation suffix") }
    let prompt = Prompt(tokens: tokens.map(UInt32.init), generationTokens: UInt32(suffix.count))
    if let cacheKey {
      let size = cacheKey.count + prompt.tokens.count * MemoryLayout<UInt32>.stride
      if size <= Self.promptCacheBudget {
        while !promptCache.isEmpty && (promptCache.count >= 4 || promptCacheBytes + size > Self.promptCacheBudget) {
          promptCacheBytes -= promptCache.removeFirst().bytes
        }
        promptCache.append((cacheKey, prompt, size))
        promptCacheBytes += size
      }
    }
    return prompt
  }

  /// The tokenizer matches added tokens anywhere in the rendered prompt, so a
  /// document could otherwise close its turn and open a system one. The template
  /// renders the real control tokens itself, after this pass. Text with no literal
  /// comes back unchanged, so ordinary prompts keep their exact tokens.
  private func withoutAddedLiterals(_ text: String) -> String {
    guard text.utf8.contains(UInt8(ascii: "<")) else { return text }
    // Literal options match code units as the tokenizer does. The default
    // comparison misses a token that a combining mark follows.
    return addedLiterals.reduce(text) {
      $0.replacingOccurrences(of: $1, with: "< " + $1.dropFirst(), options: .literal)
    }
  }
  /// The template closes tool and parameter names with its own ">", which could
  /// complete a literal that the name leaves open.
  private func nameWithoutAddedLiterals(_ name: String) -> String {
    var scalars = withoutAddedLiterals(name + ">").unicodeScalars
    scalars.removeLast()
    return String(scalars)
  }
  private func messageWithoutAddedLiterals(_ object: [String: any Sendable]) -> [String: any Sendable] {
    // Sorted so keys that collide here resolve the same way on every render.
    var result: [String: any Sendable] = [:]
    for (key, value) in object.sorted(by: { $0.key < $1.key }) {
      let name = nameWithoutAddedLiterals(key)
      guard result[name] == nil else { continue }
      if key == "name", let text = value as? String {
        result[name] = nameWithoutAddedLiterals(text)
      } else {
        result[name] = valueWithoutAddedLiterals(value)
      }
    }
    return result
  }
  private func valueWithoutAddedLiterals(_ value: any Sendable) -> any Sendable {
    if let text = value as? String { return withoutAddedLiterals(text) }
    if let object = value as? [String: any Sendable] { return messageWithoutAddedLiterals(object) }
    if let array = value as? [any Sendable] { return array.map(valueWithoutAddedLiterals) }
    return value
  }

  public var promptCacheStatistics: (entries: Int, bytes: Int, hits: Int) {
    lock.lock()
    defer { lock.unlock() }
    return (promptCache.count, promptCacheBytes, promptCacheHits)
  }

  public func decode(_ tokens: [UInt32], skipSpecialTokens: Bool = false) -> String {
    lock.lock()
    defer { lock.unlock() }
    return tokenizer.decode(tokens: tokens.map(Int.init), skipSpecialTokens: skipSpecialTokens)
  }
  /// Exact tokenization callback for the native grammar, without added BOS/EOS.
  public func encode(_ text: String) -> [UInt32] {
    lock.lock()
    defer { lock.unlock() }
    return tokenizer.encode(text: text, addSpecialTokens: false).map(UInt32.init)
  }
  /// A decoder owns only per-request buffers; its immutable vocabulary shares
  /// storage with the grammar frontend. Grammar-special markers still display
  /// unless the selected tokenizer itself marks them special.
  public func makeDecoder(stopSequences: [String] = []) throws -> SplashTextStream {
    let vocabulary = try grammarVocabulary()
    return try SplashTextStream(
      vocabulary: vocabulary, special: outputSpecialTokens,
      added: Set(addedGrammarTokens.keys), stopSequences: stopSequences)
  }
  /// Matches the pinned LLGuidance HF byte vocabulary, including padded special
  /// tokens. Ordinary token keys remain byte distinct in the maintained loader.
  public func grammarVocabulary() throws -> ByteVocabulary {
    lock.lock()
    defer { lock.unlock() }
    if let cached = grammarVocabularyCache { return cached }
    var map: [Unicode.Scalar: UInt8] = [:]
    var extra: UInt32 = 256
    for byte in UInt32(0)...255 {
      if (33...126).contains(byte) || (161...172).contains(byte) || (174...255).contains(byte) {
        map[Unicode.Scalar(byte)!] = UInt8(byte)
      } else {
        map[Unicode.Scalar(extra)!] = UInt8(byte)
        extra += 1
      }
    }
    var lengths: [UInt32] = []
    var bytes: [UInt8] = []
    var offsets = [0]
    lengths.reserveCapacity(Int(Self.vocabularySize))
    offsets.reserveCapacity(Int(Self.vocabularySize) + 1)
    for id in 0..<Self.vocabularySize {
      let value: [UInt8]
      if let added = addedGrammarTokens[id] {
        value = added
      } else if let label = tokenizer.convertIdToToken(Int(id)) {
        value = try label.unicodeScalars.map {
          guard let byte = map[$0] else { throw SplashError("Tokenizer byte mapping changed") }
          return byte
        }
      } else {
        value = [0xff] + Array("<[\(id)]>".utf8)
        outputSpecialTokens.insert(id)
      }
      lengths.append(UInt32(value.count))
      bytes += value
      offsets.append(bytes.count)
    }
    let vocabulary = ByteVocabulary(lengths: lengths, bytes: bytes, offsets: offsets)
    grammarVocabularyCache = vocabulary
    return vocabulary
  }
  private static func sha256(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}
