import Foundation
import SevraAI
import SevraAppProtocol
import ZIPFoundation

@testable import SevraCore

func checkExcelBehaviorReconstruction() async throws {
  let fixtureRoot = URL(fileURLWithPath: "integration/fixtures/excel-behavior", isDirectory: true)
  let cases = try Value.parse(
    String(contentsOf: fixtureRoot.appendingPathComponent("cases.json"), encoding: .utf8)
  ).array
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-behavior-check-" + identifier())
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: root) }
  for example in cases {
    let name = example["name"].text
    let behavior = try JSONDecoder().decode(
      ExcelBehavior.self, from: Data(example["behavior"].json().utf8))
    let files = example["files"].array.map { fixtureRoot.appendingPathComponent($0.text) }
    let book = try Workbook.create(at: root.appendingPathComponent(name + ".sevra"), title: name)
    let source = try book.importFile(files[0])
    var draft = try book.beginExcelConversion(sourceID: source.id)
    draft = try book.updateExcelConversion(
      draft.id, expectedVersion: draft.version, state: "review",
      plan: .object([
        "name": .string(name), "purpose": .string("Recreate " + name),
        "workflows": .array([.string("Edit inputs and recalculate")]), "questions": .array([]),
      ]))
    draft = try book.importExcelConversionTables(draft.id)
    let initialBuild = try book.prepareExcelConversionBuild(draft.id)
    if name == "Loan" {
      let evidence = try Value.parse(initialBuild.context)["calculationEvidence"]
      try expectEqual(evidence["inputCells"]["sheet1!B2"], .string("10000"))
      try expectEqual(evidence["inputCells"]["sheet1!D2"], .null)
      try expectEqual(evidence["formulas"]["sheet1!D2"].text.contains("PMT"), true)
    }
    for file in files.dropFirst() {
      let reference = try book.importFile(file)
      draft = try book.addExcelExample(
        draft.id, sourceID: reference.id, expectedVersion: draft.version)
    }
    if name == "Inventory" {
      let reference = try book.importFile(files[1])
      draft = try book.addExcelExample(
        draft.id, sourceID: reference.id, action: "ship",
        arguments: .object(["quantity": .string("2")]), expectedVersion: draft.version)
      let evidence = try book.readExcelEvidence(draft.id)
      let module = try expectValue(
        evidence.array.first { $0["kind"] == .string("vba") }?["id"].string)
      try expectEqual(
        try book.readExcelEvidence(draft.id, part: module)["text"].text.contains("Sub ShipStock()"),
        true)
      try expectThrows(try book.readExcelEvidence(draft.id, part: "../../secret"))
      try expectThrows(try book.readExcelEvidence(draft.id, part: module, offset: -1))
    }
    try expectThrows(try book.validateExcelConversionBuild(initialBuild))
    let report = try book.compareExcelBehavior(behavior, conversionID: draft.id)
    if report["status"] != .string("matched") {
      print(
        "Reference behavior mismatch for " + name + ": " + Workbook.excelComparisonFailure(report))
    }
    try expectEqual(report["status"], .string("matched"))
    try expectEqual(
      report["variedCases"], example["variedCases"])
    try expectEqual(report["actionsWithoutExamples"], .array([]))
    // A constant can match the starting file; varied independent examples must catch it.
    let original = try book.excelOriginalSheets(source.id)
    let baseline = try Workbook.excelCells(original)
    var constant = behavior
    constant.actions = []
    constant.source =
      "function recreate(){return {'sheet1!D2':" + (try Value.string(baseline["sheet1!D2"]!).json())
      + "};}"
    if name != "Inventory" {
      try expectEqual(
        try book.compareExcelBehavior(constant, conversionID: draft.id)["status"],
        .string("mismatch"))
    }
    if name == "Loan" {
      var nonzeroOnly = behavior
      nonzeroOnly.source =
        "function recreate(input){const c=input.cells,b=Number(c['sheet1!B2']),r=Number(c['sheet1!C2']),n=Number(c['sheet1!E2']);return {'sheet1!D2':String(Math.round(b*r/(1-Math.pow(1+r,-n))*100)/100)}}"
      let failed = try book.compareExcelBehavior(nonzeroOnly, conversionID: draft.id)
      try expectEqual(failed["status"], .string("mismatch"))
      try expectEqual(
        failed["failingScenarios"].array[0]["inputChanges"]["sheet1!C2"], .string("0"))
      try expectEqual(failed["failingScenarios"].array[0]["inputChanges"]["sheet1!D2"], .null)
      try expectEqual(Workbook.excelComparisonFailure(failed).contains("sheet1!C2"), true)
    }
    let build = try book.prepareExcelConversionBuild(draft.id)
    var package = NativeAppPackage(
      name: name,
      source:
        "const S=Sevra;S.mount(S.h(S.Column,{gap:16},S.h(S.Text,{text:'Recreated workflow'}),S.h(S.Table,{table:'sheet1',label:'Records',height:300})));",
      datasets: [
        "sheet1": .init(
          title: name, columns: build.tables[0].columns, writable: true,
          datasetID: build.tables[0].id)
      ])
    package.excelBehavior = behavior
    if name == "Loan" {
      var inputOverwrite = behavior
      inputOverwrite.outputs.append("sheet1!B2")
      try expectThrows(try book.compareExcelBehavior(inputOverwrite, conversionID: draft.id))
      var wrong = package
      wrong.excelBehavior = constant
      let revision = try book.revision()
      try expectThrows(
        try book.installExcelConversionApp(
          wrong, build: build, check: .object([:]),
          token: identifier(), cancellation: .init()))
      try expectEqual(try book.revision(), revision)
      try expectEqual(try book.spaces().filter { $0.definition.app != nil }.count, 0)
    }
    let fixtures: Value = .object([
      "sheet1": .array(try book.tablePage(build.tables[0].id).values.map(Value.object))
    ])
    var minimal = try encoded(package).object
    minimal["datasets"] = .object(["sheet1": .object(["writable": .bool(true)])])
    var steps: [Value] = [
      .object(["kind": .string("expect_control"), "target": .string("Records")])
    ]
    if name == "Inventory" {
      package.source = """
        const S=Sevra,q=S.signal(''),status=S.signal(''),busy=S.signal(false);let receipt=null;
        async function ship(){busy.value=true;try{receipt=await S.data.transaction([{op:'excel_action',action:'ship',arguments:{quantity:q.value}}]);status.value='Shipped';}catch(e){status.value=e.message;}finally{busy.value=false;}}
        async function undo(){if(!receipt)return;busy.value=true;try{await S.data.undo(receipt);receipt=null;status.value='Undone';}catch(e){status.value=e.message;}finally{busy.value=false;}}
        S.mount(S.h(S.Column,{gap:16},S.h(S.Text,{text:'Stock'}),S.h(S.Table,{table:'sheet1',label:'Records',height:300}),S.h(S.TextField,{label:'Quantity',value:q}),S.h(S.Button,{title:'Ship stock',onClick:ship,enabled:()=>!busy.value}),S.h(S.Button,{title:'Undo shipment',onClick:undo,enabled:()=>!busy.value}),S.h(S.Text,{text:status})));
        """
      minimal["source"] = .string(package.source)
      steps += [
        .object(["kind": .string("change"), "target": .string("Quantity"), "value": .string("2")]),
        .object(["kind": .string("click"), "target": .string("Ship stock")]),
        .object([
          "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
          "values": .object(["c2": .string("6"), "c4": .string("6")]),
        ]),
        .object(["kind": .string("click"), "target": .string("Undo shipment")]),
        .object([
          "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
          "values": .object(["c2": .string("8"), "c4": .string("4")]),
        ]),
        .object(["kind": .string("change"), "target": .string("Quantity"), "value": .string("999")]
        ),
        .object(["kind": .string("click"), "target": .string("Ship stock")]),
        .object(["kind": .string("expect_text"), "value": .string("available quantity")]),
        .object([
          "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
          "values": .object(["c2": .string("8"), "c4": .string("4")]),
        ]),
      ]
    }
    if name == "Inventory" {
      var namedLikeMacro = behavior
      namedLikeMacro.actions[0].id = "ShipStock"
      namedLikeMacro.actions[0].inputs?[0].id = "Quantity"
      namedLikeMacro.source = behavior.source.replacingOccurrences(
        of: "input.event===\"ship\"", with: "input.event===\"ShipStock\""
      )
      .replacingOccurrences(of: "input.arguments.quantity", with: "input.arguments.Quantity")
      let namedResult = try namedLikeMacro.evaluate(
        cells: Workbook.excelCells(book.excelOriginalSheets(source.id)), action: "ShipStock",
        arguments: .object(["Quantity": .string("2")]))
      try expectEqual(namedResult["sheet1!B2"], "6")
      for invalidID in [
        "../ship", "Ship Stock", "ShipStock\n", "recalculate", String(repeating: "a", count: 65),
      ] {
        var invalid = namedLikeMacro
        invalid.actions[0].id = invalidID
        try expectThrows(try invalid.validate())
      }
      var broken = package
      broken.source = """
        const S=Sevra,status=S.signal('');S.mount(S.h(S.Column,{},S.h(S.Button,{title:'Ship',onClick:async()=>{try{await S.data.transaction([{op:'excel_action',action:'ship',arguments:{quantity:'2'}}]);}catch(e){status.value='Handled failure';}}}),S.h(S.Text,{text:status})));
        """
      for returned in [
        "return {\"sheet1!B2\":String(b-q),\"sheet1!D2\":\"0\"}", "return 'invalid'",
      ] {
        broken.excelBehavior?.source = behavior.source.replacingOccurrences(
          of: "return {\"sheet1!B2\":String(b-q)}", with: returned)
        try expectEqual(broken.excelBehavior?.source != behavior.source, true)
        do {
          _ = try await NativeAppCheck.run(
            package: broken,
            steps: [
              .object(["kind": .string("click"), "target": .string("Ship")]),
              .object(["kind": .string("expect_text"), "value": .string("Handled failure")]),
            ], fixtures: fixtures, excelCoordinates: book.excelCheckCoordinates(draft.id))
          throw SevraError("test", "A caught malformed action result passed preflight")
        } catch {
          try expectEqual((error as? SevraError)?.code, "excel_behavior_result")
        }
      }
    }
    // A successfully compared behavior is retained by this request. UI authoring need not
    // retransmit it, but a subsequent bad comparison must invalidate that exact draft.
    minimal.removeValue(forKey: "excelBehavior")
    let args: Value = .object([
      "package": .object(minimal), "fixtures": fixtures, "tests": .array(steps),
    ])
    if name == "Loan" {
      let bad = ExcelBehavior(
        source: "function recreate(){return {'sheet1!D2':'wrong'}}", outputs: ["sheet1!D2"])
      var badPackage = minimal
      badPackage["excelBehavior"] = try encoded(bad)
      var badSave = args.object
      badSave["package"] = .object(badPackage)
      var malformedAction = behavior
      malformedAction.actions = [.init(id: "bad", title: "Bad action", writes: ["sheet1!B2"])]
      malformedAction.source = behavior.source.replacingOccurrences(
        of: "function recreate(input){",
        with: "function recreate(input){if(input.event==='bad')return {'sheet1!D2':'0'};")
      try expectEqual(
        try book.compareExcelBehavior(malformedAction, conversionID: draft.id)["status"],
        .string("matched"))
      var actionPackage = minimal
      actionPackage["excelBehavior"] = try encoded(malformedAction)
      actionPackage["source"] = .string(
        "const S=Sevra,status=S.signal('');S.mount(S.h(S.Column,{},S.h(S.Table,{table:'sheet1',label:'Records'}),S.h(S.Button,{title:'Bad',onClick:async()=>{try{await S.data.transaction([{op:'excel_action',action:'bad',arguments:{}}]);}catch(e){status.value='Handled failure';}}}),S.h(S.Text,{text:status})));"
      )
      let actionSave: Value = .object([
        "package": .object(actionPackage), "fixtures": fixtures,
        "tests": .array([
          .object(["kind": .string("click"), "target": .string("Bad")]),
          .object(["kind": .string("expect_text"), "value": .string("Handled failure")]),
        ]),
      ])
      for invalidation: (String, Value) in [
        ("compare_excel_behavior", .object(["behavior": try encoded(bad)])),
        ("save_native_app", .object(badSave)),
        ("save_native_app", actionSave),
      ] {
        let failureModel = ExcelTestModel([
          ("compare_excel_behavior", .object(["behavior": try encoded(behavior)])),
          invalidation,
          ("save_native_app", args), ("save_native_app", args), ("save_native_app", args),
        ])
        var refused = false
        do {
          _ = try await WorkbookAgent.run(
            build.request, workbook: book, context: build.context,
            model: failureModel, excelConversion: build)
        } catch { refused = true }
        try expectEqual(refused, true)
        try expectEqual(try book.excelConversion(draft.id).appID, nil)
      }
    }
    var buildActions: [(String, Value)] = [
      ("compare_excel_behavior", .object(["behavior": try encoded(behavior)])),
      ("save_native_app", args),
    ]
    if name == "Reference codes" {
      var firstPackage = minimal
      firstPackage["excelBehavior"] = try encoded(behavior)
      let failedUI: Value = .object([
        "package": .object(firstPackage), "fixtures": fixtures,
        "tests": .array([.object(["kind": .string("expect_text"), "value": .string("Missing")])]),
      ])
      // A save that passes original comparison but fails its UI checks retains only the
      // exact verified calculation draft. The next UI repair need not regenerate it.
      buildActions = [("save_native_app", failedUI), ("save_native_app", args)]
    }
    let builder = ExcelTestModel(buildActions)
    _ = try await WorkbookAgent.run(
      build.request, workbook: book, context: build.context,
      model: builder, excelConversion: build)
    let reviewInput = try expectValue(await builder.reviewInputs.last)
    try expectEqual(reviewInput["proposedPackage"]["excelBehavior"], .null)
    try expectEqual(
      reviewInput["hostValidatedActionProgram"],
      behavior.actions.isEmpty ? .null : .string(behavior.source))
    let ready = try book.excelConversion(draft.id)
    if ready.state != "ready" { print(try encoded(book.messages()).json()) }
    try expectEqual(ready.state, "ready")
    try expectEqual(ready.record.data["comparison"]["status"], .string("matched"))
    try expectEqual(try book.space(draft.id).definition.app?.excelBehavior, behavior)
    var stripped = package
    stripped.excelBehavior = nil
    try expectThrows(
      try book.installNativeApp(
        stripped, spaceID: draft.id, expectedVersion: book.space(draft.id).version))
    let access = try NativeAppAccess(workbook: book, space: book.space(draft.id))
    let table = build.tables[0].id
    for file in files.dropFirst() {
      let expectedSheets = try ExtractionWorker().readTable(file, format: .xlsx).sheets
      let expected = try Workbook.excelCells(expectedSheets)
      let row = try book.tablePage(table).rows[1]
      let token = identifier()
      let prior = try book.tablePage(table).values[1]
      var inputValues: [String: Value] = [
        "c2": .string(expected["sheet1!B2"]!), "c3": .string(expected["sheet1!C2"]!),
      ]
      if name == "Loan" { inputValues["c5"] = .string(expected["sheet1!E2"]!) }
      if name == "Lookup quotes" {
        inputValues["c6"] = .string(expected["sheet1!F2"]!)
        inputValues["c7"] = .string(expected["sheet1!G2"]!)
      }
      _ = try book.nativeAppTransaction(
        access,
        operations: [
          .object([
            "op": .string("update"),
            "table": .string("sheet1"), "id": .string(row.id),
            "values": .object(inputValues),
          ])
        ], expectedRevision: book.revision(), token: token)
      try expectEqual(
        Workbook.sameExcelResult(
          try book.tablePage(table).values[1]["c4"]!.text, expected["sheet1!D2"]!), true)
      _ = try book.nativeAppTransaction(
        access, operations: [], expectedRevision: book.revision(), token: identifier(), undo: token)
      try expectEqual(try book.tablePage(table).values[1], prior)
    }
    if name == "Inventory" {
      let token = identifier()
      let before = try book.tablePage(table).values
      _ = try book.nativeAppTransaction(
        access,
        operations: [
          .object([
            "op": .string("excel_action"),
            "action": .string("ship"), "arguments": .object(["quantity": .string("2")]),
          ])
        ], expectedRevision: book.revision(), token: token)
      try expectEqual(try book.tablePage(table).values[1]["c2"], .string("6"))
      try expectEqual(try book.tablePage(table).values[1]["c4"], .string("6"))
      let undoToken = identifier()
      _ = try book.nativeAppTransaction(
        access, operations: [], expectedRevision: book.revision(), token: undoToken, undo: token)
      try expectEqual(try book.tablePage(table).values, before)
      _ = try book.nativeAppTransaction(
        access, operations: [], expectedRevision: book.revision(), token: identifier(),
        undo: undoToken)
      try expectEqual(try book.tablePage(table).values[1]["c2"], .string("6"))
      let revision = try book.revision()
      for quantity in ["-1", "999", "oops"] {
        try expectThrows(
          try book.nativeAppTransaction(
            access,
            operations: [
              .object([
                "op": .string("excel_action"),
                "action": .string("ship"), "arguments": .object(["quantity": .string(quantity)]),
              ])
            ], expectedRevision: revision, token: identifier()))
        try expectEqual(try book.revision(), revision)
      }
    }
    let row = try book.tablePage(table).rows[1]
    try expectThrows(try book.editRow(row.id, values: ["c4": .string("forged")]))
    access.revoke()
    try expectThrows(
      try book.nativeAppTransaction(
        access,
        operations: [
          .object([
            "op": .string("excel_action"),
            "action": .string("ship"), "arguments": .object([:]),
          ])
        ], expectedRevision: book.revision(), token: identifier()))
    let archive = root.appendingPathComponent(name + ".sevraz")
    try book.export(to: archive)
    let copy = try Workbook.openArchive(
      archive, at: root.appendingPathComponent(name + " copy.sevra"))
    let current = try copy.tablePage(table).rows[1]
    _ = try copy.editRow(current.id, values: ["c2": .string(baseline["sheet1!B2"]!)])
    try expectEqual(
      Workbook.sameExcelResult(
        try copy.tablePage(table).values[1]["c4"]!.text, baseline["sheet1!D2"]!), true)
    try expectEqual(try copy.verify()["ok"], .bool(true))
    try expectEqual(try book.verify()["ok"], .bool(true))
    print(
      "PASS recreated \(name): independent original examples, calculated edits/Undo, protected outputs, revoke, portable reopen"
    )
  }

  let cells = ["sheet1!B2": "3", "sheet1!C2": "4", "sheet1!D2": "12"]
  let probe = root.appendingPathComponent("sandbox-sentinel.txt")
  try Data("synthetic sentinel".utf8).write(to: probe)
  let sandbox = try ExtractionWorker().excelBehavior(
    .object([
      "source": .string("function recreate(){return {}}"), "input": .object([:]),
      "sandboxProbe": .string(probe.path),
    ]))
  try expectEqual(sandbox["deniedRead"], .bool(true))
  try expectEqual(sandbox["deniedWrite"], .bool(true))
  try expectEqual(FileManager.default.fileExists(atPath: probe.path + ".probe"), false)
  do {
    _ = try ExcelBehavior(
      source: "function recreate(input){return {'sheet1!D2':'1'};", outputs: ["sheet1!D2"]
    ).evaluate(cells: ["sheet1!D2": "1"])
    throw SevraError("test", "Incomplete calculation function accepted")
  } catch {
    try require(
      error.localizedDescription.contains("Invalid excelBehavior.source"), "test",
      "Expected calculation syntax feedback; received: " + error.localizedDescription)
    try expectEqual(error.localizedDescription.contains("closing brace"), true)
  }
  let programs = [
    "function recreate(input){return {'sheet1!D2':String(Number(input.cells['c2'])||0)}}",
    "function recreate(input){return {'sheet1!D2':String(Number(input.c2)||0)}}",
    "function recreate(input){return {'sheet1!D2':String(input['sheet1!B2'])}}",
    "function recreate(){while(true){}}",
    "function recreate(){return {'sheet1!A1':'overreach'}}",
    "function recreate(){return {'sheet1!D2':12}}",
    "function recreate(input){return {'sheet1!D2':input.cells['sheet1!D2']}}",
    "function recreate(){return {'sheet1!D2':String(Math.random())}}",
    "function recreate(){return {'sheet1!D2':String(Date.now())}}",
    "function recreate(){return fetch('https://example.com')}",
    "function recreate(){const a=[];for(;;)a.push('x'.repeat(100000));}",
    "function recreate(){return {get 'sheet1!D2'(){while(true){}}}}",
  ]
  for source in programs {
    let program = ExcelBehavior(source: source, outputs: ["sheet1!D2"])
    try expectThrows(try program.evaluate(cells: cells))
  }
  var validationMessage = ""
  do {
    _ = try ExcelBehavior(
      source: "function recreate(){throw new Error('Enter an available quantity');}",
      outputs: ["sheet1!D2"]
    ).evaluate(cells: cells)
  } catch { validationMessage = error.localizedDescription }
  try expectEqual(validationMessage, "Enter an available quantity")
  let blank = ExcelBehavior(
    source:
      "function recreate(input){return {'sheet1!D2':String(Number(input.cells['sheet1!Z99']))}}",
    outputs: ["sheet1!D2"])
  try expectEqual(try blank.evaluate(cells: cells)["sheet1!D2"], "0")
  var invalid = ExcelBehavior(source: "function recreate(){return {}}", outputs: ["sheet1!D2"])
  invalid.actions = [.init(id: "write", title: "Write", writes: ["sheet1!D2"])]
  try expectThrows(try invalid.validate())
  try expectEqual(Workbook.sameExcelResult("00123", "123"), false)
  try expectEqual(Workbook.sameExcelResult("0.30000000000000004", "0.3"), true)
  let macro = try Data(contentsOf: fixtureRoot.appendingPathComponent("vbaProject.bin"))
  let modules = try VBASource.modules(macro, cancellation: .init())
  try expectEqual(modules.contains { $0.1.contains("Sub say_hello()") }, true)
  for bytes in [Data(), Data([1, 0, 0]), Data([1, 2, 0xB0, 1, 0, 0])] {
    try expectThrows(try VBASource.decompress(bytes))
  }
  var cyclic = macro
  // Directory first sector is replaced by itself in the FAT, producing a refused cycle.
  let firstFAT = Int(try VBASource.u32(Array(macro), 76))
  let firstDirectory = Int(try VBASource.u32(Array(macro), 48))
  let location = (firstFAT + 1) * 512 + firstDirectory * 4
  cyclic.replaceSubrange(
    location..<(location + 4),
    with: withUnsafeBytes(of: UInt32(firstDirectory).littleEndian, Array.init))
  try expectThrows(try VBASource.modules(cyclic, cancellation: .init()))
  try checkExcelEvidenceBoundaries(root)
  print(
    "PASS hostile behavior: CPU/memory/serialization limits, no clocks/random/network, hidden expected outputs, exact writes, VBA decoding and cyclic-container refusal"
  )
  try checkExcelActionAtomicity(root)
  try await checkExcelSparseFixtures()
  let examplesBook = try Workbook.create(
    at: root.appendingPathComponent("Examples.sevra"), title: "Example corrections")
  let original = try examplesBook.importFile(fixtureRoot.appendingPathComponent("loan-0.xlsx"))
  let reference = try examplesBook.importFile(fixtureRoot.appendingPathComponent("loan-1.xlsx"))
  var exampleDraft = try examplesBook.beginExcelConversion(sourceID: original.id)
  exampleDraft = try examplesBook.addExcelExample(
    exampleDraft.id, sourceID: reference.id, expectedVersion: exampleDraft.version)
  let duplicate = try examplesBook.importFile(fixtureRoot.appendingPathComponent("loan-1.xlsx"))
  try expectThrows(
    try examplesBook.addExcelExample(
      exampleDraft.id, sourceID: duplicate.id, expectedVersion: exampleDraft.version))
  let previous = exampleDraft.version
  exampleDraft = try examplesBook.removeExcelExample(
    exampleDraft.id, index: 0, expectedVersion: previous)
  try expectEqual(exampleDraft.record.data["examples"], .array([]))
  try expectThrows(
    try examplesBook.removeExcelExample(exampleDraft.id, index: 0, expectedVersion: previous))
  try expectEqual(try examplesBook.item(reference.id).id, reference.id)
  exampleDraft = try examplesBook.updateExcelConversion(
    exampleDraft.id, expectedVersion: exampleDraft.version,
    state: "review",
    plan: .object([
      "name": .string("Loan"), "purpose": .string("Compare"),
      "workflows": .array([.string("Edit")]), "questions": .array([]),
    ]))
  exampleDraft = try examplesBook.importExcelConversionTables(exampleDraft.id)
  let binding = try examplesBook.prepareExcelConversionBuild(exampleDraft.id)
  let table = exampleDraft.datasetIDs[0]
  // Replacing an ordinal with a different logical row cannot inherit that Excel address.
  let oldRows = try examplesBook.tablePage(table)
  let editor = try examplesBook.installNativeApp(
    NativeAppPackage(
      name: "Row editor", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Editor'}));",
      datasets: [
        "rows": .init(
          title: "Rows", columns: oldRows.dataset.columns, writable: true, datasetID: table)
      ]))
  let editorAccess = try NativeAppAccess(workbook: examplesBook, space: editor)
  _ = try examplesBook.nativeAppTransaction(
    editorAccess,
    operations: [
      .object([
        "op": .string("delete"), "table": .string("rows"), "id": .string(oldRows.rows[0].id),
      ]),
      .object([
        "op": .string("insert"), "table": .string("rows"), "values": .object(oldRows.values[0]),
      ]),
    ], expectedRevision: examplesBook.revision(), token: identifier())
  editorAccess.revoke()
  try expectEqual(try examplesBook.tablePage(table).total, oldRows.total)
  try expectThrows(try examplesBook.validateExcelConversionBuild(binding))
  try expectThrows(try examplesBook.prepareExcelConversionBuild(exampleDraft.id))
  print(
    "PASS example corrections: content duplicate refusal, captured removal, stale refusal, original retention and changed-row rebuild refusal"
  )
}

