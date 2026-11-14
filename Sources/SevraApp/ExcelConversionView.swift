import Foundation
import SevraCore
import SevraProduct
import SwiftUI
import UniformTypeIdentifiers

/// Conversion context belongs to the native host, so generated code cannot hide its limits.
@MainActor
struct ExcelAppOriginView: View {
  let spaceID: String
  @ObservedObject var state: WorkspaceState
  @State private var conversion: ExcelConversion?
  var body: some View {
    VStack(spacing: 0) {
      if let conversion, conversion.appID == spaceID {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            Text("From " + conversion.record.title).readingFont(.caption).lineLimit(2)
            Text(
              conversion.record.data["comparison"]["compared"].int.map {
                "\($0) saved results compared. See import details for coverage."
              } ?? "Review the original and the behavior recreated for this workspace."
            )
            .readingFont(.caption).foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          Button("Import details") { state.navigate(.excelImport(conversion.id)) }.buttonStyle(
            .link)
        }.padding(.horizontal, 20).padding(.top, 16)
      }
    }.task(id: spaceID) {
      guard let book = state.workbook else { return }
      let draft = try? await Task.detached { try book.excelConversion(spaceID) }.value
      if state.workbook === book { conversion = draft }
    }
  }
}

@MainActor
struct ExcelConversionView: View {
  let id: String
  @ObservedObject var state: WorkspaceState
  @State private var conversion: ExcelConversion?
  @State private var failure: String?
  @State private var exampleAction = "recalculate"
  @State private var exampleArguments: [String: String] = [:]
  @State private var availableActions: [ExcelBehavior.Action] = []

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        if let draft = conversion {
          header(draft)
          if state.busy {
            HStack(spacing: 12) {
              ProgressView().controlSize(.small)
              Text(state.status).readingFont(.callout)
              Spacer(minLength: 8)
              Button("Stop", action: state.stop)
            }.accessibilityElement(children: .contain)
          }
          if !state.busy, let error = failure ?? draft.failure {
            Label(error, systemImage: "exclamationmark.circle")
              .foregroundStyle(.secondary).textSelection(.enabled)
          }
          if draft.plan != .null {
            VStack(alignment: .leading, spacing: 10) {
              Text("How this workbook works").readingFont(.headline)
              Text(draft.plan["purpose"].text).textSelection(.enabled)
              ForEach(Array(draft.plan["workflows"].array.enumerated()), id: \.offset) { _, flow in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                  Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                  Text(flow.text)
                }
              }
              if !draft.plan["questions"].array.isEmpty {
                Text("A few things to clarify").readingFont(.headline).padding(.top, 6)
                ForEach(Array(draft.plan["questions"].array.enumerated()), id: \.offset) {
                  _, question in
                  Text(question.text)
                }
              }
              Text("This is an inferred workflow. Correct anything that does not match your work.")
                .readingFont(.caption).foregroundStyle(.secondary)
            }
          }
          if hasCellData(draft) {
            VStack(alignment: .leading, spacing: 8) {
              Text(
                draft.plan == .null
                  ? "What do you use this workbook for?" : "Your workflow and clarifications"
              )
              .readingFont(.headline)
              TextField(
                "For example: track customer orders, calculate totals, and follow up on unpaid invoices",
                text: Binding(
                  get: { state.excelPurposeDrafts[id] ?? draft.purpose },
                  set: { state.excelPurposeDrafts[id] = $0 }), axis: .vertical
              )
              .lineLimit(2...5).textFieldStyle(.roundedBorder)
              .accessibilityLabel("Describe your Excel workflow")
              .disabled(state.busy)
              Text(
                "Optional. Your original file stays available, and you can use the data without AI."
              )
              .readingFont(.caption).foregroundStyle(.secondary)
            }
          }
          actions(draft)
          comparison(draft)
          Divider()
          VStack(alignment: .leading, spacing: 12) {
            Text("Worksheets").readingFont(.headline)
            ForEach(Array(draft.inspection["sheets"].array.enumerated()), id: \.offset) {
              index, sheet in
              HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(sheet["name"].text).lineLimit(2)
                  Text(worksheetSummary(sheet))
                    .readingFont(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let table = draft.record.data["sheetBindings"][String(index)].string {
                  Button("Open table") { state.navigate(.table(table)) }
                    .accessibilityLabel("Open " + sheet["name"].text + " table")
                }
              }.padding(.vertical, 3)
            }
          }
          compatibility(draft)
          if hasCellData(draft) {
            HStack(spacing: 16) {
              Button("View original") { state.navigate(.item(draft.sourceID)) }
              if !state.datasets.filter({ !draft.datasetIDs.contains($0.id) }).isEmpty {
                Button("Update an existing table…") {
                  state.navigate(.tableUpdate(draft.sourceID, nil))
                }
              }
            }.buttonStyle(.link)
          }
        } else if let failure {
          Text(failure).foregroundStyle(.secondary)
          Button("Try again") { Task { await load() } }
        } else {
          ProgressView("Reading the saved import…")
        }
      }.frame(maxWidth: 760, alignment: .leading).padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
    }.task(id: state.revision) { await load() }
  }

  private func header(_ draft: ExcelConversion) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(draft.record.title).readingFont(size: 25, weight: .semibold).textSelection(.enabled)
      Text(
        !hasCellData(draft)
          ? "This workbook has no cell data."
          : draft.state != "ready"
            ? "Bring the way you work into Sevra." : "Your native workspace is ready to review."
      )
      .foregroundStyle(.secondary)
    }
  }
  private func actions(_ draft: ExcelConversion) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        primaryAction(draft)
        secondaryActions(draft)
      }
      VStack(alignment: .leading, spacing: 12) {
        primaryAction(draft)
        secondaryActions(draft)
      }
    }.disabled(state.busy)
  }
  @ViewBuilder private func primaryAction(_ draft: ExcelConversion) -> some View {
    let changed = (state.excelPurposeDrafts[id] ?? draft.purpose) != draft.purpose
    if !hasCellData(draft) {
      Button("View original") { state.navigate(.item(draft.sourceID)) }.buttonStyle(
        .borderedProminent)
    } else if draft.plan == .null || changed {
      Button(draft.plan == .null ? "Understand my workbook" : "Update understanding") {
        state.analyzeExcelImport(id)
      }
      .buttonStyle(.borderedProminent)
    } else if let app = draft.appID, draft.appMatchesPlan {
      Button("Open workspace") { state.navigate(.space(app)) }.buttonStyle(.borderedProminent)
    } else {
      Button(draft.appID == nil ? "Build workspace" : "Rebuild workspace") {
        state.buildExcelImport(id)
      }.buttonStyle(.borderedProminent)
    }
  }
  @ViewBuilder private func secondaryActions(_ draft: ExcelConversion) -> some View {
    if hasCellData(draft) {
      Button(draft.datasetIDs.isEmpty ? "Just use the tables" : "Open imported tables") {
        state.useExcelTables(id)
      }
      if draft.plan != .null {
        Button("Rethink workflow") { state.analyzeExcelImport(id) }.buttonStyle(.link)
      }
      if let app = draft.appID, !draft.appMatchesPlan {
        Button("Open previous workspace") { state.navigate(.space(app)) }.buttonStyle(.link)
      }
    }
  }
  private func compatibility(_ draft: ExcelConversion) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      if !hasCellData(draft) {
        Text("No data rows were found. Your original is saved; there is no table to build from.")
          .foregroundStyle(.secondary)
      }
      let notes = Array(
        Set(draft.inspection["sheets"].array.flatMap { $0["notes"].array.map(\.text) })
      ).sorted()
      if notes.contains(where: { $0 != "Formula cells start from the values Excel saved." })
        || (draft.record.data["formulaReport"]["saved"].int ?? 0) > 0
      {
        Label(
          "Some Excel behavior needs review. Check what carries over before relying on this workspace.",
          systemImage: "info.circle"
        )
        .readingFont(.callout).foregroundStyle(.secondary)
      }
      if draft.record.data["comparison"]["programDigest"] == .null
        || draft.record.data["comparison"]["programDigest"] == .string("builtin"),
        let live = draft.record.data["formulaReport"]["recalculating"].int
      {
        let saved = draft.record.data["formulaReport"]["saved"].int ?? 0
        Text(formulaSummary(live: live, saved: saved))
          .readingFont(.callout)
      }
      DisclosureGroup("What carries over") {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            "The original is preserved. Sevra reads its formulas, layout and available macro source, then recreates the workflow with native controls and local calculations. Comparison covers the saved examples shown here. External services and missing dependencies need explicit treatment."
          )
          ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
            Text(note).textSelection(.enabled)
          }
          Text(draft.inspection["notice"].text)
          if draft.appID != nil {
            Text(
              "The app passed isolated checks for its reported cases. Review its access and try your real workflow before relying on it."
            )
          }
        }.readingFont(.callout).foregroundStyle(.secondary).padding(.top, 8)
      }
    }
  }
  private func comparison(_ draft: ExcelConversion) -> some View {
    let result = draft.record.data["comparison"]
    return VStack(alignment: .leading, spacing: 10) {
      Text("Compare with the original").readingFont(.headline)
      if let compared = result["compared"].int {
        Label(
          compared == 0
            ? "No saved calculation results to compare" : "\(compared) saved results matched",
          systemImage: compared == 0 ? "info.circle" : "checkmark.circle")
        Text(
          "\(result["cases"].array.count) comparison cases · \(result["variedCases"].int ?? 0) examples with changed inputs"
        )
        .readingFont(.caption).foregroundStyle(.secondary)
        if !draft.appMatchesPlan {
          Text("Rebuild to check the updated workflow and examples.").foregroundStyle(.secondary)
        }
        let gaps =
          result["gaps"].array.map(\.text) + result["unverified"].array.map(\.text)
          + result["notCompared"].array.map(\.text)
          + result["actionsWithoutExamples"].array.map {
            $0.text + ": no original action example yet."
          }
        if !gaps.isEmpty {
          DisclosureGroup("Still to verify (\(gaps.count))") {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(Array(gaps.enumerated()), id: \.offset) { _, gap in
                Text(gap).textSelection(.enabled)
              }
            }.padding(.top, 8)
          }
        }
      } else {
        Text("The build checks recreated calculations against results saved in your Excel file.")
          .foregroundStyle(.secondary)
      }
      Text(
        "A saved-result match checks those examples. It does not prove every future input or business rule."
      )
      .readingFont(.caption).foregroundStyle(.secondary)
      DisclosureGroup("Add an original-result example") {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "In Excel, change inputs, recalculate and save a copy. Keep worksheet names, rows and formulas the same. Add that copy here, then rebuild to test its results too."
          )
          .readingFont(.callout).foregroundStyle(.secondary)
          if !availableActions.isEmpty {
            Picker("Example tests", selection: $exampleAction) {
              Text("Changed inputs and calculations").tag("recalculate")
              ForEach(availableActions, id: \.id) { Text($0.title).tag($0.id) }
            }
            if exampleAction != "recalculate" {
              Text(
                "For an action, save the result after running it in Excel from the original starting state. Enter the same action inputs below."
              )
              .readingFont(.caption).foregroundStyle(.secondary)
              ForEach(
                availableActions.first(where: { $0.id == exampleAction })?.inputs ?? [], id: \.id
              ) { input in
                VStack(alignment: .leading, spacing: 6) {
                  Text(input.title).readingFont(.callout)
                  TextField(
                    input.title,
                    text: Binding(
                      get: { exampleArguments[input.id] ?? "" },
                      set: { exampleArguments[input.id] = $0 })
                  ).textFieldStyle(.roundedBorder)
                }
              }
            }
          }
          HStack(spacing: 12) {
            Button("Choose Excel example…") {
              let keys = Set(
                availableActions.first(where: { $0.id == exampleAction })?.inputs?.map(\.id) ?? [])
              state.addExcelExample(
                id, action: exampleAction,
                arguments: .object(
                  exampleArguments.filter { keys.contains($0.key) }.mapValues(Value.string)))
            }
            Text("\(draft.record.data["examples"].array.count) of 12 examples added")
              .readingFont(.caption).foregroundStyle(.secondary)
          }
        }.padding(.top, 10).disabled(state.busy || draft.record.data["examples"].array.count >= 12)
      }
      if !draft.record.data["examples"].array.isEmpty {
        DisclosureGroup("Included examples") {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(draft.record.data["examples"].array.enumerated()), id: \.offset) {
              index, example in
              VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                  Button(example["title"].string ?? "Original-result example") {
                    state.navigate(.item(example["sourceID"].text))
                  }
                  .buttonStyle(.link).lineLimit(2)
                  Spacer(minLength: 8)
                  Button("Remove") {
                    state.removeExcelExample(id, index: index, version: draft.version)
                  }.buttonStyle(.link).accessibilityLabel("Remove example \(index + 1)")
                }
                Text(exampleSummary(example)).readingFont(.caption).foregroundStyle(.secondary)
              }
            }
          }.padding(.top, 8).disabled(state.busy)
        }
      }
    }
  }
  private func exampleSummary(_ example: Value) -> String {
    let actionID = example["action"].string ?? "recalculate"
    guard actionID != "recalculate" else { return "Changed inputs and calculations" }
    let action = availableActions.first { $0.id == actionID }
    let arguments = example["arguments"].object.sorted { $0.key < $1.key }.map { key, value in
      let title = action?.inputs?.first { $0.id == key }?.title ?? key
      return "\(title): \(value.text)"
    }
    return ([action?.title ?? actionID] + arguments).joined(separator: " · ")
  }
  private func count(_ value: Int, _ noun: String) -> String {
    "\(value) " + noun + (value == 1 ? "" : "s")
  }
  private func hasCellData(_ draft: ExcelConversion) -> Bool {
    draft.inspection["sheets"].array.contains { ($0["rows"].int ?? 0) > 0 }
  }
  private func worksheetSummary(_ sheet: Value) -> String {
    var result = count(sheet["rows"].int ?? 0, "row")
    result += " · " + count(sheet["columns"].int ?? 0, "column")
    if let formulas = sheet["formulaCount"].int, formulas > 0 {
      result += " · " + count(formulas, "formula")
    }
    return result
  }
  private func formulaSummary(live: Int, saved: Int) -> String {
    var result = count(live, "formula") + (live == 1 ? " recalculates" : " recalculate")
    result += " after edits."
    if saved > 0 {
      result += " " + count(saved, "formula") + (saved == 1 ? " keeps its" : " keep their")
      result += " saved Excel result."
    }
    return result
  }
  private func load() async {
    guard let book = state.workbook else { return }
    do {
      let value = try await Task.detached { try book.excelConversion(id) }.value
      guard state.workbook === book else { return }
      conversion = value
      availableActions = (try? book.space(id).definition.app?.excelBehavior?.actions) ?? []
      failure = nil
    } catch { failure = error.localizedDescription }
  }
}

