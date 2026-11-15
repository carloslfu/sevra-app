import Foundation
import SevraAI
import SevraNativeAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

func checkNativeReviewGrammar(frontend: SplashTextFrontend, factory: SplashGrammarFactory) throws {
  for thinking in [false, true] {
    let policy = try NativeCitationPolicy.make([], toolScope: .nativeAppReview, thinking: thinking)
    func output(_ roles: String, tool: String = "review_native_app") -> [UInt32] {
      frontend.encode(
        (thinking ? "Verify typed roles.</think>\n" : "")
          + "<tool_call>\n<function=\(tool)>\n<parameter=decision>\nready\n</parameter>\n"
          + "<parameter=inputRoles>\n" + roles + "\n</parameter>\n"
          + "<parameter=issues>\n[]\n</parameter>\n</function>\n</tool_call>")
    }
    let roles =
      #"{"create":{"customer":{"column":"c1","headerRow":1,"kind":"existingKey","table":"sheet1"},"reference":{"kind":"value"},"amount":{"kind":"number","maximum":null,"minimum":0,"nonzero":true,"whole":false}}}"#
    let valid = try factory.create(grammar: policy.grammar)
    let validTokens = output(roles)
    for end in 1...validTokens.count {
      do {
        try valid.finish(
          committed: Array(validTokens.prefix(end)), requireComplete: end == validTokens.count)
      } catch {
        throw SplashError(
          "Review grammar rejected valid roles (thinking=\(thinking)) near: "
            + frontend.decode(Array(validTokens.prefix(end))).suffix(250))
      }
    }
    for tokens in [
      output(roles.replacingOccurrences(of: "existingKey", with: "inventedKind")),
      output(roles.replacingOccurrences(of: "\"column\":\"c1\",", with: "")),
      output(roles.replacingOccurrences(of: "\"headerRow\":1", with: "\"headerRow\":1.5")),
      output(roles.replacingOccurrences(of: "\"whole\":false", with: "\"whole\":\"false\"")),
      output(roles.replacingOccurrences(of: "\"minimum\":0,", with: "")),
      output(roles.replacingOccurrences(of: "\"maximum\":null", with: "\"maximum\":\"none\"")),
      output(roles, tool: "save_native_app"),
    ] {
      let invalid = try factory.create(grammar: policy.grammar)
      try expectThrows(try invalid.finish(committed: tokens, requireComplete: true))
    }
  }
  print("PASS independent review grammar: nested input roles, typed headers and no write tools")
}
