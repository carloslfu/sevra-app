import Foundation

public enum Demo {
  @discardableResult public static func create(at url: URL) throws -> Value {
    let book = try Workbook.create(at: url, title: "Willow Workshop")
    let quotes = try book.addItem(
      category: "source", kind: "note", title: "Supplier quotes",
      text:
        "Synthetic quotes: Oak Supply, 10 brass bolts at 2.40 each. Cedar Tools, 10 brass bolts at 2.75 each. Both quotes exclude delivery.",
      status: "accepted")
    let table = try book.createDataset(
      title: "Supplier comparison",
      columns: [
        .init(id: "supplier", title: "Supplier"),
        .init(id: "quantity", title: "Quantity", type: "decimal"),
        .init(id: "unit_cost", title: "Unit cost", type: "decimal"),
        .init(id: "total", title: "Total", type: "decimal", formula: "quantity*unit_cost"),
      ],
      rows: [
        [
          "supplier": .string("Oak Supply"), "quantity": .string("10"),
          "unit_cost": .string("2.40"),
        ],
        [
          "supplier": .string("Cedar Tools"), "quantity": .string("10"),
          "unit_cost": .string("2.75"),
        ],
      ], sourceID: quotes.id)
    _ = try book.saveSpace(
      id: "home", title: "Home",
      definition: .init(components: [
        .init(
          type: "text", title: "Willow Workshop",
          text:
            "A small example workbook with two supplier quotes. Ask in chat to compare them, make a view or change a price. All data is synthetic."
        ), .init(type: "table", title: "Supplier comparison", datasetID: table.id),
        .init(type: "chart", title: "Quoted cost", datasetID: table.id, x: "supplier", y: "total"),
      ]), expectedVersion: 1)
    _ = try book.addMessage(
      "This example has a table of two supplier quotes. Try ‘Which supplier is cheaper, and by how much?’, ‘Make a view with a chart of each supplier’s total’ or ‘Change Cedar Tools to 2.60 each.’",
      role: "assistant", conversation: try book.chats()[0].id)
    return .object(["path": .string(url.path), "datasetID": .string(table.id)])
  }
}