private func checkExcelEvidenceBoundaries(_ root: URL) throws {
  let duplicate = ImportedSheet(
    name: "Duplicate", rows: [["a"], ["b"]], rowNumbers: [1, 1], notes: [], formulas: [:])
  try expectThrows(try StructuredResult(sheets: [duplicate]).validate())
  let valid = ImportedSheet(
    name: "Sparse", rows: [["a"], ["b"]], rowNumbers: [1, 3], notes: [], formulas: [:])
  try StructuredResult(sheets: [valid]).validate()
  let file = root.appendingPathComponent("embedded.xlsx")
  let archive = try Archive(url: file, accessMode: .create)
  let data = Data([1, 2, 3])
  try archive.addEntry(
    with: "xl/embeddings/oleObject1.bin", type: .file, uncompressedSize: Int64(data.count)
  ) { offset, size in data.subdata(in: Int(offset)..<(Int(offset) + size)) }
  let evidence = try ExcelEvidence.readInProcess(file, cancellation: .init())
  try expectEqual(evidence.count, 1)
  try expectEqual(evidence[0].kind, "unreadable_binary")
  try expectEqual(evidence[0].complete, false)
  let dtd = Data("<!DOCTYPE x><x/>".utf8)
  try archive.addEntry(with: "xl/connections.xml", type: .file, uncompressedSize: Int64(dtd.count))
  { offset, size in dtd.subdata(in: Int(offset)..<(Int(offset) + size)) }
  try expectThrows(try ExcelEvidence.readInProcess(file, cancellation: .init()))
  print(
    "PASS original evidence boundaries: duplicate coordinates refused, sparse coordinates retained, embedded binary gap explicit, XML DTD refused"
  )
}

