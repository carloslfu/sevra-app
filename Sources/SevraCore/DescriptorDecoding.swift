import Foundation

/// Decodes a descriptor the model or a person wrote, and names the field that does not fit.
/// Foundation's own words for a missing key are "The data couldn’t be read because it is
/// missing", which tells neither of them what to change.
func decodeDescriptor<T: Decodable>(_ type: T.Type, from value: Value, named name: String)
  throws -> T
{
  do {
    return try JSONDecoder().decode(type, from: Data(value.json().utf8))
  } catch let error as DecodingError {
    throw SevraError("arguments", describeDecodingFailure(error, of: name))
  }
}

/// Which field of `name` a decoding failure is about, in a sentence.
public func describeDecodingFailure(_ error: DecodingError, of name: String) -> String {
  func path(_ keys: [CodingKey]) -> String {
    keys.map { key in key.intValue.map { "[\($0)]" } ?? key.stringValue }
      .joined(separator: ".").replacingOccurrences(of: ".[", with: "[")
  }
  // The named argument leads the path, so an error inside a list reads edits[0].component.
  func named(_ keys: [CodingKey]) -> String {
    let rest = path(keys)
    if name.isEmpty { return rest.isEmpty ? "The call" : rest }
    return rest.isEmpty ? name : rest.hasPrefix("[") ? name + rest : name + "." + rest
  }
  switch error {
  case .keyNotFound(let key, let context):
    return named(context.codingPath + [key]) + " is missing."
  case .valueNotFound(_, let context):
    return named(context.codingPath) + " needs a value."
  case .typeMismatch(_, let context):
    return named(context.codingPath) + " has the wrong kind of value."
  case .dataCorrupted(let context):
    let choices =
      context.debugDescription.hasPrefix(acceptedValuesPrefix)
      ? " " + context.debugDescription : ""
    return context.codingPath.isEmpty
      ? named([]) + " is not valid."
      : named(context.codingPath) + " is not a value it accepts." + choices
  @unknown default:
    return name + " is not valid."
  }
}

/// A failure in the words to show. A decoding failure names its field.
public func failureDescription(_ error: Error) -> String {
  (error as? DecodingError).map { describeDecodingFailure($0, of: "") }
    ?? error.localizedDescription
}

let acceptedValuesPrefix = "Use one of: "

/// A closed set of names a descriptor may use. An unknown name fails with the accepted ones, so
/// whoever wrote it can pick one instead of guessing what else is wrong.
public protocol AcceptedValues: RawRepresentable, CaseIterable, Decodable
where RawValue == String {}
extension AcceptedValues {
  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let value = Self(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: acceptedValuesPrefix
            + Self.allCases.map(\.rawValue).joined(separator: ", ") + "."))
    }
    self = value
  }
}

/// Only visual and image components take a visual. One on another component would otherwise
/// fail inside the visual's own fields, which says nothing about the real mistake.
func refuseStrayVisuals(_ value: Value, path: String) throws {
  switch value {
  case .array(let items):
    for (index, item) in items.enumerated() {
      try refuseStrayVisuals(item, path: path + "[\(index)]")
    }
  case .object(let fields):
    if let type = fields["type"]?.string, type != "visual", type != "image",
      let visual = fields["visual"], visual != .null
    {
      throw SevraError(
        "arguments",
        "\(path) is a \(type), which does not take a visual. Leave visual out.")
    }
    for key in fields.keys.sorted() where key != "visual" {
      try refuseStrayVisuals(fields[key]!, path: path.isEmpty ? key : path + "." + key)
    }
  default: break
  }
}
