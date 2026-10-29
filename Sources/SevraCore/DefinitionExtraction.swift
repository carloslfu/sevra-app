import Foundation

/// A pinned native parser declaration. It grants no path, folder, model or
/// business-effect authority; its one input is an already included exact item.
struct DefinitionExtraction {
  let file: String
  static let parser = "native-v1"
  init(_ descriptor: DefinitionDescriptor) throws {
    let payload = try definitionObject(descriptor.payload, keys: ["parser", "file"])
    guard payload["parser"] == .string(Self.parser), let file = payload["file"]?.string,
      descriptor.parameters.count == 1, let parameter = descriptor.parameters.first,
      parameter.id == file && parameter.type == "item" && parameter.required
        && parameter.defaultValue == nil && parameter.unit == nil
    else {
      throw SevraError(
        "extraction_definition",
        "Declare native-v1, one required item parameter and its file parameter ID. Defaults are not allowed."
      )
    }
    self.file = file
  }
}
