import Foundation

public struct FormDraftAlternative: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let definitionID: String
  public let resolvedDefinitions: [String]
  public let arguments: Value
  public let invocationToken: String
  public let lastReceipt: Value?
  public init(
    id: String, definitionID: String, resolvedDefinitions: [String], arguments: Value,
    invocationToken: String, lastReceipt: Value?
  ) {
    self.id = id
    self.definitionID = definitionID
    self.resolvedDefinitions = resolvedDefinitions
    self.arguments = arguments
    self.invocationToken = invocationToken
    self.lastReceipt = lastReceipt
  }
}

/// Incomplete unsent values are a portable presentation checkpoint, not business evidence.
public struct FormDraftState: Codable, Equatable, Sendable {
  public var version = 1
  public var definitionID: String
  public var resolvedDefinitions: [String]
  public var arguments: Value = .object([:])
  public var invocationToken: String
  public var lastReceipt: Value?
  public var alternatives: [FormDraftAlternative] = []
  public static func componentKey(spaceID: String, componentID: String) throws -> String {
    try require(
      !spaceID.isEmpty && !componentID.isEmpty && spaceID.utf8.count <= 256
        && componentID.utf8.count <= 256,
      "form_draft", "Use bounded space and component identities.")
    return "component:"
      + ChangeFormat.hash(try Value.array([.string(spaceID), .string(componentID)]).json())
  }
  public init(
    definitionID: String, resolvedDefinitions: [String], invocationToken: String = identifier()
  ) {
    self.definitionID = definitionID
    self.resolvedDefinitions = resolvedDefinitions
    self.invocationToken = invocationToken
  }
}

