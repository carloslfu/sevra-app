import SevraCore

/// Workbook-owned schemas. Inference adapters translate these declarations at
/// their boundary; the workbook does not import an inference implementation.
package struct WorkbookToolDefinition: Sendable {
  package let name: String
  package let description: String
  package let parameters: Value
  package init(name: String, description: String, parameters: Value) {
    self.name = name
    self.description = description
    self.parameters = parameters
  }
}
