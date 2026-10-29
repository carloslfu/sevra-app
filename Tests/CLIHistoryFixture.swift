import Foundation
import SevraCore

/// Build synthetic CLI evidence through the current captured mutation path.
func createCLIHistoryFixture(at url: URL) throws -> Value {
  let book = try Workbook.create(at: url, title: "Synthetic history")
  var ids: [Value] = []
  for n in 1...700 {
    ids.append(
      .string(
        try book.addMessage(
          "Supplier archive entry \(n)", role: n % 2 == 1 ? "user" : "assistant")))
  }
  return .object([
    "ids": .array(ids), "revision": .number(Double(try book.revision())),
    "integrity": try book.verify(),
  ])
}
