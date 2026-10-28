import Foundation

extension Workbook {
  /// Missing means the initial state before this family has been edited. Every
  /// relevant captured write sets its clock to that transaction's commit ID.
  func definitionReadSnapshot() throws -> String {
    try db.scalar("SELECT value FROM meta WHERE key='definition-read-snapshot'").string ?? "initial"
  }
  func datasetReadSnapshot() throws -> String {
    try db.scalar("SELECT value FROM meta WHERE key='dataset-read-snapshot'").string ?? "initial"
  }
}
