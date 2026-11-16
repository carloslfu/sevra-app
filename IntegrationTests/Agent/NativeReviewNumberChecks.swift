import Foundation
import SevraAppProtocol

@testable import SevraAI
@testable import SevraCore

/// A separate scope lets the test supply the authority without weakening the
/// worker evidence or changing the builder's ordinary review responses.
private actor NumericRulingTestModel: WorkbookInference {
  let identity = "synthetic numeric review"
  let lastMetrics: Value = .object([:])
  private let reviewer: ExcelTestModel
  private var interpretations: [Value]
  private(set) var interpretationRequests: [Value] = []

  init(_ actions: [(String, Value)], reviews: [Value], interpretations: [Value]) {
    reviewer = ExcelTestModel(actions, reviews: reviews)
    self.interpretations = interpretations
  }

  var reviewInputs: [Value] { get async { await reviewer.reviewInputs } }
  var toolResults: [Value] { get async { await reviewer.toolResults } }
  func beginRun() {}
  func endRun() {}
  func interpret(
    request: Value, directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void
  ) async throws -> Value {
    try cancellation.check()
    interpretationRequests.append(request)
    try require(!interpretations.isEmpty, "fixture", "Unexpected structured interpretation.")
    return .object(["response": interpretations.removeFirst()])
  }
  func respond(
    messages: [InferenceMessage], directory: URL, cancellation: Cancellation,
    progress: @escaping @Sendable (String) -> Void, toolScope: InferenceToolScope,
    citationIDs: [String]
  ) async throws -> NativeReply {
    try await reviewer.respond(
      messages: messages, directory: directory, cancellation: cancellation,
      progress: progress, toolScope: toolScope, citationIDs: citationIDs)
  }
}

