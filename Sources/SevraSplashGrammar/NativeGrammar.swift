import CLLGuidance
import CryptoKit
import Darwin
import Foundation
import SevraSplash
import SevraSplashText

/// The pinned native library stays optional while the Splash candidate qualifies.
/// Only pass the trusted, hash-verified application/development library, never a
/// path supplied by a workbook, model response or imported document.
private final class GuidanceAPI {
  private let handle: UnsafeMutableRawPointer
  let newTokenizer:
    @convention(c) (UnsafePointer<LlgTokenizerInitV2>?, UnsafeMutablePointer<CChar>?, Int) ->
      OpaquePointer?
  let freeTokenizer: @convention(c) (OpaquePointer?) -> Void
  let defaults: @convention(c) (UnsafeMutablePointer<LlgConstraintInit>?, OpaquePointer?) -> Void
  let newMatcher:
    @convention(c) (UnsafePointer<LlgConstraintInit>?, UnsafePointer<CChar>?, UnsafePointer<CChar>?)
      -> OpaquePointer?
  let freeMatcher: @convention(c) (OpaquePointer?) -> Void
  let clone: @convention(c) (OpaquePointer?) -> OpaquePointer?
  let error: @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
  let maskBytes: @convention(c) (OpaquePointer?) -> Int
  let compute: @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt32>?, Int) -> Int32
  let consume: @convention(c) (OpaquePointer?, UnsafePointer<UInt32>?, Int) -> Int32
  let consumeOne: @convention(c) (OpaquePointer?, UInt32) -> Int32
  let validate: @convention(c) (OpaquePointer?, UnsafePointer<UInt32>?, Int) -> Int32
  let accepting: @convention(c) (OpaquePointer?) -> Bool
  let stopped: @convention(c) (OpaquePointer?) -> Bool

  init(library: URL, expectedSHA256: String) throws {
    guard library.isFileURL, expectedSHA256.count == 64 else {
      throw SplashError("Native grammar library identity is missing")
    }
    let data = try Data(contentsOf: library, options: [.mappedIfSafe])
    guard data.count <= 32 * 1024 * 1024,
      SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedSHA256
    else { throw SplashError("Native grammar library verification failed") }
    guard let loaded = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else {
      throw SplashError("Cannot load the native grammar library")
    }
    func symbol<T>(_ name: String, _: T.Type = T.self) throws -> T {
      guard let address = dlsym(loaded, name) else {
        throw SplashError("Native grammar library is missing a required function")
      }
      return unsafeBitCast(address, to: T.self)
    }
    do {
      let version: @convention(c) () -> UnsafePointer<CChar>? = try symbol("llg_get_version")
      guard let value = version(), String(cString: value).contains("llguidance@1.8.0") else {
        throw SplashError("Native grammar version does not match the integration pin")
      }
      newTokenizer = try symbol("llg_new_tokenizer_v2")
      freeTokenizer = try symbol("llg_free_tokenizer")
      defaults = try symbol("llg_constraint_init_set_defaults")
      newMatcher = try symbol("llg_new_matcher")
      freeMatcher = try symbol("llg_free_matcher")
      clone = try symbol("llg_clone_matcher")
      error = try symbol("llg_matcher_get_error")
      maskBytes = try symbol("llg_matcher_get_mask_byte_size")
      compute = try symbol("llg_matcher_compute_mask_into")
      consume = try symbol("llg_matcher_consume_tokens")
      consumeOne = try symbol("llg_matcher_consume_token")
      validate = try symbol("llg_matcher_validate_tokens")
      accepting = try symbol("llg_matcher_is_accepting")
      stopped = try symbol("llg_matcher_is_stopped")
      handle = loaded
    } catch {
      dlclose(loaded)
      throw error
    }
  }
  deinit { dlclose(handle) }
}

/// A worker-owned factory. It retains the exact Swift tokenizer for callbacks
/// and caches only immutable initial matchers. Each request owns a clone.
public final class SplashGrammarFactory {
  private let api: GuidanceAPI
  private let frontend: SplashTextFrontend
  private let tokenizer: OpaquePointer
  private var cache: [(String, OpaquePointer)] = []
  private var sourceBytes = 0
  public private(set) var cacheHits = 0
  public private(set) var cacheMisses = 0

