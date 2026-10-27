import Darwin
import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

/// Engine-boundary qualification, separate from autonomous task success.
func runReasoningBoundaryProbe(
  modelFolder: String, library: String, engine: String, modelsRoot: String
) throws {
  let configuration = try nativeProbeConfiguration(
    library: library, engine: engine, modelsRoot: modelsRoot, budget: .init(profile: .evaluation32K)
  )
  let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Sevra")
  try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
  let fd = Darwin.open(
    support.appendingPathComponent("inference.lock").path,
    O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
  guard fd >= 0 else { throw SplashError("Cannot open inference lock") }
  defer { Darwin.close(fd) }
  guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
    throw SplashError("Another process owns inference")
  }
  defer { flock(fd, LOCK_UN) }
  let directory = URL(fileURLWithPath: modelFolder)
  let assembly = try SplashModelPreparation.prepare(
    pack: SplashModelPack.selected(), target: directory,
    draft: directory.appendingPathComponent("dflash"), modelsRoot: configuration.modelsRoot)
  let frontend = try SplashTextFrontend(modelFolder: directory)
  let factory = try SplashGrammarFactory(
    frontend: frontend, library: configuration.grammarLibrary,
    librarySHA256: configuration.grammarSHA256)
  let helper = try SplashNativeProcess(
    executable: configuration.engine,
    arguments: [
      "serve-native", assembly.path, "32768", "12884901888", "--persistent-cache", "off",
      "--idle-sleep", "allow", "--verify-rows", "all",
    ], timeout: 180)
  defer { helper.close() }
  let policy = try NativeCitationPolicy.make([], toolScope: .finish, thinking: true)
  let prompt = try frontend.prepare(
    messages: [
      ["role": "system", "content": "Think in Chinese. Use finish to answer, with no citations."],
      [
        "role": "user",
        "content":
          "Think carefully in Chinese about how to organize an empty workbook, then answer briefly in Chinese.",
      ],
    ], tools: policy.promptTools(), thinking: true, contextLimit: 32768)
  var forced = 0
  let splitCharacter = try expectValue(["𠀋", "🪷", "🧬"].first { frontend.encode($0).count > 1 })
  for index in 1...12 {
    let cancel = index == 9
    let truncate = index == 10
    let splitUTF8 = index == 12
    let budget = splitUTF8 ? 1 : index <= 8 ? index : 512
    var shouldCancel = false
    // A subset of the production grammar forces a split UTF-8 character at
    // the cutoff, instead of relying on natural output to exercise it.
    let grammar =
      try splitUTF8 ? forcedReasoningPrefixGrammar(policy, splitCharacter) : policy.grammar
    let constraint = try factory.create(grammar: grammar)
    let stream = try SplashOutputStream(
      frontend: frontend, tools: policy.outputTools, thinking: true)
    var request = SplashWire.Request(
      id: UInt64(index), prompt: prompt.tokens,
      absoluteDeadline: UInt64((Date().timeIntervalSince1970 + 180) * 1e6),
      remainingDeadline: 180_000_000)
    request.maxOutput = truncate ? 1 : 1800
    request.generationTokens = prompt.generationTokens
    request.tokenMask = true
    request.thinking = .init(tokens: UInt32(budget), end: [248069], alsoEnds: 248058)
    let generated = try helper.generate(
      request, cancelled: { shouldCancel },
      mask: { try constraint.masks(committed: $0, simulation: $1, words: $2) },
      event: {
        if case .tokens(_, _, let tokens) = $0 {
          _ = try stream.append(tokens: tokens)
          if cancel && !tokens.isEmpty { shouldCancel = true }
        }
      })
    let parsed = try stream.finish(generated.done.reason).0
    try expectEqual(parsed.reasoning.contains("\u{FFFD}"), false)
    try expectEqual(parsed.text.contains("\u{FFFD}"), false)
    if cancel || truncate {
      try expectEqual(generated.done.reason, cancel ? .cancelled : .length)
      try expectEqual(parsed.calls.isEmpty, true)
    } else {
      try expectEqual(generated.done.reason, .stop)
      try constraint.finish(committed: generated.tokens, requireComplete: true)
      try expectEqual(parsed.calls.count, 1)
      try policy.validate(parsed.calls[0])
      let count = try NativeReasoning.bounded512.generatedTokens(generated.tokens)
      if (index <= 8 || splitUTF8) && count >= budget { forced += 1 }
      if splitUTF8 {
        try expectEqual(parsed.reasoning.hasPrefix(splitCharacter), true)
        try expectEqual(count > budget, true)
      }
    }
    print(
      try Value.object([
        "boundary": .number(Double(index)), "budget": .number(Double(budget)),
        "cancelled": .bool(cancel), "truncated": .bool(truncate),
        "forcedSplitUTF8": .bool(splitUTF8),
        "reason": .number(Double(generated.done.reason.rawValue)),
        "generatedTokens": .number(Double(generated.tokens.count)),
        "reasoningTokens": .number(
          Double(generated.tokens.firstIndex(of: 248069) ?? generated.tokens.count)),
        "calls": .number(Double(parsed.calls.count)), "passed": .bool(true),
      ]).json())
    fflush(stdout)
  }
  try expectEqual(forced > 0, true)
  let status = try Value.parse(
    String(decoding: helper.status(id: 100, release: true), as: UTF8.self))
  try expectEqual(status["weights"]["released"], .bool(true))
  try expectEqual(status["metal"]["healthy"], .bool(true))
  print(
    try Value.object([
      "boundaryFinished": .bool(true), "forcedCloses": .number(Double(forced)),
      "weightsReleased": status["weights"]["released"], "metalHealthy": status["metal"]["healthy"],
    ]).json())
}
