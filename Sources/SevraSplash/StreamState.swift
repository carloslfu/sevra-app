import Foundation

/// Validates one admitted request independently of transport or UI callbacks.
public struct SplashStreamState {
  private let request: SplashWire.Request
  private var started = false
  private var matched: UInt32 = 0
  private var progress: (UInt32, UInt64)?
  private var lastMask: UInt64 = 0
  public private(set) var tokens: [UInt32] = []
  public private(set) var terminal = false
  public var cancelled = false
  public init(_ request: SplashWire.Request) { self.request = request }

  @discardableResult public mutating func accept(_ event: SplashWire.Event) throws -> SplashWire
    .Done?
  {
    try check(!terminal, "Native event arrived after terminal result")
    switch event {
    case .start(let id, _, let cached):
      try identity(id)
      try check(!started && cached <= request.prompt.count, "Invalid or repeated start")
      started = true
      matched = cached
    case .progress(let id, let processed, let elapsed):
      try identity(id)
      try check(
        started && tokens.isEmpty && request.flags & 2 != 0, "Progress outside requested prefill")
      try check(
        processed >= matched && processed <= request.prompt.count, "Progress outside prompt")
      if let (previous, time) = progress {
        try check(processed > previous && elapsed >= time, "Progress moved backwards or repeated")
      }
      progress = (processed, elapsed)
    case .tokens(let id, let offset, let batch):
      try identity(id)
      try check(
        started && Int(offset) == tokens.count, "Missing start, token gap or duplicate tokens")
      try check(
        !batch.isEmpty && tokens.count + batch.count <= request.maxOutput,
        "Output exceeds admitted limit")
      tokens.append(contentsOf: batch)
    case .mask(let id, let maskID, _, _):
      try identity(id)
      try check(
        started && request.tokenMask && maskID > lastMask, "Unexpected or repeated mask request")
      lastMask = maskID
    case .done(let done):
      try identity(done.id)
      try check(
        done.prompt == request.prompt.count && done.completion == tokens.count,
        "Completion counts disagree with stream")
      try check(
        started || (cancelled && done.reason == .cancelled && tokens.isEmpty),
        "Completion before start")
      if done.reason == .length {
        try check(
          done.bounded ? tokens.count < request.maxOutput : tokens.count == request.maxOutput,
          "Invalid length completion")
      }
      if request.scores.isEmpty {
        try check(done.logits.isEmpty, "Unexpected scores")
      } else {
        try check(done.decodeMicros == 0 && done.reason != .length, "Invalid scoring completion")
        try check(
          done.reason == .stop ? done.logits.count == request.scores.count : done.logits.isEmpty,
          "Missing or unfinished scores")
      }
      terminal = true
      return done
    case .error(let failure):
      if failure.classification == 1 { try identity(failure.id) }
      terminal = true
      throw failure
    default: throw SplashError("Unexpected control event in request stream")
    }
    return nil
  }
  private func identity(_ id: UInt64) throws {
    try check(id == request.id, "Native event names an unknown request")
  }
}
