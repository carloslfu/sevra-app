import CryptoKit
import Foundation

extension Workbook {
  /// Resolve exact retained changes, never an inferred whole-balance cause set.
  /// This read cannot grant execution or establish independent business roots.
  public func inventoryConditionOrigins(
    _ observationID: String, cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(
      !observationID.isEmpty && observationID.utf8.count <= 256,
      "condition_input", "Use an exact complete condition observation.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try readBusinessFeed(cancellation: control) {
      try inspectInventoryConditionOrigins(observationID, cancellation: control)
    }
  }

  func inspectInventoryConditionOrigins(_ observationID: String, cancellation: Cancellation)
    throws -> Value
  {
    let (row, observation) = try conditionInputObservation(observationID)
    try require(
      observation["changeInputs"]["coverage"] == .string("complete"),
      "condition_origin_coverage",
      "Only complete retained change windows have resolvable origins. Baseline, unknown-gap or overflow coverage cannot establish an origin."
    )
    let consumer = try inventoryConditionRow(row["consumer_id"]!.text)
    let window = try conditionBusinessInputSet(
      row, observation: observation, consumer: consumer, cancellation: cancellation)
    let origins = try inspectBusinessOrigins(
      inputs: window.inputs.sorted(), cancellation: cancellation)
    let result: Value = .object([
      "workbookID": .string(id), "policy": .string("condition-business-origins-v1"),
      "observationID": .string(observationID), "consumerID": row["consumer_id"]!,
      "knowledgeBatchID": observation["knowledgeBatchID"],
      "effectiveThrough": observation["effectiveThrough"],
      "previousObservationID": observation["previousObservationID"],
      "previousCertainObservationID": observation["previousCertainObservationID"],
      "retainedChangeInputs": observation["changeInputs"],
      "inputCount": .number(Double(window.count)), "inputSetHash": .string(window.hash),
      "inputInspection": .object([
        "command": .string("condition-inputs"), "observationID": .string(observationID),
      ]),
      "origins": origins,
      "automaticProducerRunIDs": .array(origins["automaticProducers"].array.map { $0["runID"] }),
      "coverage": .string("complete-retained-window-to-automatic-producers"),
      "minimalCauseSet": .bool(false), "independentBusinessRoots": .string("not-established"),
      "dispatchEligibility": .string("not-evaluated"), "execution": .string("none"),
      "enabled": .bool(false),
    ])
    try boundedBusinessOutput(result)
    try cancellation.check()
    return result
  }

  private func conditionBusinessInputSet(
    _ row: [String: Value], observation: Value, consumer: [String: Value],
    cancellation: Cancellation
  ) throws -> (inputs: Set<String>, count: Int, hash: String) {
    var inputs = Set<String>()
    var count = 0
    var after = ""
    var digest = SHA256()
    digest.update(data: Data("[".utf8))
    while true {
      try cancellation.check()
      let page = try db.execute(
        "SELECT id,CASE WHEN length(CAST(payload AS BLOB))<=16384 THEN payload END AS payload FROM condition_observation_inputs WHERE observation_id=? AND id>? ORDER BY id LIMIT 100",
        [row["id"]!, .string(after)], maxRows: 100, maxBytes: 2_097_152)
      if page.isEmpty { break }
      for member in page {
        try cancellation.check()
        try require(
          member["payload"] != .null, "condition_origin_limit", "A retained input exceeds 16 KiB.")
        let value = try Value.parse(member["payload"]!.text)
        try validateConditionInput(
          member["id"]!.text, value: value, consumer: consumer,
          batch: row["batch_id"]!.string, effective: row["effective"]!.text)
        for version in [value["beforeID"], value["afterID"]] {
          if let id = version.string { inputs.insert(id) }
        }
        try require(
          inputs.count <= 1024, "condition_origin_limit",
          "The complete window exceeds 1,024 starting versions. Its numeric state and paginated inputs remain available."
        )
        if count > 0 { digest.update(data: Data(",".utf8)) }
        digest.update(data: Data(try Value.array([member["id"]!, value]).json().utf8))
        count += 1
        try require(
          count <= ConditionInput.limit, "condition_origin_limit",
          "The retained window exceeds its input bound.")
        after = member["id"]!.text
      }
    }
    try require(
      count == observation["changeInputs"]["count"].int,
      "condition_input_integrity", "The complete window lost retained input members.")
    digest.update(data: Data("]".utf8))
    return (inputs, count, digest.finalize().map { String(format: "%02x", $0) }.joined())
  }
}
