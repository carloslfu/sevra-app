import SevraAI

func checkContextBudget() throws {
  for profile: ContextBudget.Profile in [.development8K, .evaluation32K, .evaluation64K] {
    let budget = ContextBudget(profile: profile)
    let ready = try budget.allowance(promptTokens: budget.maintenanceThreshold - 1)
    try expectEqual(ready.outputTokens, 1800)
    try expectEqual(ready.maintenanceRecommended, false)
    let maintenance = try budget.allowance(promptTokens: budget.maintenanceThreshold)
    try expectEqual(maintenance.maintenanceRecommended, true)
    try expectEqual(maintenance.outputTokens, 1800)
    try expectEqual(
      budget.contextTokens - budget.maintenanceThreshold,
      maintenance.outputTokens + budget.nextToolResultReserve + budget.recoveryReserve)
    let boundary = try budget.allowance(promptTokens: budget.contextTokens - 256)
    try expectEqual(boundary.outputTokens, 256)
    try expectEqual(boundary.maintenanceRecommended, true)
    for invalid in [-1, 0, budget.contextTokens - 255, budget.contextTokens, Int.max] {
      try expectThrows(try budget.allowance(promptTokens: invalid))
    }
  }
  try expectEqual(ContextBudget.Profile(rawValue: 16384), nil)
  try ContextBudget.validateEnvelope([
    InferenceMessage(role: "user", content: String(repeating: "a", count: 96_001))
  ])
  try expectThrows(try ContextBudget.validateEnvelope([]))
  try expectThrows(
    try ContextBudget.validateEnvelope(
      Array(repeating: InferenceMessage(role: "user", content: "a"), count: 513)))
  try expectThrows(
    try ContextBudget.validateEnvelope([
      InferenceMessage(
        role: "user", content: String(repeating: "é", count: ContextBudget.maximumMessageBytes / 2))
    ]))
  try expectThrows(
    try ContextBudget.validateEnvelope([
      InferenceMessage(
        role: "assistant", content: "",
        toolCalls: [
          InferenceCall(
            id: "a", name: "test",
            inputJSON: String(repeating: "x", count: ContextBudget.maximumMessageBytes))
        ])
    ]))
  print("PASS exact context budgets, proactive maintenance thresholds and exhausted-prompt refusal")
}
