import Foundation
import SevraCore

/// Presentation only. Labels never alter saved keys, values or identities.
public enum StructuredPresentation {
  public static func label(_ key: String) -> String {
    let known = [
      "id": "Identifier", "itemID": "Record", "datasetID": "Table", "assetID": "File",
      "receiptID": "Receipt", "runID": "Run", "sku": "SKU", "query": "Search",
      "hasMore": "More available", "nextOffset": "Next position", "unit_price": "Unit price",
    ]
    if let label = known[key] { return label }
    let separated = key.replacingOccurrences(
      of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression
    ).replacingOccurrences(of: "_", with: " ")
    return separated.prefix(1).uppercased() + separated.dropFirst()
  }

  public static func scalar(_ value: Value) -> String? {
    switch value {
    case .null: return "Not provided"
    case .bool(let yes): return yes ? "Yes" : "No"
    case .number(let number):
      let text = String(number)
      return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    case .string(let text): return text.isEmpty ? "Empty text" : text
    case .array, .object: return nil
    }
  }

  public static func embedded(_ value: Value) -> Value {
    guard case .string(let text) = value, text.utf8.count <= 1_000_000,
      let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first,
      first == "{" || first == "[", let parsed = parseJSON(text),
      parsed.object.count > 0 || parsed.array.count > 0 || parsed == .object([:])
        || parsed == .array([])
    else { return value }
    return parsed
  }

  /// Keep number spelling for display, including integers beyond Double's exact
  /// range. Validate first; this is not a replacement JSON grammar or stored data.
  public static func parseJSON(_ text: String) -> Value? {
    guard text.utf8.count <= 1_000_000, (try? Value.parse(text)) != nil else { return nil }
    let bytes = Array(text.utf8)
    var output: [UInt8] = []
    var index = 0
    var quoted = false
    var escaped = false
    while index < bytes.count {
      let byte = bytes[index]
      if quoted {
        output.append(byte)
        if escaped {
          escaped = false
        } else if byte == 92 {
          escaped = true
        } else if byte == 34 {
          quoted = false
        }
        index += 1
      } else if byte == 34 {
        quoted = true
        output.append(byte)
        index += 1
      } else if byte == 45 || (48...57).contains(byte) {
        let start = index
        while index < bytes.count,
          (48...57).contains(bytes[index]) || [43, 45, 46, 69, 101].contains(bytes[index])
        { index += 1 }
        output.append(34)
        output.append(contentsOf: bytes[start..<index])
        output.append(34)
      } else {
        output.append(byte)
        index += 1
      }
    }
    return try? JSONDecoder().decode(Value.self, from: Data(output))
  }

  public static func isIdentifier(_ key: String) -> Bool {
    key == "id" || key.hasSuffix("ID") || key.hasSuffix("_id")
      || ["hash", "resultHash", "operation_token", "call_id"].contains(key)
  }
}