  public init(frontend: SplashTextFrontend, library: URL, librarySHA256: String) throws {
    let api = try GuidanceAPI(library: library, expectedSHA256: librarySHA256)
    self.api = api
    self.frontend = frontend
    var configuration = LlgTokenizerInitV2()
    configuration.struct_size = MemoryLayout<LlgTokenizerInitV2>.size
    configuration.vocab_size = SplashTextFrontend.vocabularySize
    configuration.tok_eos = SplashTextFrontend.stopTokens[0]
    configuration.tokenize_assumes_string = true
    configuration.tokenize_user_data = UnsafeRawPointer(
      Unmanaged.passUnretained(frontend).toOpaque())
    configuration.tokenize_fn = { context, bytes, count, output, capacity in
      guard let context, let bytes else { return 0 }
      let frontend = Unmanaged<SplashTextFrontend>.fromOpaque(context).takeUnretainedValue()
      let text = String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
      let tokens = frontend.encode(text)
      if let output {
        for index in 0..<min(tokens.count, capacity) { output[index] = tokens[index] }
      }
      return tokens.count
    }
    let resource = try SplashRuntimeResources.resource(
      "json-slices", extension: "json", bundle: "Sevra_SevraSplashGrammar")
    let slices = try JSONDecoder().decode([String].self, from: Data(contentsOf: resource))
    let strings = slices.map { strdup($0) }
    defer { strings.forEach { free($0) } }
    var pointers: [UnsafePointer<CChar>?] = strings.map { $0.map { UnsafePointer($0) } } + [nil]
    var extra = SplashTextFrontend.stopTokens[1]
    var error = [CChar](repeating: 0, count: 4096)
    let vocabulary = try frontend.grammarVocabulary()
    let created = vocabulary.bytes.withUnsafeBufferPointer { bytePointer in
      vocabulary.lengths.withUnsafeBufferPointer { lengthPointer in
        pointers.withUnsafeMutableBufferPointer { slicePointer in
          withUnsafePointer(to: &extra) { eosPointer in
            configuration.token_lens = lengthPointer.baseAddress
            configuration.token_bytes = bytePointer.baseAddress
            configuration.slices = UnsafePointer(slicePointer.baseAddress)
            configuration.tok_eos_extra = eosPointer
            configuration.tok_eos_extra_count = 1
            return api.newTokenizer(&configuration, &error, error.count)
          }
        }
      }
    }
    guard let created else { throw SplashError("Cannot initialize the native grammar tokenizer") }
    tokenizer = created
  }

  deinit {
    for (_, matcher) in cache { api.freeMatcher(matcher) }
    api.freeTokenizer(tokenizer)
  }

  public func create(grammar: String, type: String = "llguidance") throws -> SplashGrammarConstraint
  {
    guard ["llguidance", "json", "lark", "regex"].contains(type),
      !grammar.isEmpty, grammar.utf8.count <= 8 * 1024 * 1024,
      !grammar.utf8.contains(0)
    else {
      throw SplashError("Output grammar is unsupported or exceeds the preparation limit")
    }
    let key = type + ":" + grammar
    let matcher: OpaquePointer
    if let index = cache.firstIndex(where: { $0.0 == key }) {
      let entry = cache.remove(at: index)
      cache.append(entry)
      matcher = entry.1
      cacheHits += 1
    } else {
      var configuration = LlgConstraintInit()
      api.defaults(&configuration, tokenizer)
      configuration.log_buffer_level = 0
      configuration.log_stderr_level = 0
      configuration.limits.verbose_errors = false
      guard let created = api.newMatcher(&configuration, type, grammar) else {
        throw SplashError("Cannot compile output grammar")
      }
      guard api.error(created) == nil else {
        api.freeMatcher(created)
        throw SplashError("Output schema cannot be compiled by the native grammar")
      }
      while !cache.isEmpty && (cache.count >= 32 || sourceBytes + key.utf8.count > 8 * 1024 * 1024)
      {
        let removed = cache.removeFirst()
        sourceBytes -= removed.0.utf8.count
        api.freeMatcher(removed.1)
      }
      // One maximum-size schema includes its small type prefix.
      guard key.utf8.count <= 8 * 1024 * 1024 else {
        defer { api.freeMatcher(created) }
        return try constraint(cloning: created)
      }
      cache.append((key, created))
      sourceBytes += key.utf8.count
      matcher = created
      cacheMisses += 1
    }
    return try constraint(cloning: matcher)
  }

  private func constraint(cloning matcher: OpaquePointer) throws -> SplashGrammarConstraint {
    guard let copy = api.clone(matcher) else { throw SplashError("Cannot clone output grammar") }
    return SplashGrammarConstraint(factory: self, api: api, matcher: copy)
  }
}

/// One request's committed grammar state. Speculative masks use a clone, so
/// rejected proposals never advance committed state. Access only on its worker.
public final class SplashGrammarConstraint {
  private let factory: SplashGrammarFactory
  private let api: GuidanceAPI
  private let matcher: OpaquePointer
  private var consumed: [UInt32] = []
  private var failed = false
  fileprivate init(factory: SplashGrammarFactory, api: GuidanceAPI, matcher: OpaquePointer) {
    self.factory = factory
    self.api = api
    self.matcher = matcher
  }
  deinit { api.freeMatcher(matcher) }
  public var isAccepting: Bool { !failed && api.accepting(matcher) }

