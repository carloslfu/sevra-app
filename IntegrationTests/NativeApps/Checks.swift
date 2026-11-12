import AppKit
import Foundation
import SevraAppProtocol
import SevraAppRuntime
import SevraAppUI
import SevraCore

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String = "Expectation failed")
  throws
{
  if try !condition() { throw SevraError("test", message) }
}
func refuses(_ body: () throws -> Void) throws {
  do { try body() } catch { return }
  throw SevraError("test", "Expected refusal")
}
func exchange(
  _ runtime: NativeAppRuntime, source: String? = nil, messages: [Value] = [], sequence: Int = 0
) throws -> Value {
  var input: [String: Value] = [
    "kind": .string(source == nil ? "events" : "start"), "session": .string("test"),
    "sequence": .number(Double(sequence)),
  ]
  if let source {
    input["source"] = .string(source)
    input["state"] = .object([:])
  } else {
    input["messages"] = .array(messages)
  }
  return try NativeAppWire.decode(runtime.exchange(NativeAppWire.encode(.object(input))))
}
@main struct Checks {
  @MainActor static func main() async {
    setbuf(stdout, nil)
    var passed = 0
    var failed = 0
    func check(_ title: String, _ work: () throws -> Void) {
      do {
        try work()
        print("PASS " + title)
        passed += 1
      } catch {
        print("FAIL \(title): \(error)")
        failed += 1
      }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "sevra-app-checks-" + identifier())
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    if CommandLine.arguments.contains("--paging-benchmark") {
      check("Native app paging over 10,000 records") {
        let book = try Workbook.create(
          at: root.appendingPathComponent("Scale.sevra"), title: "Scale")
        let source = try book.addItem(category: "source", kind: "note", title: "Synthetic rows")
        let columns = [
          Column(id: "name", title: "Name"),
          Column(id: "quantity", title: "Quantity", type: "decimal"),
        ]
        let rows: [[String: Value]] = (0..<10_000).map {
          ["name": .string(String(format: "Item %05d", $0)), "quantity": .string(String($0))]
        }
        let table = try book.createDataset(
          title: "Scale", columns: columns, rows: rows, sourceID: source.id)
        let package = NativeAppPackage(
          name: "Scale", source: "Sevra.mount(Sevra.h(Sevra.Table,{table:'rows'}));",
          datasets: ["rows": .init(title: table.title, columns: columns, datasetID: table.id)])
        let space = try book.installNativeApp(package)
        let access = try NativeAppAccess(workbook: book, space: space)
        var durations: [Double] = []
        for index in 0..<30 {
          let start = Date()
          let page = try book.nativeAppPage(
            access,
            request: .object([
              "table": .string("rows"), "offset": .number(Double(index % 2 == 0 ? 0 : 9800)),
              "limit": .number(200),
            ]))
          durations.append(Date().timeIntervalSince(start) * 1000)
          try expect(page["total"] == .number(10_000) && page["rows"].array.count == 200)
          try expect(
            page["rows"].array.first?["values"]["name"].text
              == (index % 2 == 0 ? "Item 00000" : "Item 09800"))
        }
        durations.sort()
        print(
          "MEASURE native app 200-row page over 10,000 records: 30 alternating first/last samples, p50 \(durations[15]) ms, p95 \(durations[28]) ms"
        )
      }
      print("\(passed) passed, \(failed) failed")
      exit(failed == 0 ? 0 : 1)
    }
    var package = NativeAppPackage(
      name: "Records", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Ready'}));",
      datasets: [
        "rows": .init(
          title: "Records",
          columns: [
            .init(id: "name", title: "Name", required: true),
            .init(id: "amount", title: "Amount", type: "decimal"),
          ], writable: true)
      ])
    let book = try! Workbook.create(
      at: root.appendingPathComponent("Checks.sevra"), title: "Native apps")
    var saved: Space!
    var access: NativeAppAccess!
    var receipt: Value = .null
    check("Install is inert and saved in space history") {
      saved = try book.installNativeApp(package)
      access = try NativeAppAccess(workbook: book, space: saved)
      try expect(book.spaceHistory(saved.id).count == 1)
      try expect(
        book.nativeAppPage(access, request: .object(["table": .string("rows")]))["total"]
          == .number(0))
      _ = try book.verify()
    }
    let insert: Value = .object([
      "op": .string("insert"), "table": .string("rows"),
      "values": .object(["name": .string("Brass fitting"), "amount": .string("19.99")]),
    ])
    var base = 0
    check("Atomic command, idempotency and precise stored decimal") {
      base = try book.revision()
      receipt = try book.nativeAppTransaction(
        access, operations: [insert], expectedRevision: base, token: "insert-one")
      let retry = try book.nativeAppTransaction(
        access, operations: [insert], expectedRevision: base, token: "insert-one")
      try expect(receipt == retry)
      let page = try book.nativeAppPage(access, request: .object(["table": .string("rows")]))
      try expect(page["total"] == .number(1))
      try expect(page["rows"].array[0]["values"]["amount"] == .string("19.99"))
      _ = try book.verify()
    }
    check("Stale, unauthorized and invalid batches leave no changes") {
      let revision = try book.revision()
      try refuses {
        _ = try book.nativeAppTransaction(
          access, operations: [insert], expectedRevision: base, token: "stale")
      }
      try refuses {
        _ = try book.nativeAppTransaction(
          access,
          operations: [insert, .object(["op": .string("insert"), "table": .string("secret")])],
          expectedRevision: revision, token: "denied")
      }
      try expect(book.revision() == revision)
      try expect(
        book.nativeAppPage(access, request: .object(["table": .string("rows")]))["total"]
          == .number(1))
    }
    check("Delete undo and redo preserve immutable history") {
      let undone = try book.nativeAppTransaction(
        access, operations: [], expectedRevision: book.revision(), token: "undo-one",
        undo: "insert-one")
      try expect(
        book.nativeAppPage(access, request: .object(["table": .string("rows")]))["total"]
          == .number(0))
      _ = try book.nativeAppTransaction(
        access, operations: [], expectedRevision: book.revision(), token: "redo-one",
        undo: undone["token"].text)
      try expect(
        book.nativeAppPage(access, request: .object(["table": .string("rows")]))["total"]
          == .number(1))
      _ = try book.verify()
    }
    check("Draft persistence does not change business revision") {
      let revision = try book.revision()
      try book.saveNativeAppDraft(access, values: .object(["name": .string("Unsent input")]))
      try expect(book.revision() == revision)
      let reopened = try Workbook(book.url)
      try expect(reopened.nativeAppDraft(access)["name"] == .string("Unsent input"))
    }
    check("Portable copy and replay preserve app and data, but cannot reuse access") {
      let archive = root.appendingPathComponent("copy.sevraz")
      try book.export(to: archive) { _ in }
      let copy = try Workbook.openArchive(archive, at: root.appendingPathComponent("Copy.sevra"))
      try expect(copy.space(saved.id).definition.app == saved.definition.app)
      try refuses {
        _ = try copy.nativeAppPage(access, request: .object(["table": .string("rows")]))
      }
      let restored = try book.reconstruct(to: root.appendingPathComponent("Rebuilt.sevra"))
      try expect(restored.space(saved.id).definition.app == saved.definition.app)
      _ = try restored.verify()
    }
    check("Read-only bindings and exact-version revocation") {
      var readOnly = saved.definition.app!
      readOnly.name = "Reader"
      readOnly.datasets["rows"]?.writable = false
      let reader = try book.installNativeApp(readOnly)
      let permission = try NativeAppAccess(workbook: book, space: reader)
      try refuses {
        _ = try book.nativeAppTransaction(
          permission, operations: [insert], expectedRevision: book.revision(), token: "readonly")
      }
      package.source += "\n// revised"
      _ = try book.installNativeApp(package, spaceID: saved.id, expectedVersion: saved.version)
      try refuses {
        _ = try book.nativeAppPage(access, request: .object(["table": .string("rows")]))
      }
      permission.revoke()
      try refuses {
        _ = try book.nativeAppPage(permission, request: .object(["table": .string("rows")]))
      }
    }
    check("Signals emit incremental native property patches") {
      let runtime = NativeAppRuntime()
      let initial = try exchange(
        runtime,
        source:
          "var count=Sevra.signal(0); Sevra.mount(Sevra.h(Sevra.Column,{},Sevra.h(Sevra.Text,{text:()=>String(count.value)}),Sevra.h(Sevra.Button,{title:'Add',onClick:()=>count.value++}))); "
      )
      var tree = NativeAppTree()
      _ = try tree.apply(initial["frame"])
      let result = try exchange(
        runtime,
        messages: [
          .object([
            "kind": .string("event"), "node": .string("root/1"), "handler": .string("onClick"),
          ])
        ], sequence: 1)
      try expect(result["frame"]["patches"].array.count == 1)
      _ = try tree.apply(result["frame"])
      try expect(tree.nodes["root/0"]?.props["text"] == .string("1"))
    }
    check("Worker refuses stale sequence and missing host globals") {
      let runtime = NativeAppRuntime()
      let response = try exchange(
        runtime,
        source:
          "if(typeof fetch!=='undefined'||typeof std!=='undefined'||typeof os!=='undefined'||typeof Atomics!=='undefined')throw Error('ambient authority');Sevra.mount(Sevra.h(Sevra.Text,{text:'isolated'}));"
      )
      try expect(response["error"] == .null)
      let stale = try exchange(runtime, sequence: 8)
      try expect(stale["error"].string != nil)
    }
    check("Infinite loops and memory exhaustion are bounded failures") {
      let started = Date()
      let loop = try exchange(NativeAppRuntime(), source: "while(true){}")
      try expect(loop["error"].string != nil && Date().timeIntervalSince(started) < 3)
      let memory = try exchange(
        NativeAppRuntime(), source: "var a=[];for(;;)a.push(new Uint8Array(1048576));")
      try expect(memory["error"].string != nil)
    }
    check("Invalid trees refuse atomically, including native dimension coercion") {
      let runtime = NativeAppRuntime()
      let response = try exchange(runtime, source: package.source)
      var tree = NativeAppTree()
      _ = try tree.apply(response["frame"])
      let prior = tree.nodes
      let invalid = try Value.parse(
        "{\"version\":1,\"root\":\"root\",\"messages\":[],\"patches\":[{\"op\":\"put\",\"node\":{\"id\":\"root\",\"type\":\"text\",\"props\":{\"width\":\"999999999999\"},\"children\":[]}}]}"
      )
      try refuses { _ = try tree.apply(invalid) }
      try expect(tree.nodes == prior)
    }
    check("All three example programs mount and use only native controls") {
      for name in ["inventory", "jobs", "planner"] {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
          .appendingPathComponent("examples/apps/\(name)/app.sevraapp")
        let app = try NativeAppPackage.decode(Data(contentsOf: path))
        let result = try exchange(NativeAppRuntime(), source: app.source)
        try expect(result["error"] == .null, result["error"].text)
        var tree = NativeAppTree()
        _ = try tree.apply(result["frame"])
        try expect(tree.nodes.count > 3)
      }
    }
    if CommandLine.arguments.contains("--xpc") {
      do {
        try await xpcCheck(root: root)
        passed += 1
        print("PASS Packaged XPC/native/data/reactive/recovery journey")
      } catch {
        failed += 1
        print("FAIL Packaged XPC journey: \(error)")
      }
    }
    print("\(passed) passed, \(failed) failed")
    exit(failed == 0 ? 0 : 1)
  }
  @MainActor static func xpcCheck(root: URL) async throws {
    _ = NSApplication.shared
    let probeURL = URL(fileURLWithPath: "/private/tmp/sevra-app-probe-" + identifier())
    try Data("Synthetic sandbox probe".utf8).write(to: probeURL)
    defer { try? FileManager.default.removeItem(at: probeURL) }
    let probeConnection = NSXPCConnection(serviceName: NativeAppWire.service)
    probeConnection.remoteObjectInterface = NSXPCInterface(with: NativeAppWorkerProtocol.self)
    probeConnection.resume()
    defer { probeConnection.invalidate() }
    let probeData = try NativeAppWire.encode(
      .object(["kind": .string("sandboxProbe"), "file": .string(probeURL.path)]))
    let probeReply: Data = try await withCheckedThrowingContinuation { continuation in
      let proxy =
        probeConnection.remoteObjectProxyWithErrorHandler { error in
          continuation.resume(throwing: error)
        } as! NativeAppWorkerProtocol
      proxy.exchange(probeData) { continuation.resume(returning: $0) }
    }
    let probe = try NativeAppWire.decode(probeReply)
    try expect(
      [1, 13].contains(probe["fileErrno"].int ?? -1),
      "Sandbox did not deny the foreign file: " + probe.text)
    try expect(
      [1, 13].contains(probe["networkErrno"].int ?? -1),
      "Sandbox did not deny networking: " + probe.text)
    let book = try Workbook.create(at: root.appendingPathComponent("XPC.sevra"), title: "XPC check")
    let example = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("examples/apps/inventory/app.sevraapp")
    let package = try NativeAppPackage.decode(Data(contentsOf: example))
    let space = try book.installNativeApp(package)
    let defaults = UserDefaults(suiteName: "sevra.native-app-checks." + identifier())!
    let session = NativeAppSession(book: book, space: space, defaults: defaults)
    let renderer = NativeAppRenderer(session: session)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 850, height: 680),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentView = renderer
    session.enable()
    defer {
      session.revoke()
      window.orderOut(nil)
    }
    try await wait { session.status == "running" || session.status == "failed" }
    try expect(session.status == "running", session.error ?? session.status)
    try await wait {
      session.tree.nodes.values.contains { $0.props["text"].text == "0 items in stock" }
    }
    let fields = session.tree.nodes.values.filter { $0.type == "textField" }
    let name = fields.first { $0.props["label"].text == "Item name" }!
    let quantity = fields.first { $0.props["label"].text == "Quantity" }!
    session.event(
      node: name.id, handler: "onChange", value: .string("Native bolt"), editRevision: 1)
    session.event(node: quantity.id, handler: "onChange", value: .string("12"), editRevision: 1)
    let button = session.tree.nodes.values.first {
      $0.type == "button" && $0.props["title"].text == "Add item"
    }!
    try await wait { session.tree.nodes[name.id]?.props["value"] == .string("Native bolt") }
    guard let native = renderer.view(for: button.id) as? NSButton else {
      throw SevraError("test", "Missing native button")
    }
    session.event(
      node: name.id, handler: "onChange", value: .string("Native bolt"), editRevision: 2)
    native.performClick(nil)
    // A later edit in the same pending batch must not move in front of this Save action.
    session.event(node: name.id, handler: "onChange", value: .string("Later edit"), editRevision: 3)
    try await wait {
      session.tree.nodes.values.contains { $0.props["text"].text == "Saved to your workbook." }
    }
    let savedRows = try book.rows(space.definition.app!.datasets["stock"]!.datasetID!)
    try expect(
      savedRows.count == 1 && savedRows[0].data["name"] == .string("Native bolt"),
      "Event coalescing moved a later edit before Save")
    try await wait {
      session.tree.nodes.values.contains { $0.props["text"].text == "1 item in stock" }
    }
    func table(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView { return table }
      return view.subviews.compactMap { table(in: $0) }.first
    }
    guard let table = table(in: renderer) else { throw SevraError("test", "Missing native table") }
    try await wait { table.numberOfRows == 1 }
    window.contentView?.layoutSubtreeIfNeeded()
    guard let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView,
      let label = cell.textField
    else { throw SevraError("test", "Missing native table cell") }
    cell.layoutSubtreeIfNeeded()
    try expect(
      abs(label.frame.midY - cell.bounds.midY) < 1, "Table text is not vertically centered")
    try expect(table.tableColumns.last!.width > 250, "Native columns did not fill the table width")
    try expect(table.selectedRow == -1, "Saving must clear the controlled selection")
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try await wait { session.tree.nodes[name.id]?.props["value"] == .string("Native bolt") }
    let statusNode = session.tree.nodes.values.first {
      $0.props["label"] == .string("Save status")
    }!
    window.contentView?.layoutSubtreeIfNeeded()
    let statusLabel = renderer.view(for: statusNode.id) as! NSTextField
    try expect(
      statusLabel.bounds.height <= statusLabel.intrinsicContentSize.height + 1,
      "The native root stretched a status label into excess vertical space")
    let fieldBefore = renderer.view(for: name.id)
    session.event(
      node: name.id, handler: "onChange", value: .string("Retained draft"), editRevision: 4)
    try await wait { session.tree.nodes[name.id]?.props["value"] == .string("Retained draft") }
    try expect(fieldBefore === renderer.view(for: name.id), "Native field identity changed")
    let external = try NativeAppAccess(workbook: book, space: space)
    let page = try book.nativeAppPage(external, request: .object(["table": .string("stock")]))
    _ = try book.nativeAppTransaction(
      external,
      operations: [
        .object([
          "op": .string("update"), "table": .string("stock"), "id": page["rows"].array[0]["id"],
          "values": .object(["quantity": .string("31")]),
        ])
      ], expectedRevision: try book.revision(), token: identifier())
    await session.checkRevision()
    try await wait {
      (table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField?
        .stringValue == "31"
    }
    try expect(
      session.tree.nodes[name.id]?.props["value"] == .string("Retained draft"),
      "A background table refresh overwrote an unsaved form")
    try expect((renderer.view(for: name.id) as? NSTextField)?.stringValue == "Retained draft")
    window.setContentSize(NSSize(width: 520, height: 300))
    renderer.layoutSubtreeIfNeeded()
    let viewport = renderer.subviews.first as! NSScrollView
    let document = viewport.documentView!
    try expect(
      document.frame.height > viewport.contentSize.height,
      "Compact viewport lost its natural content height")
    viewport.contentView.scroll(
      to: NSPoint(x: 0, y: document.frame.height - viewport.contentSize.height))
    viewport.reflectScrolledClipView(viewport.contentView)
    try expect(
      abs(viewport.documentVisibleRect.maxY - document.frame.height) < 2,
      "Bottom controls are unreachable in a compact window")
    window.setContentSize(NSSize(width: 850, height: 680))
    session.stop()
    session.start()
    try await wait { session.status == "running" || session.status == "failed" }
    try expect(session.status == "running", session.error ?? "Restart failed")
    try await wait {
      session.tree.nodes.values.contains { $0.props["value"] == .string("Retained draft") }
    }
    _ = try book.verify()
    session.stop()
    let counterPackage = NativeAppPackage(
      name: "Counter",
      source:
        "var n=Sevra.signal(0);Sevra.mount(Sevra.h(Sevra.Column,{},Sevra.h(Sevra.Text,{text:()=>String(n.value)}),Sevra.h(Sevra.Button,{title:'Increment',onClick:()=>n.value++}))); "
    )
    let counterSpace = try book.installNativeApp(counterPackage)
    let counter = NativeAppSession(book: book, space: counterSpace, defaults: defaults)
    let counterView = NativeAppRenderer(session: counter)
    window.contentView = counterView
    counter.enable()
    defer { counter.revoke() }
    try await wait { counter.status == "running" || counter.status == "failed" }
    try expect(counter.status == "running", counter.error ?? "Counter failed")
    var timings: [Double] = []
    for index in 1...30 {
      let before = Date()
      counter.event(node: "root/1", handler: "onClick")
      try await wait { counter.tree.nodes["root/0"]?.props["text"] == .string(String(index)) }
      try expect((counterView.view(for: "root/0") as? NSTextField)?.stringValue == String(index))
      timings.append(Date().timeIntervalSince(before) * 1000)
    }
    timings.sort()
    print(
      "MEASURE native label event through XPC: 30 samples, p50 \(timings[15]) ms, p95 \(timings[28]) ms (1 ms observation interval)"
    )
    let kindsPackage = NativeAppPackage(
      name: "Controls",
      source: """
        const S=Sevra,h=S.h;
        S.mount(h(S.Column,{},h(S.Row,{},h(S.Toggle,{title:'Toggle',value:true}),h(S.Picker,{options:['A','B'],value:'A'}),h(S.Slider,{value:0.5,min:0,max:1}),h(S.DatePicker,{value:'2026-11-12T00:00:00Z'})),
        h(S.Grid,{columns:2},h(S.Text,{text:'A'}),h(S.Text,{text:'B'})),h(S.Split,{},h(S.Text,{text:'Left'}),h(S.Text,{text:'Right'})),
        h(S.Scroll,{height:100},h(S.Text,{text:'Scrolled'})),h(S.Tabs,{titles:['One','Two'],height:100},h(S.Text,{text:'Tab one'}),h(S.Text,{text:'Tab two'})),
        h(S.Disclosure,{title:'Details',value:true},h(S.Text,{text:'Expanded'})),h(S.TextEditor,{value:'Text',height:80}),h(S.Progress,{value:0.5}),h(S.Image,{symbol:'star',label:'Star'}),h(S.Canvas,{shapes:[],regions:[],height:80})));
        """)
    let controlsSpace = try book.installNativeApp(kindsPackage)
    let controls = NativeAppSession(book: book, space: controlsSpace, defaults: defaults)
    let controlsView = NativeAppRenderer(session: controls)
    window.contentView = controlsView
    controls.enable()
    defer { controls.revoke() }
    try await wait { controls.status == "running" || controls.status == "failed" }
    try expect(controls.status == "running", controls.error ?? "Controls failed")
    window.contentView?.layoutSubtreeIfNeeded()
  }
  @MainActor static func wait(_ predicate: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(8)
    while !predicate() {
      if Date() > deadline { throw SevraError("test", "Timed out waiting for native app state") }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }
}
