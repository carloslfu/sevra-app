import Foundation

extension WorkbookTools {
  func publishDefinitionResult(_ arguments: Value) throws -> Value {
    let a = arguments
    try require(
      Set(a.object.keys).isSubset(of: [
        "evaluationReceiptID", "title", "meaning", "scenario", "inputs",
      ])
        && ["evaluationReceiptID", "title", "meaning"].allSatisfy { a[$0].string != nil },
      "arguments", "Use an exact current evaluation receipt, result title and explicit meaning.")
    if a.object["scenario"] != nil {
      try require(a["scenario"].string != nil, "arguments", "Scenario must be text.")
    }
    if let raw = a.object["inputs"] {
      guard case .array(let values) = raw, values.allSatisfy({ $0.string != nil }) else {
        throw SevraError("arguments", "Inputs must be exact item versions.")
      }
    }
    let evaluation = try workbook.applicationEvaluationForRun(
      a["evaluationReceiptID"].text, runID: runID, conversation: conversation,
      requestSourceID: requestSourceID)
    return try encoded(
      workbook.publishApplicationResult(
        evaluation["definitionID"].text, arguments: evaluation["submittedArguments"],
        evaluation: evaluation, title: a["title"].text, meaning: a["meaning"].text,
        scenario: a.object["scenario"]?.text ?? "actual", inputs: a["inputs"].array.map(\.text),
        token: operationToken("publish_result", a), readOnly: readOnly,
        requestRunID: runID, requestSourceID: requestSourceID, cancellation: cancellation))
  }
}

extension Workbook {
  func applicationEvaluationForRun(
    _ receiptID: String, runID: String, conversation: String, requestSourceID: String?
  ) throws -> Value {
    try synchronized {
      try db.readTransaction {
        try validateApplicationToolRun(
          runID, conversation: conversation, requestSourceID: requestSourceID)
        let call = try toolCall(receiptID, conversation: conversation)
        try require(
          call["run_id"].text == runID && call["state"].text == "completed"
            && call["tool"].text == "evaluate_definition" && call["arguments"]["cursor"] == .null,
          "definition_evaluation",
          "Choose this active run's successful first-page evaluation receipt.")
        let row = try db.execute(
          "SELECT result,result_hash FROM tool_calls WHERE id=?", [.string(receiptID)]
        ).first!
        let json = row["result"]!.text
        try require(
          ToolResultProjection.digest(json) == row["result_hash"]!.text, "integrity",
          "The evaluation receipt changed.")
        let result = try Value.parse(json)
        try require(
          result["receiptID"] == .string(receiptID)
            && result["definitionID"] == call["arguments"]["id"]
            && result["submittedArguments"] == call["arguments"]["arguments"],
          "definition_evaluation", "The evaluation does not match its exact saved inputs.")
        var evaluation = result.object
        evaluation.removeValue(forKey: "receiptID")
        return .object(evaluation)
      }
    }
  }
}
