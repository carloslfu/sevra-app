import CryptoKit
import Foundation
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

struct Fixtures: Decodable {
  let byteVocabularySHA256: String
  struct Case: Decodable {
    struct Step: Decodable {
      let committed: [UInt32]
      let simulation: [UInt32]
      let maskSHA256: String
    }
    let name: String
    let grammar: String
    let type: String
    let output: String
    let tokens: [UInt32]
    let steps: [Step]
  }
  let cases: [Case]
}
func refused(_ operation: () throws -> Void) throws {
  var rejected = false
  do { try operation() } catch { rejected = true }
  guard rejected else { throw SplashError("Invalid grammar operation was accepted") }
}
do {
  guard [3, 5].contains(CommandLine.arguments.count) else {
    throw SplashError(
      "Usage: sevra-splash-grammar-checks MODEL_FOLDER PINNED_NATIVE_LIBRARY [ENGINE ASSEMBLY]")
  }
  let frontend = try SplashTextFrontend(modelFolder: URL(fileURLWithPath: CommandLine.arguments[1]))
  let library = URL(fileURLWithPath: CommandLine.arguments[2])
  let digest = SHA256.hash(data: try Data(contentsOf: library)).map { String(format: "%02x", $0) }
    .joined()
  let factory = try SplashGrammarFactory(
    frontend: frontend, library: library, librarySHA256: digest)
  let fixtures = try JSONDecoder().decode(
    Fixtures.self,
    from: Data(
      contentsOf:
        Bundle.module.url(forResource: "fixtures", withExtension: "json")!))
  let vocabulary = try frontend.grammarVocabulary()
  var vocabularyHash = SHA256()
  vocabulary.lengths.withUnsafeBytes { vocabularyHash.update(data: Data($0)) }
  vocabularyHash.update(data: Data(vocabulary.bytes))
  guard
    vocabularyHash.finalize().map({ String(format: "%02x", $0) }).joined()
      == fixtures.byteVocabularySHA256
  else {
    throw SplashError("Native grammar byte vocabulary differs from the pinned reference")
  }
  print("PASS exact byte vocabulary for all \(SplashTextFrontend.vocabularySize) tokens")
  let words = (SplashTextFrontend.vocabularySize + 31) / 32
  var requests = 0
  for fixture in fixtures.cases {
    let grammar = try factory.create(grammar: fixture.grammar, type: fixture.type)
    guard frontend.encode(fixture.output) == fixture.tokens else {
      throw SplashError("Grammar fixture tokenizer differs: " + fixture.name)
    }
    for (index, step) in fixture.steps.enumerated() {
      let masks = try grammar.masks(
        committed: step.committed, simulation: step.simulation, words: words)
      let hash = masks.withUnsafeBytes {
        SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined()
      }
      guard hash == step.maskSHA256 else {
        if let folder = ProcessInfo.processInfo.environment["SEVRA_GRAMMAR_FAILURE_DIR"] {
          let destination = URL(fileURLWithPath: folder)
          try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true)
          try masks.withUnsafeBytes {
            try Data($0).write(
              to: destination.appendingPathComponent("native-mask.bin"), options: .atomic)
          }
        }
        throw SplashError(
          "Native mask differs from reference: \(fixture.name), step \(index), actual \(hash)")
      }
      requests += 1
    }
    try grammar.finish(committed: fixture.tokens, requireComplete: true)
    for eos in SplashTextFrontend.stopTokens {
      let terminal = try factory.create(grammar: fixture.grammar, type: fixture.type)
      try terminal.finish(committed: fixture.tokens, requireComplete: true)
      try terminal.finish(committed: fixture.tokens + [eos], requireComplete: true)
    }
    let cached = try factory.create(grammar: fixture.grammar, type: fixture.type)
    guard !cached.isAccepting else { throw SplashError("Cached grammar state was mutated") }
    try refused { try cached.finish(committed: [], requireComplete: true) }
    try refused { _ = try cached.masks(committed: [], simulation: [1], words: 0) }
    let invalid = try factory.create(grammar: fixture.grammar, type: fixture.type)
    try refused {
      try invalid.finish(committed: [SplashTextFrontend.vocabularySize], requireComplete: false)
    }
    let invalidCount = try factory.create(grammar: fixture.grammar, type: fixture.type)
    try refused {
      _ = try invalidCount.masks(
        committed: [], simulation: Array(repeating: 1, count: 9), words: words)
    }
    let invalidText = try factory.create(grammar: fixture.grammar, type: fixture.type)
    try refused {
      try invalidText.finish(committed: frontend.encode("INCORRECT"), requireComplete: true)
    }
    let stale = try factory.create(grammar: fixture.grammar, type: fixture.type)
    try stale.finish(committed: Array(fixture.tokens.prefix(1)), requireComplete: false)
    try refused { try stale.finish(committed: [], requireComplete: false) }
    print("PASS \(fixture.name): exact speculative masks, cache isolation, EOS and refusals")
  }
  try refused { _ = try factory.create(grammar: "invalid", type: "json") }
  try refused { _ = try factory.create(grammar: "{}\0extra", type: "json") }
  try refused {
    _ = try factory.create(grammar: String(repeating: "x", count: 8 * 1024 * 1024 + 1))
  }
  try refused {
    _ = try SplashGrammarFactory(
      frontend: frontend, library: library, librarySHA256: String(repeating: "0", count: 64))
  }
  print("PASS \(requests) exact upstream mask requests across \(fixtures.cases.count) grammars")
  if CommandLine.arguments.count == 5 {
    try runNativeGrammar(
      frontend: frontend, factory: factory, fixtures: fixtures,
      engine: CommandLine.arguments[3], assembly: CommandLine.arguments[4])
  }
} catch {
  fputs("\(error)\n", stderr)
  exit(1)
}
