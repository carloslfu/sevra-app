import AppKit
import Foundation
import SevraAppProtocol
import SevraAppRuntime
import SevraAppUI
import SevraCore

private actor ConversationWorker {
  var runtime = NativeAppRuntime()
  func exchange(_ data: Data) throws -> Data {
    if try NativeAppWire.decode(data)["kind"] == .string("start") { runtime = NativeAppRuntime() }
    return runtime.exchange(data)
  }
}

@MainActor func conversationChecks(_ root: URL, useXPC: Bool = false) async throws {
  let book = try Workbook.create(
    at: root.appendingPathComponent("Conversation.sevra"), title: "Conversation")
  let package = NativeAppPackage(
    name: "Stock",
    source: """
      const S=Sevra,name=S.draftSignal('name',''),status=S.signal('Ready');
      const add=S.action('add',{title:'Add item',inputs:{name:{type:'text',title:'Item name'},quantity:{type:'decimal',title:'Quantity'}}},async(args)=>{
        if(!args.name.trim())throw Error('Name is required');
        if(Number(args.quantity)<=0)throw Error('Quantity must be positive');
        const receipt=await S.data.transaction([{op:'insert',table:'stock',values:args}]);
        status.value='Saved '+args.name;return {saved:args.name,receipt:receipt.token};
      });
      S.action('update',{title:'Update quantity',inputs:{row:{type:'text',title:'Row'}}},async({row})=>{
        const saved=await S.data.transaction([{op:'update',table:'stock',id:row,values:{quantity:'7'}}]);
        return {receipt:saved.token};
      });
      S.action('partial',{title:'Save and wait',inputs:{}},async()=>{await S.data.transaction([{op:'insert',table:'stock',values:{name:'Committed before stop',quantity:'1'}}]);await new Promise(()=>{});});
      S.mount(S.h(S.Column,{},S.h(S.TextField,{label:'Name',value:name}),S.h(S.Button,{title:'Add one',onClick:async()=>add({name:name.value,quantity:'1'})}),S.h(S.Text,{text:status}),S.h(S.Table,{table:'stock',label:'Stock',onSelect:e=>name.value=e.value.values.name}),S.h(S.Table,{table:'stock',label:'Stock review'}),S.h(S.Canvas,{label:'Board',width:300,height:200,regions:[{id:'card',label:'Card',x:0,y:0,width:100,height:50}],onDrop:e=>status.value='Moved '+e.value+' by '+e.x+','+e.y})));
      """,
    datasets: [
      "stock": .init(
        title: "Stock",
        columns: [
          .init(id: "name", title: "Name", required: true),
          .init(id: "quantity", title: "Quantity", type: "decimal"),
        ], writable: true)
    ])
  let space = try book.installNativeAppContents(package)
  let worker = ConversationWorker()
  let suite = "Sevra-chat-check-" + identifier()
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let transport: (@Sendable (Data) async throws -> Data)?
  if useXPC { transport = nil } else { transport = { data in try await worker.exchange(data) } }
  let session = NativeAppSession(book: book, space: space, defaults: defaults, exchange: transport)
  defer { session.stop() }
  let disabled = try await session.converse("inspect", readOnly: true)
  try expect(disabled["status"] == .string("disabled"))
  do {
    _ = try await session.converse("run", arguments: .object(["action": .string("add")]))
    throw SevraError("test", "Disabled app silently accepted an action")
  } catch let error as SevraError { try expect(error.code == "app_permission") }
  let homeRenderer = NativeAppRenderer(session: session)
  let appRenderer = NativeAppRenderer(session: session)
  defer {
    homeRenderer.disconnect()
    appRenderer.disconnect()
  }
  let ready = try await session.converse("enable")
  try expect(ready["actions"].array.first?["id"] == .string("add"))
  try expect(ready["actions"].array.first?["inputs"]["quantity"]["valueType"] == .string("string"))
  let nameNode = session.tree.nodes.values.first { $0.type == "textField" }!
  let homeField = homeRenderer.view(for: nameNode.id) as! NSTextField
  let appField = appRenderer.view(for: nameNode.id) as! NSTextField
  func edit(_ field: NSTextField, _ text: String) async throws {
    field.stringValue = text
    field.delegate?.controlTextDidChange?(
      Notification(name: NSControl.textDidChangeNotification, object: field))
    try await Checks.wait { homeField.stringValue == text && appField.stringValue == text }
  }
  try await edit(homeField, "First draft")
  try await edit(homeField, "Second draft")
  try await edit(appField, "Changed in the app")
  _ = try await session.converse(
    "set", arguments: .object(["target": .string("Name"), "value": .string("Changed in chat")]))
  try expect(
    homeField.stringValue == "Changed in chat" && appField.stringValue == "Changed in chat")
  try await edit(homeField, "Changed after chat")
  _ = try book.addMessage("Add Pencils with quantity 3", role: "user")
  let inserted = try await session.converse(
    "run",
    arguments: .object([
      "action": .string("add"),
      "inputs": .object(["name": .string("Pencils"), "quantity": .string("3")]),
    ]))
  try expect(inserted["outcome"] == .string("completed"))
  try expect(inserted["invocationInputContract"] == ready["actions"].array.first?["inputs"])
  try expect(inserted["changes"].array.count == 1)
  let dataset = space.definition.app!.datasets["stock"]!.datasetID!
  try expect(book.rows(dataset).count == 1)
  guard
    let statusNode = session.tree.nodes.values.first(where: {
      $0.type == "text" && $0.props["text"].text == "Saved Pencils"
    })
  else { throw SevraError("test", "Shared live status was missing") }
  try expect(
    (homeRenderer.view(for: statusNode.id) as? NSTextField)?.stringValue == "Saved Pencils")
  try expect((appRenderer.view(for: statusNode.id) as? NSTextField)?.stringValue == "Saved Pencils")
  homeRenderer.disconnect()
  _ = try await session.converse(
    "run",
    arguments: .object([
      "action": .string("add"),
      "inputs": .object(["name": .string("Pens"), "quantity": .string("2")]),
    ]))
  try expect(
    (appRenderer.view(for: statusNode.id) as? NSTextField)?.stringValue == "Saved Pens",
    "Detaching Home must not disconnect the full app")
  let undone = try await session.converse("undo")
  try expect(book.rows(dataset).count == 1)
  try expect(undone["canUndo"] == .bool(false) && undone["canRedo"] == .bool(true),
    "A second Undo must not silently redo the change")
  do {
    _ = try await session.converse("undo")
    throw SevraError("test", "A repeated Undo silently restored the change")
  } catch let error as SevraError { try expect(error.code == "app_undo") }
  try expect(book.rows(dataset).count == 1)
  let invalid = try await session.converse(
    "run",
    arguments: .object([
      "action": .string("add"),
      "inputs": .object(["name": .string("Invalid"), "quantity": .string("-1")]),
    ]))
  try expect(invalid["outcome"] == .string("failed"))
  try expect(invalid["changes"].array.isEmpty)
  try expect(invalid["canRedo"] == .bool(true), "A refused action must preserve Redo")
  try expect(book.rows(dataset).count == 1)
  do {
    _ = try await session.converse(
      "run", arguments: .object(["action": .string("add"), "inputs": .object([:])]), readOnly: true)
    throw SevraError("test", "Read-only action was allowed")
  } catch let error as SevraError { try expect(error.code == "read_only_request") }
  let selected = try await session.converse(
    "select",
    arguments: .object(["target": .string("Stock"), "rowID": .string(try book.rows(dataset)[0].id)])
  )
  try expect(
    selected["inputs"].array.contains {
      $0["fields"]["label"] == .string("Name") && $0["fields"]["value"] == .string("Pencils")
    })
  let moved = try await session.converse(
    "drop",
    arguments: .object([
      "target": .string("Board"), "region": .string("card"), "x": .number(20), "y": .number(-5),
    ]))
  try expect(moved["display"].array.contains(.string("Moved card by 20,-5")))
  _ = try await session.converse(
    "fill",
    arguments: .object([
      "inputs": .array([
        .object(["target": .string("Name"), "value": .string("Paper")])
      ])
    ]))
  _ = try book.addMessage("Saving the item", role: "assistant")
  let operated = try await session.converse(
    "activate", arguments: .object(["target": .string("Add one")]))
  try expect(operated["outcome"] == .string("completed"))
  try expect(operated["canUndo"] == .bool(true) && operated["canRedo"] == .bool(false),
    "A new saved change replaces the previous Redo")
  try expect(book.rows(dataset).count == 2)
  let browsed = try await session.converse(
    "browse",
    arguments: .object([
      "target": .string("Stock"), "sort": .string("name"), "descending": .bool(true),
      "search": .string("Pencils"),
    ]), readOnly: true)
  try expect(browsed["page"]["total"] == .number(1))
  try expect(browsed["page"]["rows"].array.first?["values"]["name"] == .string("Pencils"))
  let tableNode = session.tree.nodes.values.first { $0.props["label"] == .string("Stock") }!
  try expect(
    session.tableRequest(tableNode) == browsed["request"],
    "The optional renderer must read the same page settings")
  do {
    _ = try await session.converse(
      "browse", arguments: .object(["target": .string("Stock"), "sort": .string("missing")]),
      readOnly: true)
    throw SevraError("test", "Unknown sort column was accepted")
  } catch let error as SevraError { try expect(error.code != "test") }
  try expect(
    session.tableRequest(tableNode) == browsed["request"],
    "Rejected browsing must not change the view")
  _ = try await session.converse("undo")
  try expect(book.rows(dataset).count == 1)
  _ = try await session.converse("disable")
  try expect(!session.isGranted)
  let reopened = try Workbook(book.url)
  try expect(reopened.rows(dataset).count == 1)
  let restored = NativeAppSession(
    book: reopened, space: space, defaults: defaults, exchange: transport)
  defer { restored.stop() }
  let restoredState = try await restored.converse("enable")
  try expect(restoredState["canUndo"] == .bool(false) && restoredState["canRedo"] == .bool(true))
  restored.stop()
  let stoppedInspection = try await restored.converse("inspect")
  try expect(
    stoppedInspection["status"] == .string("disabled")
      && stoppedInspection["enabled"] == .bool(true),
    "Inspection must not execute an approved but stopped program")
  _ = try await restored.converse("restart")
  let redone = try await restored.converse("redo")
  try expect(redone["canUndo"] == .bool(true) && redone["canRedo"] == .bool(false))
  try expect(reopened.rows(dataset).count == 2)
  do {
    _ = try await restored.converse("redo")
    throw SevraError("test", "A repeated Redo silently undid the change")
  } catch let error as SevraError { try expect(error.code == "app_undo") }
  try expect(reopened.rows(dataset).count == 2)
  let pencil = try reopened.rows(dataset).first { $0.data["name"] == .string("Pencils") }!
  let refusedSelection = try await restored.converse(
    "select",
    arguments: .object(["target": .string("Stock review"), "rowID": .string(pencil.id)]))
  let selectedRow: Value = .object(["table": .string("stock"), "key": .string(pencil.logicalID)])
  try expect(refusedSelection["outcome"] == .string("failed"))
  try expect(refusedSelection["id"] == .string(space.id))
  try expect(refusedSelection["version"].int == space.version)
  try expect(refusedSelection["unavailableSelection"] == selectedRow)
  try expect(refusedSelection["changes"] == .array([]))
  try expect(reopened.item(pencil.logicalID).id == pencil.id)
  let update = try await restored.converse(
    "run",
    arguments: .object([
      "action": .string("update"), "inputs": .object(["row": .string(pencil.id)]),
    ]))
  try expect(update["outcome"] == .string("completed"))
  try expect(update["updatedRows"] == .array([selectedRow]))
  let savedPencil = try reopened.item(pencil.logicalID)
  try expect(savedPencil.id != pencil.id && savedPencil.data["quantity"] == .string("7"))
  do {
    _ = try await restored.converse(
      "select",
      arguments: .object(["target": .string("Stock review"), "rowID": .string(pencil.id)]))
    throw SevraError("test", "Stale row version supplied selection-recovery evidence")
  } catch let error as SevraError { try expect(error.code == "app_row") }
  let cancellation = Cancellation()
  let interrupted = Task {
    try await restored.converse(
      "run", arguments: .object(["action": .string("partial"), "inputs": .object([:])]),
      cancellation: cancellation)
  }
  let deadline = Date().addingTimeInterval(3)
  while try reopened.rows(dataset).count < 3 && Date() < deadline {
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  cancellation.cancel()
  do {
    _ = try await interrupted.value
    throw SevraError("test", "Cancelled action reported completion")
  } catch let error as SevraError { try expect(error.code == "cancelled") }
  try expect(restored.status == "disabled")
  try expect(
    reopened.rows(dataset).count == 3, "Committed partial results must survive cancellation")
  _ = try await restored.converse("disable")
  print(
    "PASS conversation: named action, real writes, validation, existing controls, read-only refusal, row selection, canvas deltas, Undo, revoke, reopen and cancellation with preserved partial results without a renderer"
  )
}