private func checkExcelSparseFixtures() async throws {
  var package = NativeAppPackage(
    name: "Long worksheet",
    source: "Sevra.mount(Sevra.h(Sevra.Table,{table:'sheet1',label:'Records'}));",
    datasets: [
      "sheet1": .init(
        title: "Worksheet",
        columns: [.init(id: "c1", title: "Input"), .init(id: "c2", title: "Output")])
    ])
  package.excelBehavior = .init(
    source:
      "function recreate(input){const out={};for(let r=1;r<=100;r++)out['sheet1!B'+r]=String(Number(input.cells['sheet1!A'+r])*2);return out;}",
    outputs: (1...100).map { "sheet1!B\($0)" })
  let checked = try await NativeAppCheck.run(
    package: package,
    steps: [
      .object(["kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(100)]),
      .object([
        "kind": .string("expect_rows"), "table": .string("sheet1"), "count": .number(1),
        "values": .object(["c2": .string("6")]),
      ]),
    ], fixtures: .object(["sheet1": .array([.object(["c1": .string("3"), "c2": .string("0")])])]),
    excelCoordinates: [Array(1...100)])
  try expectEqual(checked["paddedSyntheticRows"], .number(99))
  print(
    "PASS long worksheet checks: 100 original positions, 99 blank invented rows, no original values copied"
  )
}

private func checkExcelActionAtomicity(_ root: URL) throws {
  let book = try Workbook.create(
    at: root.appendingPathComponent("Atomic.sevra"), title: "Atomic action check")
  let columns: [Column] = [.init(id: "c1", title: "Input"), .init(id: "c2", title: "Output")]
  var package = NativeAppPackage(
    name: "Cross-sheet action", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Atomic check'}));",
    datasets: [
      "sheet1": .init(title: "First", columns: columns, writable: true),
      "sheet2": .init(title: "Second", columns: columns, writable: true),
    ])
  package.excelBehavior = .init(
    source: """
      function recreate(input){const c=input.cells,a=Number(c['sheet1!A1']),b=Number(c['sheet2!A1']);
      if(a!==b)throw Error('Both inputs must move together');
      if(input.event==='advance')return {'sheet1!A1':String(a+1),'sheet2!A1':String(b+1)};
      return {'sheet1!B1':String(a*2),'sheet2!B1':String(b*3)};}
      """, outputs: ["sheet1!B1", "sheet2!B1"],
    actions: [.init(id: "advance", title: "Advance", writes: ["sheet1!A1", "sheet2!A1"])])
  try expectThrows(try book.installNativeApp(package))
  let space = try book.installNativeAppContents(package)
  let access = try NativeAppAccess(workbook: book, space: space)
  _ = try book.nativeAppTransaction(
    access,
    operations: ["sheet1", "sheet2"].map {
      .object([
        "op": .string("insert"), "table": .string($0),
        "values": .object(["c1": .string("2"), "c2": .string("0")]),
      ])
    }, expectedRevision: book.revision(), token: identifier())
  try book.attachSyntheticExcelBehavior(space.definition.app!, coordinates: nil)
  let action: [Value] = [.object(["op": .string("excel_action"), "action": .string("advance")])]
  let token = identifier()
  _ = try book.nativeAppTransaction(
    access, operations: action, expectedRevision: book.revision(), token: token)
  let first = space.definition.app!.datasets["sheet1"]!.datasetID!
  let second = space.definition.app!.datasets["sheet2"]!.datasetID!
  try expectEqual(try book.tablePage(first).values[0]["c2"], .string("6"))
  try expectEqual(try book.tablePage(second).values[0]["c2"], .string("9"))
  _ = try book.nativeAppTransaction(
    access, operations: [], expectedRevision: book.revision(), token: identifier(), undo: token)
  try expectEqual(try book.tablePage(first).values[0]["c2"], .string("4"))
  try expectEqual(try book.tablePage(second).values[0]["c2"], .string("6"))
  let batchToken = identifier()
  let batch = try [first, second].enumerated().map { index, table in
    Value.object([
      "op": .string("update"), "table": .string("sheet\(index + 1)"),
      "id": .string(try book.tablePage(table).rows[0].id),
      "values": .object(["c1": .string("5")]),
    ])
  }
  _ = try book.nativeAppTransaction(
    access, operations: batch, expectedRevision: book.revision(), token: batchToken)
  try expectEqual(try book.tablePage(first).values[0]["c2"], .string("10"))
  try expectEqual(try book.tablePage(second).values[0]["c2"], .string("15"))
  _ = try book.nativeAppTransaction(
    access, operations: [], expectedRevision: book.revision(), token: identifier(), undo: batchToken
  )
  try expectEqual(try book.tablePage(first).values[0]["c2"], .string("4"))
  try expectEqual(try book.tablePage(second).values[0]["c2"], .string("6"))
  let revision = try book.revision()
  let invalidBatch: [Value] = [
    .object([
      "op": .string("update"), "table": .string("sheet1"),
      "id": .string(try book.tablePage(first).rows[0].id),
      "values": .object(["c1": .string("5")]),
    ])
  ]
  try expectThrows(
    try book.nativeAppTransaction(
      access, operations: invalidBatch, expectedRevision: revision, token: identifier()))
  try expectEqual(try book.revision(), revision)
  try expectEqual(try book.tablePage(first).values[0]["c1"], .string("2"))
  try expectEqual(try book.tablePage(second).values[0]["c2"], .string("6"))
  try expectThrows(
    try book.nativeAppTransaction(
      access, operations: action, expectedRevision: revision - 1, token: identifier()))
  try expectThrows(
    try book.nativeAppTransaction(
      access,
      operations: [
        .object([
          "op": .string("insert"), "table": .string("sheet1"),
          "values": .object(["c1": .string("2")]),
        ])
      ], expectedRevision: revision, token: identifier()))
  try expectEqual(try book.revision(), revision)
  var readonly = space.definition.app!
  readonly.datasets["sheet2"]!.writable = false
  let update = try book.installNativeAppContents(
    readonly, spaceID: space.id, expectedVersion: space.version)
  let limited = try NativeAppAccess(workbook: book, space: update)
  let base = try book.revision()
  try expectThrows(
    try book.nativeAppTransaction(
      limited, operations: action, expectedRevision: base, token: identifier()))
  try expectEqual(try book.revision(), base)
  try expectEqual(try book.verify()["ok"], .bool(true))
  print(
    "PASS cross-sheet action: no intermediate calculation, atomic Undo, stale/schema/read-only refusal and rollback"
  )
}