extension Workbook {
  public func applicationFormContext(_ id: String, cancellation: Cancellation = .init()) throws
    -> Value
  {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          let definition = try applicationDefinition(id)
          try require(definition.kind == "form", "definition_kind", "Open a form definition.")
          let state = DefinitionEvaluation(control)
          try validateDefinitionGraph(definition, state: state, depth: 0)
          return .object([
            "definition": try encoded(definition),
            "resolvedDefinitions": .array(state.resolved.keys.sorted().map(Value.string)),
          ])
        }
      }
    }
  }
  public func newFormDraft(_ formID: String, cancellation: Cancellation = .init()) throws
    -> FormDraftState
  {
    let context = try applicationFormContext(formID, cancellation: cancellation)
    return .init(
      definitionID: context["definition"]["id"].text,
      resolvedDefinitions: context["resolvedDefinitions"].array.map(\.text))
  }
  public func previewFormDraft(_ state: FormDraftState, cancellation: Cancellation = .init()) throws
    -> Value
  {
    let control = Cancellation(parent: cancellation, deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction {
          try validateFormDraft(state)
          try require(
            state.lastReceipt == nil, "form_submitted",
            "This draft was submitted. Start a new entry explicitly.")
          let context = try applicationFormContext(state.definitionID, cancellation: control)
          try require(
            context["resolvedDefinitions"].array.map(\.text) == state.resolvedDefinitions,
            "stale_form_definition",
            "A live action or function changed. Your inputs are retained. Open the current definition explicitly before submitting."
          )
          let definition = try applicationDefinition(state.definitionID)
          if try DefinitionForm(DefinitionDescriptor(definition.content)).targetKind == "workflow" {
            return try workflowFormPlan(
              state.definitionID, arguments: state.arguments, cancellation: control)
          }
          return try applicationActionPlan(
            state.definitionID, arguments: state.arguments, cancellation: control)
        }
      }
    }
  }
  public func applicationFormReceipt(_ token: String, definitionID: String, arguments: Value)
    throws -> Value?
  {
    try synchronized {
      guard
        let row = try db.execute(
          "SELECT kind,request,result FROM operations WHERE id=?", [.string(token)]
        ).first
      else { return nil }
      let stored = try Value.parse(row["request"]!.text)["arguments"]
      try require(
        ["invoke_application_action", "submit_workflow_form"].contains(row["kind"]!.text)
          && stored["id"] == .string(definitionID)
          && stored["arguments"] == arguments, "action_token",
        "This retry identity belongs to another request.")
      return try Value.parse(row["result"]!.text)
    }
  }
  public func formDraft(_ key: String) throws -> FormDraftState? {
    let control = Cancellation(deadlineAfterSeconds: 3)
    return try synchronized(cancellation: control) {
      try db.budget(cancellation: control, seconds: 3) {
        try db.readTransaction { try readFormDraft(key) }
      }
    }
  }
  private func formDraftKey(_ key: String) throws -> String {
    try require(
      !key.isEmpty && key.utf8.count <= 512, "form_draft",
      "Use a nonempty draft key of at most 512 bytes.")
    return "form-draft:" + key
  }
  private func readFormDraft(_ key: String) throws -> FormDraftState? {
    let key = try formDraftKey(key)
    let size =
      try db.scalar("SELECT length(CAST(value AS BLOB)) FROM meta WHERE key=?", [.string(key)]).int
      ?? 0
    try require(size <= 1_000_000, "form_draft_limit", "The saved form draft exceeds 1 MB.")
    guard let raw = try db.scalar("SELECT value FROM meta WHERE key=?", [.string(key)]).string
    else { return nil }
    let state = try JSONDecoder().decode(FormDraftState.self, from: Data(raw.utf8))
    try validateFormDraft(state)
    return state
  }
  @discardableResult public func saveFormDraft(
    _ key: String, state: FormDraftState, expected: FormDraftState?, keepOther: Bool = false
  ) throws -> FormDraftState {
    try presentationMutation {
      let current = try readFormDraft(key)
      try require(
        current == expected || current == state || keepOther,
        "form_draft_conflict",
        "Another window changed this form draft. Your inputs are still here. Keep both drafts before continuing."
      )
      var saved = state
      if keepOther, let current, current != expected && current != state {
        let alternative = FormDraftAlternative(
          id: identifier(), definitionID: current.definitionID,
          resolvedDefinitions: current.resolvedDefinitions, arguments: current.arguments,
          invocationToken: current.invocationToken, lastReceipt: current.lastReceipt)
        saved.alternatives =
          current.alternatives
          + saved.alternatives.filter { candidate in
            !current.alternatives.contains(where: { $0.id == candidate.id })
          }
        saved.alternatives.append(alternative)
      }
      try validateFormDraft(saved)
      let encoded = try encoded(saved).json()
      try require(
        encoded.utf8.count <= 1_000_000, "form_draft_limit",
        "Form drafts and alternatives exceed 1 MB.")
      let storageKey = try formDraftKey(key)
      if current == nil {
        try require(
          try db.scalar("SELECT count(*) FROM meta WHERE key LIKE 'form-draft:%'").int ?? 0 < 256,
          "form_draft_limit", "This workbook already has 256 form drafts.")
      }
      try db.execute(
        "INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        [.string(storageKey), .string(encoded)])
      return saved
    }
  }

  func validateFormDraft(_ state: FormDraftState) throws {
    try require(
      state.version == 1 && state.alternatives.count <= 8
        && Set(state.alternatives.map(\.id)).count == state.alternatives.count,
      "form_draft_limit", "Use the current draft version and at most eight saved alternatives.")
    func validate(
      _ id: String, _ bindings: [String], _ arguments: Value, _ token: String, _ receipt: Value?
    ) throws {
      let definition = try applicationDefinition(id)
      try require(
        definition.id == id && definition.kind == "form" && bindings.contains(id)
          && !bindings.isEmpty && bindings.count <= 128 && Set(bindings).count == bindings.count
          && bindings == bindings.sorted() && !token.isEmpty && token.utf8.count <= 256,
        "form_draft", "A draft needs an exact local form, bound definitions and a retry identity.")
      for binding in bindings {
        try require(
          try applicationDefinition(binding).id == binding, "form_draft",
          "Draft bindings need exact local definitions.")
      }
      let descriptor = try DefinitionDescriptor(definition.content)
      guard case .object(let values) = arguments,
        Set(values.keys).isSubset(of: descriptor.parameters.map(\.id)),
        try arguments.json().utf8.count <= 64_000
      else {
        throw SevraError(
          "form_draft_limit", "Keep incomplete form inputs within 64 KB and declared fields.")
      }
      if let receipt {
        guard
          try applicationFormReceipt(token, definitionID: id, arguments: arguments) == receipt,
          receipt["definitionID"] == .string(id)
        else {
          throw SevraError(
            "form_draft", "A submitted form must reference its exact saved invocation receipt.")
        }
      }
    }
    try validate(
      state.definitionID, state.resolvedDefinitions, state.arguments, state.invocationToken,
      state.lastReceipt)
    for saved in state.alternatives {
      try require(
        UUID(uuidString: saved.id) != nil, "form_draft", "Saved alternatives need unique IDs.")
      try validate(
        saved.definitionID, saved.resolvedDefinitions, saved.arguments, saved.invocationToken,
        saved.lastReceipt)
    }
  }
  func verifyFormDrafts() throws {
    let rows = try db.execute(
      "SELECT key FROM meta WHERE key LIKE 'form-draft:%' ORDER BY key LIMIT 257")
    try require(rows.count <= 256, "form_draft_limit", "Too many saved form drafts.")
    for row in rows {
      _ = try readFormDraft(String(row["key"]!.text.dropFirst("form-draft:".count)))
    }
  }
}