extension WorkspaceState {
  func removeExcelExample(_ id: String, index: Int, version: String) {
    run(
      "Updating comparison examples",
      operation: { book, _ in
        try book.removeExcelExample(id, index: index, expectedVersion: version).id
      }, completion: { self.navigate(.excelImport($0)) })
  }
  func addExcelExample(_ id: String, action: String, arguments: Value) {
    guard interactionActive, !busy, let book = workbook, let draft = try? book.excelConversion(id)
    else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [
      UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xlsm"),
    ].compactMap { $0 }
    panel.message =
      "Choose a copy saved after recalculating in Excel. Its saved results become a comparison example."
    guard panel.runModal() == .OK, let url = panel.url, workbook === book, interactionActive else {
      return
    }
    run(
      "Adding original-result example",
      operation: { book, cancel in
        let inputs = action == "recalculate" ? Value.object([:]) : arguments
        let source = try book.captureIntake(
          url, role: .reference, token: identifier(), cancellation: cancel)
        return try book.addExcelExample(
          id, sourceID: source.sourceID, action: action, arguments: inputs,
          expectedVersion: draft.version, cancellation: cancel
        ).id
      }, completion: { self.navigate(.excelImport($0)) })
  }
  var excelModelDirectory: URL {
    UserDefaults.standard.string(forKey: ProductAI.preferenceKey).map { URL(fileURLWithPath: $0) }
      ?? ProductAI.defaultDirectory
  }

