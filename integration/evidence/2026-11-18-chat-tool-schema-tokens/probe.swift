import Foundation
import SevraAI
import SevraCore
import SevraNativeAI
import SevraSplash
import SevraSplashGrammar
import SevraSplashText

@main struct Probe {
  static func main() throws {
    let modelsRoot = URL(fileURLWithPath: CommandLine.arguments[1])
    let assembly = try SplashModelPreparation.installed(
      pack: SplashModelPack.selected(), modelsRoot: modelsRoot)
    let frontend = try SplashTextFrontend(modelFolder: assembly.appendingPathComponent("tokenizer"))
    if CommandLine.arguments.count == 3 {
      let text = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
      for line in text.components(separatedBy: "\n") where !line.isEmpty {
        print(frontend.encode(line + "\n").count, String(line.trimmingCharacters(in: .whitespaces).prefix(70)), separator: "\t")
      }
      return
    }
    func tools(_ scope: InferenceToolScope, authoring: Bool, input: Bool, actions: [String]?) throws
      -> [[String: any Sendable]]
    {
      try NativeCitationPolicy.make(
        [], toolScope: scope, thinking: true, conversationActions: actions,
        documentCopyIDs: nil, historyReferenceIDs: nil, nativeAppAuthoring: authoring,
        conversationInput: input
      ).promptTools()
    }
    func name(_ tool: [String: any Sendable]) -> String {
      ((tool["function"] as? [String: any Sendable])?["name"] as? String) ?? ""
    }
    func description(_ tool: [String: any Sendable]) -> String {
      ((tool["function"] as? [String: any Sendable])?["description"] as? String) ?? ""
    }
    let base: [[String: any Sendable]] = [
      ["role": "system", "content": "Rules."], ["role": "user", "content": "Question."],
    ]
    func count(_ list: [[String: any Sendable]]?) throws -> Int {
      try frontend.prepare(
        messages: base, tools: list, thinking: true, contextLimit: SplashWire.maxTokens
      ).tokens.count
    }
    let mainActions = ["start_thread", "start_thread_and_continue"]
    let sideActions = [
      "start_thread", "start_thread_and_continue", "rename_thread", "return_to_main",
      "review_summary",
    ]
    let everything = try tools(.all, authoring: true, input: true, actions: sideActions)
    let anchor = everything.first { name($0) == "finish" }!
    let withAnchor = try count([anchor])
    let none = try count(nil)
    var rows: [[String: Any]] = []
    for tool in everything {
      let json = try JSONSerialization.data(
        withJSONObject: tool, options: [.sortedKeys, .withoutEscapingSlashes])
      let compact = frontend.encode(String(decoding: json, as: UTF8.self) + "\n").count
      let template =
        name(tool) == "finish" ? withAnchor - none : try count([anchor, tool]) - withAnchor
      let shared =
        InferenceToolScope.answer.allows(name(tool))
        && !["workspace_actions", "workspace_action"].contains(name(tool))
      rows.append([
        "name": name(tool), "shared": shared, "template": template, "compact": compact,
        "description": frontend.encode(description(tool)).count,
      ])
    }
    func names(_ scope: InferenceToolScope, authoring: Bool, input: Bool, actions: [String]?) throws
      -> [String]
    { try tools(scope, authoring: authoring, input: input, actions: actions).map(name) }
    let output: [String: Any] = [
      "templateWrapper": withAnchor - none, "tools": rows,
      "mainFirst": try names(.all, authoring: false, input: true, actions: mainActions),
      "mainReadOnly": try names(.conversationAnswer, authoring: false, input: true, actions: mainActions),
      "side": try names(.all, authoring: false, input: true, actions: sideActions),
      "authoring": try names(.all, authoring: true, input: true, actions: mainActions),
      "mainFirstTemplateTotal": try count(tools(.all, authoring: false, input: true, actions: mainActions)) - none,
      "readOnlyTemplateTotal": try count(tools(.conversationAnswer, authoring: false, input: true, actions: mainActions)) - none,
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted])
    FileHandle.standardOutput.write(data)
  }
}