func checkNativeReviewNumbers(
  package: NativeAppPackage, workbook: Workbook, build: ExcelConversionBuild,
  requestSourceID: String, directory: URL
) async throws {
  let role: Value = .object([
    "kind": .string("number"), "minimum": .number(1), "maximum": .number(3),
    "whole": .bool(true), "nonzero": .bool(false),
  ])
  let probes = try NativeAppReview.numberProbes(role: role, input: .number(1))
  try expectEqual(probes.map(\.0), ["whole", "minimum", "maximum"])
  try expectEqual(probes.map(\.1), [.number(1.5), .number(0), .number(4)])
  try expectEqual(
    try NativeAppReview.numberProbes(role: role, input: .number(3))[0].1, .number(2.5))
  try expectEqual(
    try NativeAppReview.numberProbes(role: role, input: .string("1")).map(\.1),
    [.string("1.5"), .string("0"), .string("4")])
  var narrow = role.object
  narrow["maximum"] = .number(1.2)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(narrow), input: .number(1)).map(\.1),
    [.number(1.1), .number(0), .number(2)])
  narrow["minimum"] = .number(0.8)
  narrow["maximum"] = .number(1)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(narrow), input: .number(1)).map(\.1),
    [.number(0.9), .number(0), .number(2)])
  narrow["minimum"] = .number(1.5)
  narrow["maximum"] = .number(3.25)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(narrow), input: .number(2)).map(\.1),
    [.number(2.5), .number(1), .number(4)])
  narrow["minimum"] = .number(-3.25)
  narrow["maximum"] = .number(-1.5)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(narrow), input: .number(-2)).map(\.1),
    [.number(-1.5), .number(-4), .number(-1)])
  var nonzero = role.object
  nonzero["nonzero"] = .bool(true)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(nonzero), input: .number(1)).map(\.1),
    [.number(1.5), .number(-1), .number(4), .number(0)])
  nonzero["minimum"] = .number(-3)
  nonzero["maximum"] = .number(-1)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(nonzero), input: .number(-1)).map(\.1),
    [.number(-1.5), .number(-4), .number(1), .number(0)])
  var positive = role.object
  positive["minimum"] = .number(0)
  positive["maximum"] = .null
  positive["whole"] = .bool(false)
  positive["nonzero"] = .bool(true)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(positive), input: .string("2.25")).map(\.1),
    [.string("-1"), .string("0")])
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(positive), input: .string("2")).map(\.0),
    ["minimum", "nonzero", "allowed_fraction"])
  var permissive = positive
  permissive["minimum"] = .null
  permissive["nonzero"] = .bool(false)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(permissive), input: .number(-2)).map(\.1),
    [.number(0), .number(-1.5)])
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(permissive), input: .string("0")).count, 0)
  try expectEqual(
    try NativeAppReview.numberProbes(role: .object(permissive), input: .number(1e16)).map(\.0),
    ["allowed_zero"])
  for invalid in [
    Value.number(0), .number(1.5), .number(4), .number(.infinity), .string("bad"), .bool(true),
  ] {
    try expectThrows(try NativeAppReview.numberProbes(role: role, input: invalid))
  }
  for (field, invalid) in [
    ("minimum", Value.string("1")), ("maximum", .number(0)),
    ("whole", .string("true")), ("kind", .string("value")), ("nonzero", .null),
    ("extra", .bool(true)),
  ] {
    var changed = role.object
    changed[field] = invalid
    try expectThrows(try NativeAppReview.numberProbes(role: .object(changed), input: .number(1)))
  }
  var missing = role.object
  missing.removeValue(forKey: "maximum")
  try expectThrows(try NativeAppReview.numberProbes(role: .object(missing), input: .number(1)))
  var precision = role.object
  precision["minimum"] = .number(1e38)
  precision["maximum"] = .null
  try expectThrows(try NativeAppReview.numberProbes(role: .object(precision), input: .number(1e38)))

  // Report every misclassified numeric input together. String-encoded decimals
  // must not be mistaken for text or turned into SDK metadata by a later repair.
  let numericContracts: Value = .object([
    "price": .object([
      "amount": .object(["type": .string("decimal"), "valueType": .string("string")]),
      "count": .object(["type": .string("number"), "valueType": .string("number")]),
      "note": .object(["type": .string("text"), "valueType": .string("string")]),
    ])
  ])
  try expectEqual(NativeAppReview.numericInputs(numericContracts).array.count, 2)
  let misclassified: Value = .object([
    "price": .object([
      "amount": .object(["kind": .string("value")]),
      "count": .object(["kind": .string("value")]),
    ])
  ])
  var classificationFailure = ""
  do {
    _ = try NativeAppReview.inputProbes(
      actions: ["price"], roles: misclassified,
      steps: [
        .object([
          "kind": .string("run_action"), "action": .string("price"),
          "inputs": .object(["amount": .string("1"), "count": .number(2)]),
        ]),
        .object(["kind": .string("expect_text"), "value": .string("Quoted")]),
      ], fixtures: .object([:]),
      inputTypes: .object([
        "0": .object(["amount": .string("decimal"), "count": .string("number")])
      ]),
      package: package, tables: build.tables, coordinates: [], inputCell: { _ in .null })
  } catch { classificationFailure = error.localizedDescription }
  try expectEqual(classificationFailure.contains("price.amount (decimal)"), true)
  try expectEqual(classificationFailure.contains("price.count (number)"), true)
  try expectEqual(classificationFailure.contains("review-only inputRoles"), true)

  // Real isolated worker: a positive-only independent review must not accept
  // validation performed AFTER parseInt has silently truncated a fractional input.
  var candidate = package
  candidate.source = """
    const result=Sevra.signal('Ready');
    Sevra.action('chooseMonth',{title:'Choose month',inputs:{month:{type:'number',required:true}}},input=>{
      const month=parseInt(input.month,10);
      if(!Number.isInteger(month)||month<1||month>3)throw Error('Month must be a whole number from 1 to 3');
      result.value='Month '+month;
    });
    Sevra.mount(Sevra.h(Sevra.Text,{text:result}));
    """
  let review: Value = .object([
    "decision": .string("ready"), "issues": .array([]),
    "inputRoles": .object(["chooseMonth": .object(["month": role])]),
    "tests": .array([
      .object([
        "kind": .string("run_action"), "action": .string("chooseMonth"),
        "inputs": .object(["month": .number(1)]),
      ]),
      .object(["kind": .string("expect_text"), "value": .string("Month 1")]),
    ]),
  ])
  var flatReview = review.object
  flatReview["inputRoles"] = .object(["month": .object(["kind": role])])
  let repeatedField =
    review["tests"].array + [
      .object([
        "kind": .string("run_action"), "action": .string("cancelMonth"),
        "inputs": .object(["month": .number(1)]),
      ]),
      .object(["kind": .string("expect_text"), "value": .string("Cancelled")]),
    ]
  try expectEqual(
    NativeAppReview.actionIndexedRoles(
      flatReview["inputRoles"]!, actions: ["chooseMonth", "cancelMonth"],
      registeredActions: ["chooseMonth", "cancelMonth"], steps: repeatedField),
    flatReview["inputRoles"]!)
  let contracts = try await NativeAppCheck.run(
    package: candidate,
    steps: [
      .object(["kind": .string("expect_text"), "value": .string("Ready")])
    ] + review["tests"].array)
  try expectEqual(contracts["actionInputs"]["chooseMonth"]["month"]["type"], .string("number"))
  try expectEqual(contracts["actionInputs"]["chooseMonth"]["month"]["valueType"], .string("number"))
  let monthPurpose = "Choose a month, a whole number from 1 to 3."
  let costPurpose =
    "Update unit cost using the explicit supplied price. The order quantity must be positive."
  func reviewBuild(purpose: String) throws -> ExcelConversionBuild {
    var context = try Value.parse(build.context).object
    context["userClarification"] = .string(purpose)
    return .init(
      physicalID: build.physicalID, workbookID: build.workbookID, conversionID: build.conversionID,
      conversionVersion: build.conversionVersion, sourceID: build.sourceID, tables: build.tables,
      appVersion: build.appVersion, context: try Value.object(context).json(),
      request: build.request, displayRequest: build.displayRequest)
  }
  func decision(_ name: String, _ evidence: String = "") -> Value {
    .object(["decision": .string(name), "evidence": .string(evidence)])
  }
  let monthRestriction = decision("forbid", monthPurpose)
  let allowCost = decision("allow")
  func check(
    _ candidate: NativeAppPackage, verdict: Value = review,
    model supplied: NumericRulingTestModel? = nil
  ) async throws -> Value {
    let model =
      supplied
      ?? NumericRulingTestModel(
        [], reviews: Array(repeating: verdict, count: 3), interpretations: [monthRestriction])
    let result = try await NativeAppReview.check(
      request: monthPurpose, requestSourceID: requestSourceID,
      arguments: .object([
        "package": try encoded(candidate), "tests": review["tests"], "fixtures": .object([:]),
      ]),
      workbook: workbook, model: model,
      directory: directory,
      cancellation: .init(), progress: { _ in },
      excelConversion: try reviewBuild(purpose: monthPurpose),
      checkedActions: ["chooseMonth"], checkedActionInputs: contracts["actionInputs"],
      checkedInterface: contracts["initialInterface"])
    try expectEqual(
      await model.reviewInputs.first?["checkedActionInputs"], contracts["actionInputs"])
    try expectEqual(
      await model.reviewInputs.first?["checkedInterface"], contracts["initialInterface"])
    try expectEqual(
      await model.reviewInputs.first?["numericInputs"],
      .array([
        .object([
          "action": .string("chooseMonth"), "input": .string("month"),
          "type": .string("number"), "valueType": .string("number"),
        ])
      ]))
    return result
  }
  let confirmingModel = NumericRulingTestModel(
    [], reviews: [.object(flatReview)], interpretations: [monthRestriction])
  var failure = ""
  do {
    _ = try await check(candidate, model: confirmingModel)
    throw SevraError("regression", "The isolated worker accepted a forbidden fractional month.")
  } catch {
    try expectEqual((error as? SevraError)?.code, "app_review")
    failure = error.localizedDescription
  }
  try expectEqual(failure.contains("confirmed the disputed rule for chooseMonth.month (1.5)"), true)
  try expectEqual(failure.contains("Refuse this value without a write."), true)
  try expectEqual(await confirmingModel.reviewInputs.count, 1)
  let questions = await confirmingModel.interpretationRequests
  try expectEqual(questions.count, 1)
  let blind = try Value.parse(questions[0]["messages"].array[1]["content"].text)
  try expectEqual(
    Set(blind.object.keys),
    [
      "originalRequest", "originalWorkbookRules", "actionTitle", "inputID", "inputTitle",
      "inputValue",
    ])
  try expectEqual(blind["originalRequest"], .string(monthPurpose))
  try expectEqual(blind["inputValue"], .number(1.5))
  try expectThrows(
    try NativeAppReview.numericRuleDecision(
      decision("forbid", "invented provenance"), originalRequest: monthPurpose, sourceRules: [],
      inputNames: ["month"]))
  try expectThrows(
    try NativeAppReview.numericRuleDecision(
      decision("unclear"), originalRequest: monthPurpose, sourceRules: [], inputNames: ["month"]))
  try expectThrows(
    try NativeAppReview.numericRuleDecision(
      decision("forbid"), originalRequest: monthPurpose, sourceRules: [], inputNames: ["month"]))
  try expectThrows(
    try NativeAppReview.numericRuleDecision(
      decision("forbid", "The order quantity must be positive."),
      originalRequest: costPurpose, sourceRules: [], inputNames: ["unitCost", "Unit cost"]))

  try expectThrows(
    try NativeAppReview.numericRuleDecision(
      decision("forbid", costPurpose), originalRequest: costPurpose, sourceRules: [],
      inputNames: ["unitCost", "Unit cost"]))
  try expectThrows(
    try NativeAppReview.numericRuleDecision(
      decision("allow", String(repeating: "a", count: 361)),
      originalRequest: String(repeating: "a", count: 361), sourceRules: [], inputNames: ["a"]))

  // A price has no requested positivity rule. A review that invents nonzero
  // must correct its own classification, without asking the author to reject zero.
  var cost = package
  cost.source = """
    const result=Sevra.signal('Ready');
    Sevra.action('updateCost',{title:'Update unit cost',inputs:{cost:{type:'decimal',required:true}}},input=>{
      result.value='Cost '+input.cost;
    });
    Sevra.mount(Sevra.h(Sevra.Text,{text:result}));
    """
  var unconstrained = positive
  unconstrained["minimum"] = .null
  unconstrained["nonzero"] = .bool(false)
  let costTests: Value = .array([
    .object([
      "kind": .string("run_action"), "action": .string("updateCost"),
      "inputs": .object(["cost": .string("3.75")]),
    ]),
    .object(["kind": .string("expect_text"), "value": .string("Cost 3.75")]),
  ])
  let costContracts = try await NativeAppCheck.run(package: cost, steps: costTests.array)
  // A lone nonzero rule reproduces the live failure without a second invented bound.
  var wrongCostRole = unconstrained
  wrongCostRole["nonzero"] = .bool(true)
  let wrongCostReview: [String: Value] = [
    "decision": .string("ready"), "issues": .array([]), "tests": costTests,
    "inputRoles": .object(["updateCost": .object(["cost": .object(wrongCostRole)])]),
  ]
  var correctedCostReview = wrongCostReview
  correctedCostReview["inputRoles"] = .object([
    "updateCost": .object(["cost": .object(unconstrained)])
  ])
  correctedCostReview["tests"] = .array(
    costTests.array + [
      .object([
        "kind": .string("run_action"), "action": .string("updateCost"),
        "inputs": .object(["cost": .string("0")]),
      ]),
      .object(["kind": .string("expect_text"), "value": .string("Cost 0")]),
    ])
  let correctingModel = NumericRulingTestModel(
    [],
    reviews: [.object(wrongCostReview), .object(wrongCostReview), .object(correctedCostReview)],
    interpretations: [allowCost])
  let costAccepted = try await NativeAppReview.check(
    request: costPurpose,
    requestSourceID: requestSourceID,
    arguments: .object(["package": try encoded(cost), "tests": costTests, "fixtures": .object([:])]
    ),
    workbook: workbook, model: correctingModel, directory: directory, cancellation: .init(),
    progress: { _ in }, excelConversion: try reviewBuild(purpose: costPurpose),
    checkedActions: ["updateCost"],
    checkedActionInputs: costContracts["actionInputs"],
    checkedInterface: costContracts["initialInterface"])
  try expectEqual(await correctingModel.reviewInputs.count, 3)
  try expectEqual(await correctingModel.interpretationRequests.count, 1)
  try expectEqual(
    await correctingModel.toolResults.last?["error"].text.contains("already resolved"), true)
  try expectEqual(
    await correctingModel.toolResults.first?["status"], .string("resolved_input_rule"))
  try expectEqual(costAccepted["digest"], .string(cost.digest))
  try expectEqual(costAccepted["checkedCounterexamples"].array.count, 2)
  try expectEqual(
    costAccepted["checkedCounterexamples"].array[0]["verdict"],
    pairedActionReviewFixture(.object(wrongCostReview)))
  try expectEqual(
    costAccepted["checkedCounterexamples"].array[0]["result"]["status"],
    .string("resolved_input_rule"))
  let costChecks = costAccepted["independentActionCheck"]["checks"].array
  try expectEqual(costChecks.count, 1)
  try expectEqual(costChecks[0]["tests"], correctedCostReview["tests"])
  let resolvedZero = NativeAppReview.NumericRuling(
    dispute: .init(
      probe: .object([
        "action": .string("updateCost"), "input": .string("cost"), "value": .string("0"),
        "rule": .string("nonzero"),
      ]), failure: "The old role expected refusal"),
    accepted: true)
  try expectEqual(resolvedZero.invalidatesReadiness(.object(wrongCostReview)), true)
  try expectEqual(resolvedZero.invalidatesReadiness(costChecks[0]), false)
  try expectEqual(
    resolvedZero.invalidatesReadiness(.object(["inputRoles": review["inputRoles"]])), false)
  let costBoundary = try expectValue(costChecks[0]["inputChecks"].array.first)
  try expectEqual(costBoundary["rule"], .string("allowed_zero"))
  try expectEqual(costBoundary["tests"].array.count, 1)
  try expectEqual(costBoundary["tests"].array[0]["reject"], .null)
  try expectEqual(costBoundary["tests"].array[0]["inputs"]["cost"], .string("0"))
  try expectEqual(costBoundary["check"]["assertions"], .number(1))
  // Live Stock accepted a normal price but unconditionally refused zero.
  // It must fail independent review even if the reviewer only supplies a normal price.
  var strictCost = cost
  strictCost.source = strictCost.source.replacingOccurrences(
    of: "result.value='Cost '+input.cost;",
    with:
      "if(Number(input.cost)<=0)throw Error('Cost must be positive');result.value='Cost '+input.cost;"
  )
  var strictVerdict = correctedCostReview
  strictVerdict["tests"] = costTests
  let unprovenCost = NumericRulingTestModel(
    [], reviews: [.object(strictVerdict), .object(wrongCostReview)], interpretations: [allowCost])
  var allowedFailure = ""
  do {
    _ = try await NativeAppReview.check(
      request: costPurpose,
      requestSourceID: requestSourceID,
      arguments: .object([
        "package": try encoded(strictCost), "tests": costTests, "fixtures": .object([:]),
      ]),
      workbook: workbook, model: unprovenCost, directory: directory, cancellation: .init(),
      progress: { _ in }, excelConversion: try reviewBuild(purpose: costPurpose),
      checkedActions: ["updateCost"],
      checkedActionInputs: costContracts["actionInputs"])
    throw SevraError("regression", "A positive-only price passed its allowed zero probe.")
  } catch {
    try expectEqual((error as? SevraError)?.code, "app_review")
    allowedFailure = error.localizedDescription
  }
  try expectEqual(
    allowedFailure.contains("Accept this value when the other business prerequisites hold"), true)
  try expectEqual(await unprovenCost.reviewInputs.count, 1)
  try expectEqual(allowedFailure.contains("Cost must be positive"), true)
  candidate.source = candidate.source.replacingOccurrences(
    of: "parseInt(input.month,10)", with: "input.month")
  let accepted = try await check(candidate)
  let checks = accepted["independentActionCheck"]["checks"].array
  try expectEqual(checks[0]["check"]["actionInputTypes"]["0"]["month"], .string("number"))
  let derived = checks[0]["inputChecks"].array
  try expectEqual(derived.count, 3)
  for probe in derived {
    try expectEqual(probe["tests"].array.count, 1)
    try expectEqual(probe["tests"].array[0]["reject"], .bool(true))
    try expectEqual(probe["check"]["status"], .string("passed"))
  }
  // Rejecting without writes can still mutate in-memory state. A prior refused
  // fraction must not mask an absent upper-bound check on a later input.
  var masking = candidate
  masking.source = """
    let blocked=false; const result=Sevra.signal('Ready');
    Sevra.action('chooseMonth',{title:'Choose month',inputs:{month:{type:'number',required:true}}},input=>{
      if(blocked)throw Error('Temporarily blocked');
      if(!Number.isInteger(input.month)||input.month<1){blocked=true;throw Error('Invalid month');}
      result.value='Month '+input.month;
    });
    Sevra.mount(Sevra.h(Sevra.Text,{text:result}));
    """
  var maskingFailure = ""
  do { _ = try await check(masking) } catch { maskingFailure = error.localizedDescription }
  try expectEqual(maskingFailure.contains("Refuse this value without a write."), true)
  var hidden = review.object
  hidden["inputRoles"] = .object([
    "chooseMonth": .object(["month": .object(["kind": .string("value")])])
  ])
  var hiddenFailure = ""
  do { _ = try await check(candidate, verdict: .object(hidden)) } catch {
    hiddenFailure = error.localizedDescription
  }
  try expectEqual(hiddenFailure.contains("chooseMonth.month (number)"), true)
  try expectEqual(hiddenFailure.contains("review-only inputRoles"), true)
  print(
    "PASS independent numeric probes: truncation refused, typed boundaries checked, numeric value-role bypass refused"
  )
}