  func analyzeExcelImport(_ id: String) {
    guard let (book, ticket) = beginOperation("Understanding your Excel workflow") else { return }
    let purpose = excelPurposeDrafts[id]
    let path = excelModelDirectory
    Task {
      defer { finishOperation(ticket, in: book) }
      var expected: String?
      do {
        let draft = try await Task.detached {
          let old = try book.excelConversion(id)
          return try book.updateExcelConversion(
            id, expectedVersion: old.version, state: "analyzing", purpose: purpose)
        }.value
        expected = draft.version
        await NativeAutomationHost.shared.yieldForInteractive()
        try ticket.cancellation.check()
        let result = try await ProductAI.shared.analyzeExcel(
          draft, workbook: book, modelDirectory: path,
          cancellation: ticket.cancellation,
          progress: { value in
            Task { @MainActor in if self.owns(ticket, in: book) { self.status = value } }
          })
        try ticket.cancellation.check()
        _ = try await Task.detached {
          try book.saveExcelConversionPlan(
            id, expectedVersion: draft.version, plan: result["plan"], model: result["model"].text)
        }.value
      } catch {
        if let expected {
          _ = try? await Task.detached {
            try book.updateExcelConversion(
              id, expectedVersion: expected, state: "needs_attention",
              failure: error.localizedDescription)
          }.value
        }
        report(error, for: ticket, in: book)
      }
    }
  }

