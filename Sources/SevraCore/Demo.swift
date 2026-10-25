import Foundation

public enum Demo {
  @discardableResult public static func create(at url: URL) throws -> Value {
    let book = try Workbook.create(at: url, title: "Willow Workshop")
    let source = try book.addItem(
      category: "source", kind: "note", title: "Workshop inventory",
      text: "Synthetic example: opening stock of brass bolts was 20 on 1 January 2026.",
      status: "accepted")
    try book.setOpeningBalance(
      subject: "brass bolts", quantity: "20", effective: "2026-01-01T00:00:00Z", sourceID: source.id
    )
    let handover = try book.addItem(
      category: "source", kind: "observation", title: "Delivery 1042",
      text:
        "Synthetic example: on 2 January 2026 two brass bolts were handed over to Willow's customer. The delivery cost was 4.50.",
      status: "accepted")
    _ = try book.movement(
      subject: "brass bolts", quantity: "-2", occurrence: "delivery-1042",
      effective: "2026-01-02T00:00:00Z", input: handover.id, status: "accepted",
      token: "demo-delivery")
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
            "A small example workbook. Compare suppliers, inspect a delivery, or ask why stock is 18. All data is synthetic."
        ), .init(type: "table", title: "Supplier comparison", datasetID: table.id),
        .init(type: "chart", title: "Quoted cost", datasetID: table.id, x: "supplier", y: "total"),
      ]))
    _ = try book.addMessage(
      "This example has supplier quotes and a delivery. Try ‘Why do we have 18 brass bolts?’ or ‘Compare the supplier costs and show the evidence.’",
      role: "assistant")
    return .object(["path": .string(url.path), "datasetID": .string(table.id)])
  }
}
