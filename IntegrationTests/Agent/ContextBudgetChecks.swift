import SevraAI

func checkContextBudget() throws {
  for profile: ContextBudget.Profile in [
    .development8K, .evaluation32K, .evaluation64K, .evaluation128K, .evaluation256K,
  ] {
    let budget = ContextBudget(profile: profile)
    for output in [1400, 1800, 4096, 8192] {
      let reserve = output == 1400 ? 0 : 2048
      let maximum = budget.contextTokens - output - reserve - 256
      if maximum <= 0 {
        try expectThrows(try budget.allowance(promptTokens: 1, outputTokens: output))
        continue
      }
      let threshold = ContextBudget.maintenanceThreshold(
        capacity: budget.contextTokens, outputTokens: output, toolResultTokens: reserve)
      for prompt in [threshold - 1, threshold, threshold + 1] where prompt > 0 && prompt <= maximum
      {
        let allowance = try budget.allowance(
          promptTokens: prompt, outputTokens: output, toolResultTokens: reserve)
        try expectEqual(allowance.outputTokens, output)
        try expectEqual(allowance.maintenanceRecommended, prompt >= threshold)
      }
      let measurement = ContextMeasurement(
        promptTokens: maximum, capacity: budget.contextTokens,
        templateIdentity: "test", outputTokens: output, toolResultTokens: reserve)
      try expectEqual(measurement.maximumPrompt, maximum)
      try expectEqual(measurement.threshold, threshold)
      try expectEqual(
        try budget.allowance(
          promptTokens: maximum, outputTokens: output,
          toolResultTokens: reserve
        ).outputTokens, output)
      for invalid in [-1, 0, maximum + 1, budget.contextTokens, Int.max] {
        try expectThrows(
          try budget.allowance(
            promptTokens: invalid, outputTokens: output,
            toolResultTokens: reserve))
      }
    }
  }
  try expectEqual(ContextBudget.maintenanceThreshold(capacity: 32768, outputTokens: 8192), 22272)
  try expectEqual(ContextBudget(profile: .development8K).maintenanceThreshold, 4088)
  try expectEqual(ContextBudget(profile: .evaluation32K).maintenanceThreshold, 24576)
  try expectEqual(ContextBudget(profile: .evaluation64K).maintenanceThreshold, 49152)
  try expectEqual(ContextBudget.maintenanceThreshold(capacity: 32771), 24578)
  try expectEqual(ContextBudget.maintenanceThreshold(capacity: 0), 0)
  try expectEqual(ContextBudget.maintenanceThreshold(capacity: -1), 0)
  try expectEqual(ContextBudget.maintenanceThreshold(capacity: Int.max) > 0, true)
  try expectEqual(ContextBudget.Profile(rawValue: 16384), nil)
  // Ready may admit less than requested. Never use configured capacity to overrun it.
  try expectThrows(
    try ContextBudget(profile: .evaluation64K).allowance(
      promptTokens: 30000, capacity: 32768))
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