  func useExcelTables(_ id: String) {
    let navigation = itemPreviewIdentity
    let progress = rowProgress()
    run(
      "Importing Excel data",
      operation: { book, cancel in
        try book.importExcelConversionTables(id, cancellation: cancel, progress: progress)
          .datasetIDs
      },
      completion: { ids in
        if self.itemPreviewIdentity == navigation, let first = ids.first {
          self.navigate(.table(first))
        }
      })
  }

  func buildExcelImport(_ id: String) {
    guard let (book, ticket) = beginOperation("Preparing your native workspace") else { return }
    let path = excelModelDirectory
    let chat = conversation
    let progress = rowProgress()
    Task {
      defer { finishOperation(ticket, in: book) }
      var expected: String?
      do {
        let build = try await Task.detached {
          let imported = try book.importExcelConversionTables(
            id, cancellation: ticket.cancellation, progress: progress)
          _ = try book.updateExcelConversion(
            id, expectedVersion: imported.version, state: "building")
          return try book.prepareExcelConversionBuild(id)
        }.value
        expected = build.conversionVersion
        await NativeAutomationHost.shared.yieldForInteractive()
        try ticket.cancellation.check()
        let result = try await ProductAI.shared.run(
          build.request, workbook: book, conversation: chat,
          context: build.context, modelDirectory: path, cancellation: ticket.cancellation,
          progress: { update in
            Task { @MainActor in
              if self.owns(ticket, in: book) {
                self.status = update
                self.refresh()
              }
            }
          }, excelConversion: build)
        let completed = try await Task.detached { try book.excelConversion(id) }.value
        try require(
          completed.state == "ready" && completed.appID != nil, "excel_build", result.answer)
      } catch {
        if let expected {
          _ = try? await Task.detached {
            try book.updateExcelConversion(
              id, expectedVersion: expected, state: "needs_attention",
              failure: error.localizedDescription)
          }.value
        }
        report(error, for: ticket, in: book)
      }
    }
  }
}
