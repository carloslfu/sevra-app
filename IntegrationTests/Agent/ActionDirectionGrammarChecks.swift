import Foundation
import SevraAI
import SevraNativeAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

func checkActionDirectionGrammar(
  frontend: SplashTextFrontend, factory: SplashGrammarFactory
) throws {
  for thinking in [false, true] {
    let policy = try NativeCitationPolicy.make(
      [], toolScope: .actionDirection, thinking: thinking)
    func output(_ rows: [String], tool: String = "review_action_directions") -> [UInt32] {
      frontend.encode(
        (thinking ? "Check each original independently.</think>\n" : "")
          + "<tool_call>\n<function=\(tool)>\n<parameter=directions>\n["
          + rows.joined(separator: ",") + "]\n</parameter>\n</function>\n</tool_call>")
    }
    let rows = (10..<20).map { index in
      "{\"index\":\(index),\"direction\":\"incoming\",\"basis\":\"evidence\",\"quote\":\"We received these items.\"}"
    }
    let valid = try factory.create(grammar: policy.grammar)
    let tokens = output(rows)
    try valid.finish(committed: tokens, requireComplete: true)
    try expectEqual(tokens.count < 1800 - 512, true)
    for invalid in [
      output(rows + [rows[0]]),
      output(["{\"direction\":\"incoming\",\"basis\":\"evidence\",\"quote\":\"Received\"}"]),
      output(rows, tool: "prepare_action"),
    ] {
      let constraint = try factory.create(grammar: policy.grammar)
      try expectThrows(try constraint.finish(committed: invalid, requireComplete: true))
    }
  }
  print(
    "PASS isolated batch-direction grammar, ten global indexes, required fields, tool isolation and bounded output with reasoning on/off"
  )
}
