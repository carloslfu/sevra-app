import AppKit
import Foundation
import SevraAppProtocol
import SevraAppUI
import SevraCore

extension Checks {
  @MainActor static func removedCanvasRegionCheck(root: URL) async throws {
    let book = try Workbook.create(at: root.appendingPathComponent("Canvas.sevra"), title: "Canvas")
    let package = NativeAppPackage(
      name: "Changing canvas",
      source: """
        const S=Sevra,h=S.h;
        const regions=S.signal([{id:'first',label:'First',x:0,y:0,width:30,height:30},{id:'second',label:'Second',x:40,y:0,width:30,height:30}]);
        const status=S.signal('Ready');let count=0;
        function action(e){status.value=e.value+':'+(++count);}
        S.mount(h(S.Column,{},h(S.Canvas,{regions,shapes:[],height:80,onClick:action,onDrop:action}),
          h(S.Button,{title:'Remove selected',onClick:()=>regions.value=regions.value.filter(r=>r.id!=='first')}),h(S.Text,{text:status})));
        """)
    let space = try book.installNativeApp(package)
    let domain = "sevra.canvas-removal." + identifier()
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let session = NativeAppSession(book: book, space: space, defaults: defaults)
    let renderer = NativeAppRenderer(session: session)
    session.enable()
    defer { session.revoke() }
    try await wait { session.status == "running" || session.status == "failed" }
    try expect(session.status == "running", session.error ?? session.status)
    let canvas = renderer.view(for: "root/0")!
    let old = canvas.accessibilityChildren()!.first as! NSAccessibilityElement
    try expect(old.accessibilityPerformPress())
    try await wait { session.tree.nodes["root/2"]?.props["text"] == .string("first:1") }
    session.event(node: "root/1", handler: "onClick")
    try await wait { session.tree.nodes["root/0"]?.props["regions"].array.count == 1 }
    let right = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 124)!
    canvas.keyDown(with: right)
    try await wait { session.tree.nodes["root/2"]?.props["text"].text.hasSuffix(":2") == true }
    try expect(
      session.tree.nodes["root/2"]?.props["text"] == .string("second:2"),
      "Keyboard action reached a removed canvas region")
    try expect(!old.accessibilityPerformPress(), "Removed accessibility region remained actionable")
    let current = canvas.accessibilityChildren()!.first as! NSAccessibilityElement
    try expect(current.accessibilityPerformPress())
    try await wait { session.tree.nodes["root/2"]?.props["text"] == .string("second:3") }
  }

  @MainActor static func remountedInputCheck(root: URL) async throws {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Remount.sevra"), title: "Remount")
    let package = NativeAppPackage(
      name: "Remounted form",
      source: """
        const S=Sevra,h=S.h,switched=S.signal(false);
        function Field({initial}) { const value=S.signal(initial); return h(S.TextField,{label:'Editor',value}); }
        S.mount(h(S.Column,{},()=>h(Field,{initial:switched.value?'Second':'First'}),
          h(S.Button,{title:'Switch form',onClick:()=>switched.value=!switched.value})));
        """)
    let space = try book.installNativeApp(package)
    let domain = "sevra.remount." + identifier()
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let session = NativeAppSession(book: book, space: space, defaults: defaults)
    let renderer = NativeAppRenderer(session: session)
    session.enable()
    defer { session.revoke() }
    try await wait { session.status == "running" || session.status == "failed" }
    try expect(session.status == "running", session.error ?? session.status)
    let field = renderer.view(for: "root/0") as! NSTextField
    field.stringValue = "Typed first"
    field.delegate?.controlTextDidChange?(
      Notification(name: NSControl.textDidChangeNotification, object: field))
    try await wait { session.tree.nodes["root/0"]?.props["value"] == .string("Typed first") }
    session.event(node: "root/1", handler: "onClick")
    try await wait { session.tree.nodes["root/0"]?.props["value"] == .string("Second") }
    try expect(
      (renderer.view(for: "root/0") as? NSTextField)?.stringValue == "Second",
      "Remounted input retained the prior control's text/revision")
  }

  static func schemaAccessCheck(root: URL) throws {
    let book = try Workbook.create(at: root.appendingPathComponent("Schema.sevra"), title: "Schema")
    let source = try book.addItem(category: "source", kind: "note", title: "Synthetic fixture")
    let columns = [Column(id: "name", title: "Name")]
    let table = try book.createDataset(
      title: "Approved", columns: columns, rows: [["name": .string("Public")]], sourceID: source.id)
    let package = NativeAppPackage(
      name: "Reader", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Reader'}));",
      datasets: ["rows": .init(title: "Approved", columns: columns, datasetID: table.id)])
    let space = try book.installNativeApp(package)
    let access = try NativeAppAccess(workbook: book, space: space)
    let request: Value = .object(["table": .string("rows")])
    let query = try Value.parse(
      """
      {"sources":[{"table":"rows"}],"select":[{"id":"value","column":{"source":0,"column":"name"}}]}
      """)
    try expect(book.nativeAppPage(access, request: request)["total"] == .number(1))
    try expect(book.nativeAppQuery(access, request: query)["rows"].array.count == 1)
    // Renaming the same table does not expand its approved schema.
    let base = try book.datasetDefinition(table.id)
    _ = try book.updateDatasetDefinition(
      table.id, expectedVersion: base.version, expectedDefinitionID: base.id, title: "Renamed")
    try expect(book.nativeAppPage(access, request: request)["total"] == .number(1))
    try book.setColumns(table.id, columns: columns + [.init(id: "secret", title: "Private field")])
    let row = try book.rows(table.id)[0]
    _ = try book.editRows(
      table.id,
      edits: [
        .init(
          id: row.id, values: ["name": .string("Public"), "secret": .string("Synthetic secret")])
      ])
    try refuses { _ = try book.nativeAppPage(access, request: request) }
    try refuses { _ = try book.nativeAppQuery(access, request: query) }
    try refuses { _ = try book.nativeAppFingerprints(access) }
    var revised = package
    revised.datasets["rows"]!.columns = try book.dataset(table.id).columns
    let updated = try book.installNativeApp(
      revised, spaceID: space.id, expectedVersion: space.version)
    let fresh = try NativeAppAccess(workbook: book, space: updated)
    try expect(
      book.nativeAppPage(fresh, request: request)["rows"].array[0]["values"]["secret"]
        == .string("Synthetic secret"))
    let current = try book.datasetDefinition(table.id)
    _ = try book.updateDatasetDefinition(
      table.id, expectedVersion: current.version, expectedDefinitionID: current.id, archived: true)
    try refuses { _ = try book.nativeAppPage(fresh, request: request) }
    try refuses { _ = try book.nativeAppQuery(fresh, request: query) }
    _ = try book.verify()
  }

  @MainActor static func controlledWidgetsCheck(root: URL) async throws {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Widgets.sevra"), title: "Widgets")
    let source = try book.addItem(category: "source", kind: "note", title: "Synthetic fixture")
    let columns = [Column(id: "name", title: "Name")]
    let table = try book.createDataset(
      title: "Rows", columns: columns,
      rows: [["name": .string("Zulu")], ["name": .string("Alpha")]], sourceID: source.id)
    let selected = try book.rows(table.id)[1].logicalID
    let package = NativeAppPackage(
      name: "Controlled widgets",
      source: """
        const S=Sevra,h=S.h; const titles=S.signal(['One','Two']), clicks=S.signal(0), active=S.signal(false); let renamed=0;
        S.mount(h(S.Column,{},
          h(S.Tabs,{label:'Panels',titles,value:1},h(S.Text,{text:'First'}),h(S.Text,{text:'Second'})),
          h(S.Button,{title:'Rename tab',onClick:()=>titles.value=['One','Renamed '+(++renamed)]}),
        h(S.Table,{label:'Rows',table:'rows',sort:'name',selection:\(try Value.string(selected).json()),height:200}),
        h(S.Column,{enabled:active},h(S.Button,{title:'Blocked',onClick:()=>clicks.value++})),
        h(S.Text,{text:()=>String(clicks.value)}),
        h(S.Tabs,{enabled:false,titles:['Locked','Other'],value:0},h(S.Text,{text:'Locked'}),h(S.Text,{text:'Other'})),
        h(S.Disclosure,{enabled:false,title:'Locked details',value:false},h(S.Text,{text:'Details'})),
        h(S.Table,{enabled:false,table:'rows',label:'Disabled rows',height:100}),
        h(S.Button,{title:'Enable action',onClick:()=>active.value=true}),
        h(S.Disclosure,{title:'Working details',value:false},h(S.Text,{text:'Visible details'}))));
        """, datasets: ["rows": .init(title: "Rows", columns: columns, datasetID: table.id)])
    let space = try book.installNativeApp(package)
    let domain = "sevra.adversarial." + identifier()
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let session = NativeAppSession(book: book, space: space, defaults: defaults)
    let renderer = NativeAppRenderer(session: session)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.contentView = renderer
    session.enable()
    defer {
      session.revoke()
      window.orderOut(nil)
    }
    try await wait { session.status == "running" || session.status == "failed" }
    try expect(session.status == "running", session.error ?? session.status)
    let tabs = renderer.view(for: "root/0") as! NSTabView
    func findTable(_ view: NSView) -> NSTableView? {
      if let table = view as? NSTableView { return table }
      return view.subviews.compactMap(findTable).first
    }
    let grid = findTable(renderer)!
    try await wait { grid.numberOfRows == 2 }
    var failures: [String] = []
    if tabs.selectedTabViewItem?.identifier as? String != "root/0/1" {
      failures.append("Initial tab selection ignored")
    }
    let first = grid.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView
    if first?.textField?.stringValue != "Alpha" {
      failures.append("Initial native table sort ignored")
    }
    if grid.selectedRow != 0 { failures.append("Initial controlled row selection ignored") }
    if grid.sortDescriptors.first?.key != "name" || grid.sortDescriptors.first?.ascending != true {
      failures.append("Initial table sort indicator missing")
    }
    session.event(node: "root/1", handler: "onClick")
    try await wait {
      session.tree.nodes["root/0"]?.props["titles"].array.last == .string("Renamed 1")
    }
    if tabs.tabViewItems.last?.label != "Renamed 1" {
      failures.append("Reactive tab title ignored")
    }
    let blocked = renderer.view(for: "root/3/0") as! NSButton
    if blocked.isEnabled { failures.append("Disabled ancestor left its native button enabled") }
    let disclosure = renderer.view(for: "root/6") as! NSStackView
    let disclosureHeader = disclosure.arrangedSubviews.first as! NSStackView
    let disclosureButton = disclosureHeader.arrangedSubviews.first as! NSButton
    if disclosureButton.isEnabled {
      failures.append("Disabled disclosure still actionable")
    }
    let disclosureTitle = disclosureHeader.arrangedSubviews[1] as! NSTextField
    try expect(disclosureTitle.stringValue == "Locked details")
    try expect(disclosureButton.accessibilityLabel() == "Locked details")
    let workingDisclosure = renderer.view(for: "root/9") as! NSStackView
    let workingHeader = workingDisclosure.arrangedSubviews[0] as! NSStackView
    let workingButton = workingHeader.arrangedSubviews[0] as! NSButton
    try expect(workingDisclosure.arrangedSubviews[1].isHidden)
    workingButton.performClick(nil)
    try expect(!workingDisclosure.arrangedSubviews[1].isHidden && workingButton.state == .on)
    workingButton.performClick(nil)
    try expect(workingDisclosure.arrangedSubviews[1].isHidden && workingButton.state == .off)
    let disabledTable = findTable(renderer.view(for: "root/7")!)!
    if disabledTable.isEnabled { failures.append("Disabled table still selectable") }
    let locked = renderer.view(for: "root/5") as! NSTabView
    if locked.delegate?.tabView?(locked, shouldSelect: locked.tabViewItems[1]) != false {
      failures.append("Disabled tabs still actionable")
    }
    try expect(locked.alphaValue < 1 && !locked.isAccessibilityEnabled())
    grid.sortDescriptors = [NSSortDescriptor(key: "name", ascending: false)]
    try await wait {
      (grid.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?
        .textField?.stringValue == "Zulu"
    }
    try expect(grid.selectedRow == 1, "Sorting lost the selected logical row")
    session.event(node: "root/3/0", handler: "onClick")
    // An enabled action behind it establishes that the queued event batch has completed.
    session.event(node: "root/1", handler: "onClick")
    try await wait {
      session.tree.nodes["root/0"]?.props["titles"].array.last == .string("Renamed 2")
    }
    if session.tree.nodes["root/4"]?.props["text"] != .string("0") {
      failures.append("Host dispatched a disabled action")
    }
    session.event(node: "root/8", handler: "onClick")
    try await wait { session.tree.nodes["root/3"]?.props["enabled"] == .bool(true) }
    try expect(blocked.isEnabled, "Reenabled descendant remained disabled")
    blocked.performClick(nil)
    try await wait { session.tree.nodes["root/4"]?.props["text"] == .string("1") }
    try expect(failures.isEmpty, failures.joined(separator: "; "))
  }

  @MainActor static func sharedRevocationCheck(root: URL) async throws {
    let book = try Workbook.create(
      at: root.appendingPathComponent("Revocation.sevra"), title: "Revocation")
    let package = NativeAppPackage(
      name: "Shared grant", source: "Sevra.mount(Sevra.h(Sevra.Text,{text:'Ready'}));",
      datasets: [
        "rows": .init(title: "Rows", columns: [.init(id: "name", title: "Name")], writable: true)
      ])
    let space = try book.installNativeApp(package)
    let domain = "sevra.adversarial." + identifier()
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    let first = NativeAppSession(book: book, space: space, defaults: defaults)
    let second = NativeAppSession(book: book, space: space, defaults: defaults)
    first.enable()
    try await wait { first.status == "running" || first.status == "failed" }
    second.start()
    try await wait { second.status == "running" || second.status == "failed" }
    defer {
      first.revoke()
      second.stop()
    }
    try expect(first.status == "running" && second.status == "running")
    let stale = second.access!
    let request: Value = .object(["table": .string("rows")])
    let insert = try Value.parse(
      "{\"op\":\"insert\",\"table\":\"rows\",\"values\":{\"name\":\"Denied\"}}")
    try expect(book.nativeAppPage(stale, request: request)["total"] == .number(0))
    first.revoke()
    try refuses { _ = try book.nativeAppPage(stale, request: request) }
    try refuses {
      _ = try book.nativeAppTransaction(
        stale, operations: [insert], expectedRevision: book.revision(), token: identifier())
    }
    first.enable()
    try await wait { first.status == "running" || first.status == "failed" }
    // Reapproval must not resurrect an old running worker's authority.
    try refuses { _ = try book.nativeAppPage(stale, request: request) }
    try expect(book.nativeAppPage(first.access!, request: request)["total"] == .number(0))
    let revokedAfterAdmission = Cancellation()
    let commitFence = try NativeAppAccess(
      workbook: book, space: space,
      permission: {
        if revokedAfterAdmission.isCancelled { return false }
        revokedAfterAdmission.cancel()
        return true
      })
    let revision = try book.revision()
    try refuses {
      _ = try book.nativeAppTransaction(
        commitFence, operations: [insert], expectedRevision: revision, token: identifier())
    }
    try expect(book.revision() == revision)
    _ = try book.verify()
  }
}
