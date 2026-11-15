import Foundation
import SevraAppProtocol
import SevraCore

func checkNativeAssertionContracts(_ workspace: NativeAppPackage) async throws {
  func decoded(_ text: String) throws -> [Value] { try Value.parse(text).array }
  var typed = workspace
  typed.source = """
    Sevra.action('quote',{title:'Quote',inputs:{amount:{type:'decimal'},count:{type:'number'},active:{type:'boolean'}}},()=>{});
    Sevra.mount(Sevra.h(Sevra.Text,{text:'Typed contract'}));
    """
  let contract = try await NativeAppCheck.run(
    package: typed,
    steps: decoded(
      #"[{"kind":"run_action","action":"quote","inputs":{"amount":"2.25","count":2,"active":true}},{"kind":"expect_text","value":"Typed contract"}]"#
    ))
  for (field, valueType) in [("amount", "string"), ("count", "number"), ("active", "boolean")] {
    try expectEqual(contract["actionInputs"]["quote"][field]["valueType"], .string(valueType))
  }
  try expectEqual(contract["initialInterface"].array.isEmpty, false)
  for node in contract["initialInterface"].array {
    try expectEqual(node["props"]["value"], .null)
    try expectEqual(node["props"]["text"], .null)
    try expectEqual(node["source"], .null)
  }
  do {
    _ = try await NativeAppCheck.run(
      package: typed,
      steps: decoded(
        #"[{"kind":"run_action","action":"quote","inputs":{"amount":2.25,"count":2,"active":true},"reject":true}]"#
      ))
    throw SevraError("test", "A numeric decimal argument was accepted as a business refusal.")
  } catch {
    try expectEqual((error as? SevraError)?.code, "app_check")
    try expectEqual(error.localizedDescription.contains("amount requires JSON string"), true)
  }
  var tabs = workspace
  tabs.source = """
    Sevra.mount(Sevra.h(Sevra.Tabs,{label:'Pages',titles:['Inputs','Results'],value:Sevra.signal(0)},Sevra.h(Sevra.Text,{text:'First content'}),Sevra.h(Sevra.Text,{text:'Second content'})));
    """
  do {
    _ = try await NativeAppCheck.run(
      package: tabs, steps: decoded(#"[{"kind":"expect_text","value":"Results"}]"#))
    throw SevraError("test", "A tab title was mistaken for Text content.")
  } catch {
    try expectEqual((error as? SevraError)?.code, "app_check_assertion")
    try expectEqual(error.localizedDescription.contains("existing native tab title"), true)
    try expectEqual(error.localizedDescription.contains(#""target":"Pages""#), true)
  }
  _ = try await NativeAppCheck.run(
    package: tabs,
    steps: decoded(
      #"[{"kind":"select","target":"Pages","value":1},{"kind":"expect_text","value":"Second content"}]"#
    ))
  let match = try decoded(
    #"[{"kind":"expect_row","table":"entries","values":{"name":"A"}}]"#)
  func fixtures(_ names: [Value]) -> Value {
    .object(["entries": .array(names.map { .object(["name": $0]) })])
  }
  _ = try await NativeAppCheck.run(
    package: workspace, steps: match,
    fixtures: fixtures([.string("Header"), .string("A"), .string("B")]))
  var completed: [Int] = []
  do {
    let absent = try decoded(
      #"[{"kind":"expect_row","table":"entries","values":{"name":"absent"}}]"#)
    _ = try await NativeAppCheck.run(
      package: workspace, steps: match + absent,
      fixtures: fixtures([.string("A")]), testProgress: { completed.append($0) })
    throw SevraError("test", "A failed assertion was reported as completed.")
  } catch {
    try expectEqual((error as? SevraError)?.code, "app_check_assertion")
    try expectEqual(completed, [1])
  }
  for names in [[], [.string("B")], [.string("A"), .string("A")]] as [[Value]] {
    do {
      _ = try await NativeAppCheck.run(
        package: workspace, steps: match, fixtures: fixtures(names))
      throw SevraError("test", "An absent or duplicate row passed a unique saved-row assertion.")
    } catch {
      try expectEqual((error as? SevraError)?.code, "app_check_assertion")
    }
  }
  for test in [
    #"{"kind":"expect_row","table":"entries","values":{}}"#,
    #"{"kind":"expect_row","table":"entries","values":{"name":"A"},"count":2}"#,
    #"{"kind":"expect_row","table":"entries","values":{"unknown":"A"}}"#,
    #"{"kind":"expect_rows","table":"entries","values":"ignored","count":0}"#,
  ] {
    do {
      _ = try await NativeAppCheck.run(package: workspace, steps: [Value.parse(test)])
      throw SevraError("test", "Malformed saved-row assertion passed.")
    } catch {
      try expectEqual((error as? SevraError)?.code, "app_check")
    }
  }
  var paged = workspace
  paged.source = """
    Sevra.action('fill',{title:'Fill',inputs:{duplicate:{type:'boolean'}}},async inputs=>{
      for(let page=0;page<4;page++){
        const operations=[];
        for(let offset=0;offset<64;offset++){
          const index=page*64+offset;
          const name=index===0||(inputs.duplicate&&index===255)?'Target':'R'+index;
          operations.push({op:'insert',table:'entries',values:{name}});
        }
        await Sevra.data.transaction(operations);
      }
    });
    Sevra.mount(Sevra.h(Sevra.Text,{text:'Paged assertion'}));
    """
  _ = try await NativeAppCheck.run(
    package: paged,
    steps: decoded(
      #"[{"kind":"run_action","action":"fill","inputs":{"duplicate":false}},{"kind":"expect_row","table":"entries","values":{"name":"R255"}},{"kind":"expect_row","table":"entries","values":{"name":"Target"}}]"#
    ))
  do {
    _ = try await NativeAppCheck.run(
      package: paged,
      steps: decoded(
        #"[{"kind":"run_action","action":"fill","inputs":{"duplicate":true}},{"kind":"expect_row","table":"entries","values":{"name":"Target"}}]"#
      ))
    throw SevraError("test", "A duplicate after the first 200 rows escaped the assertion.")
  } catch {
    try expectEqual((error as? SevraError)?.code, "app_check_assertion")
    try expectEqual(error.localizedDescription.contains("found 2"), true)
  }
  var rejecting = workspace
  rejecting.source = """
    Sevra.action('add',{title:'Add',inputs:{name:{type:'text'}}},async inputs=>{
      if(inputs.name==='Closed')throw Error('This entry is unavailable');
      await Sevra.data.transaction([{op:'insert',table:'entries',values:inputs}]);
    });
    Sevra.mount(Sevra.h(Sevra.Text,{text:'Boundary probe'}));
    """
  let reject = try decoded(
    #"[{"kind":"run_action","action":"add","inputs":{"name":"Closed"},"reject":true}]"#)
  let report = try await NativeAppCheck.run(package: rejecting, steps: reject)
  try expectEqual(report["assertions"], .number(1))
  for fields in [
    ["reject": Value.bool(false)],
    ["reject": .bool(true), "error": .string("unavailable")],
    ["error": .bool(true)],
  ] {
    var test = reject[0].object
    test.removeValue(forKey: "reject")
    test.merge(fields) { _, new in new }
    do {
      _ = try await NativeAppCheck.run(
        package: rejecting,
        steps: [
          .object(test), .object(["kind": .string("expect_text"), "value": .string("Boundary")]),
        ])
      throw SevraError("test", "A malformed refusal assertion was ignored.")
    } catch {
      try expectEqual((error as? SevraError)?.code, "app_check")
    }
  }
  for (input, code) in [(Value.string("Open"), "app_check_assertion"), (.number(42), "app_check")] {
    var test = reject[0].object
    test["inputs"] = .object(["name": input])
    do {
      _ = try await NativeAppCheck.run(package: rejecting, steps: [.object(test)])
      throw SevraError(
        "test", "Successful action or malformed inputs satisfied a business refusal.")
    } catch {
      try expectEqual((error as? SevraError)?.code, code)
    }
  }
  var partial = rejecting
  partial.source = """
    Sevra.action('add',{title:'Add',inputs:{name:{type:'text'}}},async inputs=>{
      await Sevra.data.transaction([{op:'insert',table:'entries',values:inputs}]);
      throw Error('Rejected after writing');
    });
    Sevra.mount(Sevra.h(Sevra.Text,{text:'Boundary probe'}));
    """
  do {
    _ = try await NativeAppCheck.run(package: partial, steps: reject)
    throw SevraError("test", "A refusal assertion accepted partial writes.")
  } catch {
    try expectEqual((error as? SevraError)?.code, "app_check_assertion")
    try expectEqual(error.localizedDescription.contains("committed a data change"), true)
  }
  print(
    "PASS unambiguous unique-row and refusal assertions; absence, duplicates, malformed inputs and partial writes fail"
  )
}
