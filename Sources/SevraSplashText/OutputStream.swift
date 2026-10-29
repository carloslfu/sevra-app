import Foundation
import SevraSplash

/// One request's native output pipeline. Only committed token batches enter.
/// Do not feed speculative candidates or synthesize a successful terminal after
/// an engine error. The native transport validates order and the terminal event.
public final class SplashOutputStream {
  private let decoder: SplashTextStream
  private let parser: SplashOutputParser
  private var terminal = false
  public var isReasoning: Bool { parser.isReasoning }
  public var matchedStop: String? { decoder.matchedStop }

  public init(
    frontend: SplashTextFrontend, tools: [SplashOutputTool] = [],
    thinking: Bool = false, structured: Bool = false, stopSequences: [String] = []
  ) throws {
    decoder = try frontend.makeDecoder(stopSequences: stopSequences)
    parser = try SplashOutputParser(tools: tools, thinking: thinking, structured: structured)
  }

  public func append(tokens: [UInt32]) throws -> [SplashOutputDelta] {
    guard !terminal else { throw SplashError("Generation output has already ended") }
    do {
      var events: [SplashOutputDelta] = []
      for token in tokens { events += try parser.append(decoder.append(token)) }
      return events
    } catch {
      terminal = true
      throw error
    }
  }

  public func finish(_ reason: SplashWire.Finish) throws -> (
    SplashParsedOutput, [SplashOutputDelta]
  ) {
    guard !terminal else { throw SplashError("Generation output has already ended") }
    terminal = true
    var events = try parser.append(decoder.finish())
    // Caller-defined stops cut off the model response and cannot authorize a
    // call, even if a close tag appeared before the stop sequence.
    let effectiveReason: SplashWire.Finish =
      matchedStop == nil || reason == .cancelled ? reason : .length
    let (output, tail) = try parser.finish(effectiveReason)
    events += tail
    return (output, events)
  }
}
