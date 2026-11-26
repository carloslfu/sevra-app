import CoreFoundation
import CryptoKit
import Foundation
import Hub
import Jinja
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
  private var systemPrefix: (key: Data, tokens: [Int])?
  private var promptCacheBytes = 0
  private var promptCacheHits = 0
  private static let promptCacheBudget = 8 * 1024 * 1024
  private let lock = NSLock()
  private var addedGrammarTokens: [UInt32: [UInt8]] = [:]
  /// Added tokens by their text, and each one's text after its first character, `<`.
  private var addedIDs: [String: Int] = [:]
  private var addedRests: [[Unicode.Scalar]] = []
  /// Splits a rendered prompt at every whole added token, the longest first, as the tokenizer does.
  private var addedSplit: NSRegularExpression?
  /// A text no request can hold, drawn when the frontend loads. `quote` sets it after the `<` of
  /// an added token that begins in text the host did not write, as Splash 1.7.3's
  /// `PromptTokenizer.quote` does, so that token reaches the model as its characters.
  private let quoteMark = "__sevra_quoted_" + (0..<16).map { _ in
    String(format: "%02x", UInt8.random(in: 0...255))
  }.joined() + "__"
  /// The same normalizer, pre-tokenizer and model without the added tokens: how a part of a
  /// prompt between two of the template's own tokens encodes. It keeps one added token, the
  /// mark, which no part holds, as a tokenizer without any splits its input at every character.
  private let plainTokenizer: any Tokenizer
  /// The tokenizer's own split pattern, matched over scalars as the reference tokenizer does.
  private var pieceSplit: NSRegularExpression?
  private let compiledTemplate: Template
  private var specialContext: [String: Jinja.Value] = [:]
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
    var plainData = tokenizerData.dictionary() ?? [:]
    plainData["added_tokens"] = Config([
      Config([
        "id": Config(Int(Self.stopTokens[0])), "content": Config(quoteMark),
        "special": Config(true), "lstrip": Config(false), "rstrip": Config(false),
        "normalized": Config(false), "single_word": Config(false),
      ] as [String: Config])
    ])
    plainTokenizer = try AutoTokenizer.from(
      tokenizerConfig: tokenizerConfig, tokenizerData: Config(plainData), strict: true)
    compiledTemplate = try Template(adapted, with: .init(lstripBlocks: true, trimBlocks: true))
    // As swift-transformers' applyChatTemplate gives a template the tokenizer's special tokens.
    for (key, value) in tokenizerConfig.dictionary(or: [:])
    where ["bos_token", "eos_token", "unk_token", "sep_token", "pad_token", "cls_token",
      "mask_token", "additional_special_tokens"].contains(key.string) && !value.isNull()
    {
      if let text = value.string() {
        specialContext[key.string] = .string(text)
      } else if let content = value.dictionary()?["content"]?.string() {
        specialContext[key.string] = .string(content)
      } else if let texts: [String] = value.get() {
        specialContext[key.string] = .array(texts.map { .string($0) })
      }
    }
    guard tokenizerData.decoder.type.string() == "ByteLevel" else {
      throw SplashError("Selected tokenizer byte decoder changed")
    }
    // `encodeText` cuts text at this pattern's pieces, which holds only for an NFC normalizer,
    // a split that keeps each piece, and a byte-level step that does not split again.
    let steps = tokenizerData.preTokenizer.pretokenizers.array(or: [])
    guard tokenizerData.normalizer.type.string() == "NFC",
      tokenizerData.preTokenizer.type.string() == "Sequence", steps.count == 2,
      steps[0].type.string() == "Split", steps[0].behavior.string() == "Isolated",
      !steps[0].invert.boolean(or: false), let pattern = steps[0].pattern.Regex.string(),
      steps[1].type.string() == "ByteLevel", !steps[1].useRegex.boolean(or: true),
      !steps[1].addPrefixSpace.boolean(or: true)
    else {
      throw SplashError("Selected tokenizer normalizer or pre-tokenizer changed")
    }
    pieceSplit = try NSRegularExpression(pattern: pattern)
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
      guard content.hasPrefix("<"), content.unicodeScalars.count >= 2,
        !content.contains(quoteMark), !quoteMark.contains(content)
      else {
        throw SplashError("Selected tokenizer has an unsupported added token")
      }
      addedIDs[content] = id
      addedRests.append(Array(content.unicodeScalars.dropFirst()))
    }
    addedSplit = try NSRegularExpression(
      pattern: addedIDs.keys.sorted { $0.utf16.count > $1.utf16.count }
        .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|"))
    // The part encoder reads ordinary text as the tokenizer does, and an added token's text as
    // its characters.
    for probe in ["Quarterly report: Café, 日本語 and 18 bolts.\n", "a < b <b> x<"] {
      guard plainTokenizer.encode(text: probe, addSpecialTokens: false)
        == tokenizer.encode(text: probe, addSpecialTokens: false)
      else { throw SplashError("Tokenizer without added tokens encodes ordinary text differently") }
    }
    guard !plainTokenizer.encode(text: "<|im_start|>", addSpecialTokens: false).contains(248045)
    else { throw SplashError("Tokenizer without added tokens still reads them") }
    for (text, id) in [
      "<|endoftext|>": 248044, "<|im_start|>": 248045, "<|im_end|>": 248046,
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
            try render(
              canary, tools: nil, generation: generation, thinking: thinking,
              preserveThinking: preserve)
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
    thinking: Bool = false, preserveThinking: Bool = false, contextLimit: Int = 8192,
    reuseSystemPrefix: Bool = false
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
    let messageNumberCount = numericIdentity.count
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
      // Tool history comes from JSONSerialization, and swift-jinja reads any NSNumber as an
      // Int, which would show true as 1 and 2.0 as 2.
      if let number = value as? NSNumber {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        if ["f", "d"].contains(String(cString: number.objCType)) { return number.doubleValue }
      }
      return value
    }
    // As Splash 1.7.3, every text the template is given is quoted, messages and tool
    // definitions alike: an added token one spells reaches the model as its characters.
    let templateMessages = messages.map(quoteObject).map { $0.mapValues(templateValue) }
    let templateTools = tools?.map(quoteObject).map { $0.mapValues(templateValue) }
    func render(_ source: [Message], _ definitions: [ToolSpec]?) throws -> [Int] {
      try self.render(
        source, tools: definitions, generation: true, thinking: thinking,
        preserveThinking: preserveThinking)
    }
    // Workbook headers contain only host policy and schemas. The next role starts with
    // a verified special token, so tokenization cannot merge across the join.
    var headerKey: Data?
    if reuseSystemPrefix, let tools, messages[0]["role"] as? String == "system",
      let content = messages[0]["content"] as? String, messages.count > 1,
      messages.dropFirst().contains(where: { $0["role"] as? String == "user" })
    {
      headerKey = try JSONSerialization.data(withJSONObject: [
        "content": content, "tools": tools, "numbers": Array(numericIdentity.dropFirst(messageNumberCount)),
      ], options: [.sortedKeys])
    }
    let tokens: [Int]
    if let headerKey, let cached = systemPrefix, cached.key == headerKey {
      tokens = cached.tokens + (try render(Array(templateMessages.dropFirst()), nil))
    } else {
      tokens = try render(templateMessages, templateTools)
      if let headerKey, headerKey.count <= 1024 * 1024,
        let end = tokens.firstIndex(of: 248046),
        let next = tokens[(end + 1)...].firstIndex(of: 248045)
      {
        systemPrefix = (headerKey, Array(tokens[..<next]))
      }
    }
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

  /// The tokens of the template rendered with the context swift-transformers' applyChatTemplate
  /// gives it. Only the template's own tokens are added tokens; each text between two of them,
  /// its marks taken out, encodes as ordinary text (`PromptTokenizer.tokens`).
  private func render(
    _ messages: [Message], tools: [ToolSpec]?, generation: Bool, thinking: Bool,
    preserveThinking: Bool
  ) throws -> [Int] {
    var context: [String: Jinja.Value] = [
      "messages": .array(try messages.map { try Value(any: $0) }),
      "add_generation_prompt": .boolean(generation),
      "enable_thinking": .boolean(thinking), "preserve_thinking": .boolean(preserveThinking),
    ]
    if let tools { context["tools"] = .array(try tools.map { try Value(any: $0) }) }
    for (key, value) in specialContext { context[key] = value }
    return try tokensOf(try compiledTemplate.render(context))
  }

  /// `text` with each U+0000 as U+FFFD, and the mark after every `<` where an added token
  /// begins: one the text spells whole, or one its end cuts off, which what the template writes
  /// next could complete (Splash 1.7.3's `PromptTokenizer.quote`). Scalars, not characters, as
  /// the tokenizer reads them: a combining mark after `>` must not hide a token.
  private func quote(_ text: String) -> String {
    guard text.unicodeScalars.contains(where: { $0 == "<" || $0 == "\u{0}" }) else { return text }
    let scalars = text.unicodeScalars.map { $0 == "\u{0}" ? "\u{FFFD}" : $0 }
    var result = String.UnicodeScalarView()
    for (index, scalar) in scalars.enumerated() {
      result.append(scalar)
      guard scalar == "<" else { continue }
      let begins = addedRests.contains { rest in
        var matched = 0
        while matched < rest.count, index + 1 + matched < scalars.count,
          scalars[index + 1 + matched] == rest[matched]
        {
          matched += 1
        }
        return matched == rest.count || index + 1 + matched == scalars.count
      }
      if begins { result.append(contentsOf: quoteMark.unicodeScalars) }
    }
    return String(result)
  }
  private func quoteObject(_ object: [String: any Sendable]) -> [String: any Sendable] {
    // Sorted so keys that collide here resolve the same way on every render.
    var result: [String: any Sendable] = [:]
    for (key, value) in object.sorted(by: { $0.key < $1.key }) {
      let name = quote(key)
      guard result[name] == nil else { continue }
      result[name] = quoteValue(value)
    }
    return result
  }
  private func quoteValue(_ value: any Sendable) -> any Sendable {
    if let text = value as? String { return quote(text) }
    if let object = value as? [String: any Sendable] { return quoteObject(object) }
    if let array = value as? [any Sendable] { return array.map(quoteValue) }
    return value
  }
  /// The tokens of a rendered prompt: each whole added token the template wrote, and between
  /// them the text without its marks, as ordinary text (`PromptTokenizer.tokens`).
  private func tokensOf(_ rendered: String) throws -> [Int] {
    guard let addedSplit else { throw SplashError("Selected tokenizer has no added tokens") }
    let text = rendered as NSString
    var tokens: [Int] = []
    var start = 0
    func plain(_ end: Int) throws {
      guard end > start else { return }
      let part = text.substring(with: NSRange(location: start, length: end - start))
        .replacingOccurrences(of: quoteMark, with: "")
      if !part.isEmpty { tokens += try encodeText(part) }
    }
    for match in addedSplit.matches(in: rendered, range: NSRange(location: 0, length: text.length)) {
      try plain(match.range.location)
      tokens.append(addedIDs[text.substring(with: match.range)]!)
      start = match.range.location + match.range.length
    }
    try plain(text.length)
    return tokens
  }
  /// Ordinary text as the reference tokenizer encodes it. swift-transformers finds the split
  /// pattern's pieces with Foundation's search, which reads characters, not scalars: a
  /// character of several scalars can move a piece's end, so `❤️<b>` splits as `❤️<` and `b`
  /// where the reference has `❤️` and `<b`. Text whose characters are single scalars reads the
  /// same both ways. Other text is cut around each piece that holds a character of several
  /// scalars, at the pattern's own boundaries, and each run encodes alone.
  private func encodeText(_ text: String) throws -> [Int] {
    let normalized = text.precomposedStringWithCanonicalMapping
    guard normalized.unicodeScalars.count != normalized.count else {
      return plainTokenizer.encode(text: normalized, addSpecialTokens: false)
    }
    guard let pieceSplit else { throw SplashError("Selected tokenizer has no split pattern") }
    let units = normalized as NSString
    var wide: [Range<Int>] = []
    var index = normalized.startIndex
    while index < normalized.endIndex {
      let after = normalized.index(after: index)
      if normalized[index].unicodeScalars.count > 1 {
        wide.append(index.utf16Offset(in: normalized)..<after.utf16Offset(in: normalized))
      }
      index = after
    }
    var cuts: [Int] = []
    var next = 0
    for match in pieceSplit.matches(in: normalized, range: NSRange(location: 0, length: units.length)) {
      let piece = match.range.location..<(match.range.location + match.range.length)
      while next < wide.count, wide[next].upperBound <= piece.lowerBound { next += 1 }
      if next < wide.count, wide[next].overlaps(piece) {
        cuts += [piece.lowerBound, piece.upperBound]
      }
    }
    var tokens: [Int] = []
    var start = 0
    for end in cuts + [units.length] where end > start {
      tokens += plainTokenizer.encode(
        text: units.substring(with: NSRange(location: start, length: end - start)),
        addSpecialTokens: false)
      start = end
    }
    return tokens
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
