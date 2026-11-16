import Foundation
import SevraAI
import SevraCore
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
  for thinking in [false, true] {
    let contracts = try Value.parse(
      """
      {"ship":{"quantity":{"valueType":"number","required":true}},
       "remove":{"reference":{"valueType":"string","required":true}},
       "updateLoan":{"months":{"valueType":"number","required":true},
                     "principal":{"valueType":"string","required":true},
                     "rate":{"valueType":"string","required":true},
                     "includeFees":{"valueType":"boolean","required":false}}}
      """)
    let policy = try NativeCitationPolicy.make(
      [], toolScope: .nativeActionReview, thinking: thinking,
      reviewContract: .object([
        "actions": contracts,
        "columns": .object([
          "ledger": .array([.string("reference"), .string("quantity")]),
          "sheet1": .array([.string("c2"), .string("c3"), .string("c4")]),
          "summary": .array([.string("reference"), .string("quantity")]),
        ]),
        "writableTables": .array([.string("ledger"), .string("sheet1")]),
      ]))
    func output(
      _ probes: String, tool: String = "review_native_app", fixtures: String? = nil,
      extraRoles: Bool = false
    )
      -> [UInt32]
    {
      frontend.encode(
        (thinking ? "Derive the saved effect.</think>\n" : "")
          + "<tool_call>\n<function=\(tool)>\n<parameter=decision>\nready\n</parameter>\n"
          + (extraRoles ? "<parameter=inputRoles>\n{}\n</parameter>\n" : "")
          + (fixtures.map { "<parameter=fixtures>\n" + $0 + "\n</parameter>\n" } ?? "")
          + "<parameter=issues>\n[]\n</parameter>\n<parameter=probes>\n"
          + probes + "\n</parameter>\n</function>\n</tool_call>")
    }
    let probes =
      #"[{"action":"ship","inputs":{"quantity":3},"inputRoles":{"quantity":{"kind":"number","maximum":null,"minimum":0,"nonzero":true,"whole":false}},"expect":[{"kind":"expect_row","table":"ledger","values":{"reference":"NEW","quantity":"-3"}},{"kind":"expect_text","value":"Remaining 7"}]},{"action":"ship","inputs":{"quantity":0},"expect":[{"kind":"reject"}]}]"#
    let valid = try factory.create(grammar: policy.grammar)
    let validTokens = output(
      probes,
      fixtures:
        #"{"ledger":[{"quantity":"Quantity","reference":"Reference"},{"quantity":"10","reference":"PREV"}]}"#
    )
    for end in 1...validTokens.count {
      do {
        try valid.finish(
          committed: Array(validTokens.prefix(end)), requireComplete: end == validTokens.count)
      } catch {
        throw SplashError(
          "Blind review grammar rejected a valid probe (thinking=\(thinking)) near: "
            + frontend.decode(Array(validTokens.prefix(end))).suffix(450))
      }
    }
    let removal =
      #"[{"action":"remove","inputs":{"reference":"REMOVE"},"inputRoles":{"reference":{"column":"reference","headerRow":1,"kind":"existingKey","table":"ledger"}},"expect":[{"kind":"expect_rows","table":"ledger","count":0,"values":{"reference":"REMOVE"}}]}]"#
    do {
      try factory.create(grammar: policy.grammar).finish(
        committed: output(removal), requireComplete: true)
    } catch {
      throw SplashError(
        "Blind review grammar rejected a valid removal: " + error.localizedDescription)
    }
    let loan =
      #"[{"action":"updateLoan","inputs":{"months":12,"principal":"12000","rate":"0.05"},"inputRoles":{"months":{"kind":"number","maximum":null,"minimum":1,"nonzero":false,"whole":true},"principal":{"kind":"number","maximum":null,"minimum":0,"nonzero":false,"whole":false},"rate":{"kind":"number","maximum":null,"minimum":0,"nonzero":false,"whole":false}},"expect":[{"kind":"expect_row","table":"sheet1","values":{"c2":"12000","c3":"0.05","c4":"12"}}]}]"#
    try factory.create(grammar: policy.grammar).finish(
      committed: output(loan), requireComplete: true)
    for tokens in [
      output(loan.replacingOccurrences(of: #""principal":"12000""#, with: #""principal":12000"#)),
      output(loan.replacingOccurrences(of: #""rate":"0.05""#, with: #""rate":0.05"#)),
      output(loan.replacingOccurrences(of: #""months":12,"#, with: "")),
      output(loan.replacingOccurrences(of: #""updateLoan""#, with: #""unregistered""#)),
      output("[]"),
      output(#"[{"kind":"expect_text","value":"Ready"}]"#),
      output(#"[{"action":"ship","inputs":{}}]"#),
      output(#"[{"action":"ship","inputs":{},"expect":[]}]"#),
      output(#"[{"action":"ship","inputs":{},"expect":{"kind":"reject"}}]"#),
      output(
        #"[{"action":"ship","inputs":{},"expect":[{"kind":"reject"},{"kind":"expect_text","value":"Done"}]}]"#
      ),
      output(probes.replacingOccurrences(of: #""quantity":"-3""#, with: #""quantity":-3"#)),
      output(probes.replacingOccurrences(of: "expect_row", with: "run_action")),
      output(probes.replacingOccurrences(of: #""table":"ledger""#, with: #""table":"summary""#)),
      output(removal.replacingOccurrences(of: #""count":0"#, with: #""count":1"#)),
      output(removal.replacingOccurrences(of: #","values":{"reference":"REMOVE"}"#, with: "")),
      output(probes, tool: "save_native_app"),
      output(probes, extraRoles: true),
      output(probes, fixtures: #"{"ledger":[["Reference","Quantity"]]}"#),
      output(probes, fixtures: #"{"ledger":[{"Display Heading":"Value"}]}"#),
      output(probes, fixtures: #"{"otherLedger":[{"reference":"Reference"}]}"#),
      output(probes.replacingOccurrences(of: #""whole":false"#, with: "\"whole\":\"false\"")),
      output(
        #"[{"action":"ship","inputs":{"quantity":3},"expect":[{"kind":"expect_text","value":"Saved"}]}]"#
      ),
      output(
        #"[{"action":"ship","inputs":{"quantity":0},"inputRoles":{},"expect":[{"kind":"reject"}]}]"#
      ),
    ] {
      let invalid = try factory.create(grammar: policy.grammar)
      try expectThrows(try invalid.finish(committed: tokens, requireComplete: true))
    }
  }
  for thinking in [false, true] {
    let policy = try SplashToolPolicy.interpretationResult(
      schemaJSON: Data(NativeAppReview.numericRulingSchema.json().utf8), thinking: thinking)
    func output(_ result: String, tool: String = "interpretation_result") -> [UInt32] {
      frontend.encode(
        (thinking ? "Check the original rule.</think>\n" : "")
          + "<tool_call>\n<function=\(tool)>\n<parameter=result>\n"
          + result + "\n</parameter>\n</function>\n</tool_call>")
    }
    let allowed = output(#"{"decision":"allow","evidence":""}"#)
    let valid = try factory.create(grammar: policy.grammar)
    for end in 1...allowed.count {
      try valid.finish(
        committed: Array(allowed.prefix(end)), requireComplete: end == allowed.count)
    }
    for tokens in [
      output(#"{"decision":"approve","evidence":""}"#),
      output(#"{"decision":"forbid"}"#),
      output(#"{"decision":"allow","evidence":"","writes":true}"#),
      output(#"{"decision":"allow","evidence":""}"#, tool: "save_native_app"),
    ] {
      let invalid = try factory.create(grammar: policy.grammar)
      try expectThrows(try invalid.finish(committed: tokens, requireComplete: true))
    }
  }
  print("PASS disputed input grammar: exact interpretation only, no publication tool")
  print("PASS independent review grammar: nested input roles, typed headers and no write tools")
  print(
    "PASS blind review grammar: mandatory action/input/effect pairs, refusals, no standalone assertions"
  )
}