  private func consume(_ committed: [UInt32]) throws {
    guard !failed, committed.count <= SplashWire.maxTokens, committed.starts(with: consumed),
      committed.allSatisfy({ $0 < SplashTextFrontend.vocabularySize })
    else {
      failed = true
      throw SplashError("Committed grammar tokens are inconsistent or out of range")
    }
    let new = Array(committed.dropFirst(consumed.count))
    if new.isEmpty { return }
    let code: Int32
    if new.count == 1, SplashTextFrontend.stopTokens.contains(new[0]),
      api.error(matcher) == nil, api.stopped(matcher), api.accepting(matcher)
    {
      // The Python binding's consume_token_inner treats stopped EOS as a no-op.
      // The C matcher does not, so preserve that exact frontend behavior here.
      code = 0
    } else {
      code = new.withUnsafeBufferPointer { api.consume(matcher, $0.baseAddress, $0.count) }
    }
    guard code == 0 else {
      failed = true
      throw SplashError("Generated tokens violated the output grammar")
    }
    consumed = committed
  }

  /// Row 0 is the grammar's mask after the committed tokens, and row i + 1 the mask after draft
  /// token i's path: the tokens from the first along their parents to it. As Splash 1.7.1's
  /// `TokenConstraint.masks`, the tree is walked depth first and only forward, on a copy of the
  /// committed matcher; a row with several children gives each but the last a copy of its own.
  /// No matcher takes a token back: LLGuidance 1.8.0 keeps its last mask keyed by the lexer state
  /// and the parser's row index, which another branch can reach again after a rollback with
  /// other parser rows under it (Splash #790, LLGuidance #390). A token outside the vocabulary,
  /// a stop token or a token the grammar refuses is a row the target never accepts, nor any row
  /// below it; those rows take their parent's mask. No forced tokens are returned.
  public func masks(_ query: SplashWire.MaskQuery) throws -> SplashWire.MaskReply {
    let rows = query.rows
    guard !failed, query.simulation.count <= SplashWire.maxSimulationTokens,
      query.parents.count == query.simulation.count,
      query.parents.indices.allSatisfy({
        $0 == 0 ? query.parents[0] == SplashWire.noParent : query.parents[$0] < $0
      }),
      query.words == (SplashTextFrontend.vocabularySize + 31) / 32,
      api.maskBytes(matcher) == Int(query.words) * 4
    else {
      failed = true
      throw SplashError("Invalid native grammar mask dimensions")
    }
    try consume(query.committed)
    let width = Int(query.words)
    var result = [UInt32](repeating: 0, count: width * rows)
    var reached = [Bool](repeating: false, count: rows)
    var children = [[Int]](repeating: [], count: rows)
    let follows = query.parents.map { $0 == SplashWire.noParent ? 0 : Int($0) + 1 }
    for (index, parentRow) in follows.enumerated() { children[parentRow].append(index + 1) }

    func reach(_ state: OpaquePointer, _ row: Int) throws {
      let code = result.withUnsafeMutableBufferPointer {
        api.compute(state, $0.baseAddress! + row * width, width * 4)
      }
      guard code == 0 else {
        failed = true
        throw SplashError("Cannot compute the output grammar mask")
      }
      reached[row] = true
    }
    func walk(_ state: OpaquePointer, _ row: Int) throws {
      let last = children[row].count - 1
      for (index, child) in children[row].enumerated() {
        var token = query.simulation[child - 1]
        if token >= SplashTextFrontend.vocabularySize
          || SplashTextFrontend.stopTokens.contains(token)
        {
          continue
        }
        // As the reference: copy first, then try the token on the copy, so a sibling never
        // sees a matcher another sibling validated on.
        let branch: OpaquePointer
        if index == last {
          branch = state
        } else {
          guard let copy = api.clone(state) else {
            failed = true
            throw SplashError("Cannot copy the output grammar")
          }
          branch = copy
        }
        defer { if index != last { api.freeMatcher(branch) } }
        let valid = api.validate(branch, &token, 1)
        guard valid >= 0, valid <= 1 else {
          failed = true
          throw SplashError("Cannot validate speculative grammar tokens")
        }
        if valid == 0 { continue }
        guard api.consumeOne(branch, token) == 0 else {
          failed = true
          throw SplashError("Speculative grammar validation changed")
        }
        try reach(branch, child)
        try walk(branch, child)
      }
    }

    try reach(matcher, 0)
    if !query.simulation.isEmpty {
      guard let walker = api.clone(matcher) else {
        failed = true
        throw SplashError("Cannot copy the output grammar")
      }
      defer { api.freeMatcher(walker) }
      try walk(walker, 0)
    }
    // A parent's row comes before its children's.
    for row in 1..<max(1, rows) where !reached[row] {
      let parent = follows[row - 1]
      for word in 0..<width { result[row * width + word] = result[parent * width + word] }
    }
    for row in 0..<rows where !result[(row * width)..<((row + 1) * width)].contains(where: { $0 != 0 }) {
      failed = true
      throw SplashError("Output grammar has no valid next token")
    }
    return SplashWire.MaskReply(words: result)
  }

  public func finish(committed: [UInt32], requireComplete: Bool) throws {
    try consume(committed)
    if requireComplete && !isAccepting {
      throw SplashError("Model stopped before completing its output grammar")
    }
  }
}
