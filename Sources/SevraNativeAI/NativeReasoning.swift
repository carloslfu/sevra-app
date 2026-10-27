import SevraCore
import SevraSplash

/// Internal comparison profiles. Not a user preference or an adopted default.
package enum NativeReasoning: Int, Sendable {
  case off = 0
  case bounded512 = 512

  package var enabled: Bool { self != .off }
  package func budget(outputTokens: Int) throws -> SplashWire.Thinking? {
    guard enabled else { return nil }
    try require(
      outputTokens >= rawValue + 4 + 256, "context_limit",
      "This request has insufficient space for bounded reasoning and a complete tool response.")
    // Match pinned Splash's Qwen budget. Under grammar masks, the native engine
    // waits for a complete UTF-8 character before selecting the close. Reserve
    // three continuation-byte tokens plus the close before the tool allowance. The total
    // output limit still bounds the whole response, including that small overrun.
    return .init(tokens: UInt32(rawValue), end: [248069], alsoEnds: 248058)
  }

  package func generatedTokens(_ tokens: [UInt32]) throws -> Int {
    guard enabled else { return 0 }
    guard let end = tokens.firstIndex(where: { $0 == 248069 || $0 == 248058 }) else {
      throw SevraError("reasoning_incomplete", "Reasoning did not close before the tool response.")
    }
    return end
  }
}
