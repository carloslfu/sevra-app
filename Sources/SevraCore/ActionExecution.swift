import Foundation

extension Workbook {
  /// A preview grants no authority and publishes no mutation, receipt or Source.
  public func previewApplicationAction(
    _ id: String, arguments: Value, cancellation: Cancellation = .init()
  ) throws -> Value {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          try self.applicationActionPlan(id, arguments: arguments, cancellation: control)
        }
      }
    }
  }

  @discardableResult public func invokeApplicationAction(
    _ id: String, arguments: Value, preview: Value, token: String,
    requestSourceID: String? = nil, readOnly: Bool = false, actor: ChangeActor? = nil,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try require(!readOnly, "read_only_request", "This request does not permit changes.")
    try require(
      !token.isEmpty && token.utf8.count <= 256, "action_token",
      "Use a bounded nonempty retry token.")
    let actual = actor ?? ChangeAttribution.actor ?? .programmatic("SevraCore.applicationAction")
    let request: Value = .object([
      "id": .string(id), "arguments": arguments, "preview": preview,
      "requestSourceID": requestSourceID.map(Value.string) ?? .null,
    ])
    try require(
      try request.json().utf8.count <= 256_000, "action_limit", "Action request exceeds 256 KB.")
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try mutation(
      "invoke_application_action", token: token, request: request, cancellation: control,
      actor: actual
    ) {
      let plan = try self.applicationActionPlan(id, arguments: arguments, cancellation: control)
      try require(
        plan == preview, "stale_action_preview",
        "The action or its inputs changed. Keep your draft and preview it again.")
      if let requestSourceID {
        let source = try self.item(requestSourceID)
        try require(
          source.id == requestSourceID && source.category == "source" && source.kind == "request",
          "movement_request", "Use the captured current request Source.")
      }
      let definitionInputs = plan["resolvedDefinitions"].array.map { $0["sourceID"].text }
      let invocation = try self.insertItem(
        category: "source", kind: "application_invocation",
        title: "Submitted " + plan["title"].text,
        text: actual.label + " submitted draft inventory proposals. Acceptance remains separate.",
        data: .object(["submitted": request, "plan": plan, "actor": try encoded(actual)]),
        meaning: "actual", status: "accepted", scenario: "actual",
        inputs: Array(
          Set(
            definitionInputs + [plan["primitiveArguments"]["evidence"].text]
              + (requestSourceID.map { [$0] } ?? []))
        ).sorted(),
        transformation: "application-action-invocation-v1")
      var proposals: [Value] = []
      for raw in plan["movements"].array {
        try control.check()
        var movement = raw.object
        if let requestSourceID { movement["requestSourceID"] = .string(requestSourceID) }
        let proposal = try self.insertMovement(.object(movement), additionalInputs: [invocation])
        proposals.append(.string(proposal))
      }
      return .object([
        "workbookID": .string(self.id), "definitionID": plan["definitionID"],
        "sourceID": .string(invocation), "proposals": .array(proposals),
        "state": .string("draft"), "acceptedBalanceChanged": .bool(false),
        "resolvedDefinitions": plan["resolvedDefinitions"], "fingerprint": plan["fingerprint"],
      ])
    }
  }

  func applicationActionPlan(_ id: String, arguments: Value, cancellation: Cancellation) throws
    -> Value
  {
    let root = try applicationDefinition(id)
    let descriptor = try DefinitionDescriptor(root.content)
    try require(
      ["action", "form"].contains(root.kind), "definition_kind", "Preview an action or form.")
    let supplied = try definitionArguments(descriptor, arguments)
    let state = DefinitionEvaluation(cancellation)
    try state.enter(root, depth: 0)
    let action: ApplicationDefinition
    if root.kind == "form" {
      let form = try DefinitionForm(descriptor)
      action = try resolveDefinition(form.binding)
      try validateForm(form, descriptor: descriptor, action: action)
      try state.enter(action, depth: 1)
    } else {
      action = root
    }
    let actionDescriptor = try DefinitionDescriptor(action.content)
    let primitive = try DefinitionAction(actionDescriptor)
    let mapped = try validateActionMapping(
      primitive, caller: actionDescriptor, state: state,
      arguments: supplied, depth: root.kind == "form" ? 1 : 0)
    let movements =
      try primitive.primitiveID == ActionRegistry.receivingID
      ? receivingMovements(mapped) : proposedMovements(mapped)
    for movement in movements {
      try cancellation.check()
      try validateMovement(movement)
    }
    var plan: [String: Value] = [
      "workbookID": .string(self.id), "requestedID": .string(id), "definitionID": .string(root.id),
      "actionID": .string(action.id), "title": .string(root.title), "arguments": .object(supplied),
      "submittedArguments": arguments, "primitiveArguments": .object(mapped),
      "primitive": .object([
        "id": .string(primitive.primitiveID),
        "version": .number(Double(primitive.primitiveVersion)),
      ]),
      "resolvedDefinitions": .array(
        state.resolved.values.sorted { $0.id < $1.id }.map {
          .object([
            "id": .string($0.id), "logicalID": .string($0.logicalID),
            "sourceID": .string($0.sourceID),
          ])
        }),
      "movements": .array(movements), "readOnly": .bool(true),
      "effect": .string(
        "Save \(movements.count) draft actual inventory proposals. Balances change only after separate review and acceptance."
      ),
      "units": .string("discrete items"),
    ]
    plan["fingerprint"] = .string(ChangeFormat.hash(try Value.object(plan).json()))
    return .object(plan)
  }

  private func proposedMovements(_ arguments: [String: Value]) throws -> [Value] {
    let quantity = try Numbers.decimal(arguments["quantity"]!.text)
    var original = quantity
    var rounded = Decimal()
    NSDecimalRound(&rounded, &original, 0, .plain)
    try require(
      quantity != 0 && quantity == rounded, "action_input",
      "A signed item count must be a nonzero whole number.")
    try require(
      arguments["subject"]!.text.utf8.count <= 512
        && arguments["occurrence"]!.text.utf8.count <= 512,
      "action_input", "Inventory subject and occurrence must be at most 512 bytes.")
    return [
      try movementRequest(
        subject: arguments["subject"]!.text, quantity: Numbers.string(quantity),
        occurrence: arguments["occurrence"]!.text, effective: arguments["effective"]!.text,
        input: arguments["evidence"]!.text, meaning: arguments["meaning"]!.text,
        supersedes: arguments["supersedes"]?.string)
    ]
  }

  private func receivingMovements(_ arguments: [String: Value]) throws -> [Value] {
    let delivery = arguments["delivery"]!.text
    try require(
      !delivery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && delivery.utf8.count <= 512,
      "action_input", "Enter a delivery identity of at most 512 bytes from your business evidence.")
    let evidence = arguments["evidence"]!.text
    let effective = arguments["effective"]!.text
    var lines = Set<String>()
    var movements: [Value] = []
    for row in arguments["lines"]!.array {
      let line = row["line"].text
      let subject = row["subject"].text
      let quantity = try Numbers.decimal(row["quantity"].text)
      var original = quantity
      var rounded = Decimal()
      NSDecimalRound(&rounded, &original, 0, .plain)
      try require(
        quantity > 0 && quantity == rounded, "action_input",
        "A received item count must be a positive whole number.")
      try require(
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && line.utf8.count <= 256
          && lines.insert(line).inserted,
        "action_input",
        "Each delivery needs distinct nonempty line identities of at most 256 bytes.")
      try require(
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && subject.utf8.count <= 512,
        "action_input", "Enter an inventory subject of at most 512 bytes.")
      let occurrence =
        "delivery:" + ChangeFormat.hash(try Value.array([.string(delivery), .string(line)]).json())
      // A delivery-line identity is unique across subjects. Editing the SKU cannot duplicate a line.
      try require(
        try db.scalar(
          "SELECT count(*) FROM effects WHERE occurrence=? AND kind='inventory'",
          [.string(occurrence)]
        ).int == 0,
        "duplicate_effect",
        "This delivery line already has a proposal. Review or correct its existing record.")
      movements.append(
        try movementRequest(
          subject: subject, quantity: Numbers.string(quantity),
          occurrence: occurrence, effective: effective, input: evidence))
    }
    return movements
  }
}
