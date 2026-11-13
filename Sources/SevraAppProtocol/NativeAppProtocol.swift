import Foundation
import SevraCore

@objc public protocol NativeAppWorkerProtocol {
  func exchange(_ request: Data, withReply reply: @escaping (Data) -> Void)
}
public enum NativeAppWire {
  public static let service = "com.sevra.workbooks.app-worker"
  /// Unapproved source is checked in a different OS process from user-enabled apps.
  public static let checkService = "com.sevra.workbooks.app-check-worker"
  public static let byteLimit = 2_097_152
  public static func decode(_ data: Data) throws -> Value {
    try require(data.count <= byteLimit, "app_protocol", "App message exceeds 2 MiB.")
    return try Value.parse(String(decoding: data, as: UTF8.self))
  }
  public static func encode(_ value: Value) throws -> Data {
    let data = Data(try value.json().utf8)
    try require(data.count <= byteLimit, "app_protocol", "App message exceeds 2 MiB.")
    return data
  }
}

public struct NativeAppNode: Equatable, Sendable {
  public let id: String
  public let type: String
  public let props: Value
  public let children: [String]
  public init(_ value: Value) throws {
    id = value["id"].text
    type = value["type"].text
    props = value["props"]
    children = value["children"].array.map(\.text)
    try require(
      !id.isEmpty && id.utf8.count <= 2048 && children.count <= 512
        && Set(children).count == children.count && props.json().utf8.count <= 262_144,
      "app_tree", "Invalid native node identity, children or properties.")
    try require(Self.types.contains(type), "app_tree", "Unsupported native component: " + type)
    let allowed = Self.common.union(Self.properties[type] ?? [])
    try require(
      Set(props.object.keys).isSubset(of: allowed), "app_tree",
      "Unknown property for " + type + ": "
        + Set(props.object.keys).subtracting(allowed).sorted().joined(separator: ", ")
        + ". Allowed properties: " + allowed.sorted().joined(separator: ", "))
    for key in [
      "width", "height", "gap", "padding", "min", "max", "columns", "size", "editRevision",
    ] {
      guard let raw = props.object[key], !(type == "table" && key == "columns") else { continue }
      guard case .number(let value) = raw, value.isFinite, abs(value) <= 100_000 else {
        throw SevraError("app_tree", "Native dimensions must be bounded numbers.")
      }
    }
    if ["slider", "progress"].contains(type), let raw = props.object["value"] {
      guard case .number(let value) = raw, value.isFinite, abs(value) <= 100_000 else {
        throw SevraError("app_tree", "Native numeric values must be bounded numbers.")
      }
    }
    for key in ["enabled", "hidden", "selectable", "vertical", "indeterminate", "descending"] {
      if let value = props.object[key], case .bool = value {
      } else if props.object[key] != nil {
        throw SevraError("app_tree", "Native flags must be booleans.")
      }
    }
    if type == "table" {
      for key in ["table", "search", "sort", "selection"] where props.object[key] != nil {
        try require(
          props[key].string != nil, "app_tree",
          "Table " + key + " must be a string, not a flag or object.")
      }
      if let columns = props.object["columns"] {
        guard case .array = columns, columns.array.allSatisfy({ $0.string != nil }) else {
          throw SevraError("app_tree", "Table columns must be an array of column ID strings.")
        }
      }
    }
    try require(
      props["options"].array.count <= 200 && props["titles"].array.count <= 50,
      "app_tree", "Too many native choices.")
    if type == "canvas" {
      try require(
        props["shapes"].array.count <= 2048 && props["regions"].array.count <= 128,
        "app_tree", "Canvas exceeds its shape or hit-region budget.")
      for shape in props["shapes"].array + props["regions"].array {
        for key in ["x", "y", "width", "height", "x2", "y2", "size"] {
          if let raw = shape.object[key] {
            guard case .number(let n) = raw, n.isFinite, abs(n) <= 100_000 else {
              throw SevraError("app_tree", "Canvas coordinates must be bounded numbers.")
            }
          }
        }
      }
    }
  }
  public static let types: Set<String> = [
    "column", "row", "grid", "split", "scroll", "section", "text", "button", "textField",
    "textEditor", "toggle", "picker", "slider", "date", "progress", "table", "tabs", "disclosure",
    "canvas", "image", "spacer",
  ]
  static let common: Set<String> = [
    "label", "help", "enabled", "hidden", "width", "height", "padding", "gap", "editRevision",
    "draftKey",
  ]
  static let properties: [String: Set<String>] = [
    "column": ["alignment"], "row": ["alignment"], "grid": ["columns"], "split": ["vertical"],
    "text": ["text", "size", "weight", "color", "selectable"],
    "button": ["title", "role"], "textField": ["value", "placeholder"], "textEditor": ["value"],
    "toggle": ["value", "title"], "picker": ["value", "options"],
    "slider": ["value", "min", "max"],
    "date": ["value"], "progress": ["value", "indeterminate"],
    "table": ["table", "search", "sort", "descending", "columns", "selection"],
    "tabs": ["titles", "value"],
    "disclosure": ["title", "value"], "canvas": ["shapes", "regions"], "image": ["symbol"],
  ]
}

/// Validate an entire batch before applying any view mutations. Retain the last valid tree on refusal.
public struct NativeAppTree: Sendable {
  public private(set) var nodes: [String: NativeAppNode] = [:]
  public private(set) var root: String?
  public init() {}
  public mutating func apply(_ frame: Value) throws -> Set<String> {
    try require(
      frame["version"] == .number(1) && frame["patches"].array.count <= 1024
        && frame["messages"].array.count <= 128, "app_protocol", "Invalid app frame.")
    var candidate = nodes
    var changed = Set<String>()
    for patch in frame["patches"].array {
      switch patch["op"].text {
      case "put":
        let node = try NativeAppNode(patch["node"])
        candidate[node.id] = node
        changed.insert(node.id)
      case "remove":
        candidate.removeValue(forKey: patch["id"].text)
        changed.insert(patch["id"].text)
      default: throw SevraError("app_tree", "Unknown tree operation.")
      }
    }
    try require(candidate.count <= 512, "app_tree", "App has more than 512 mounted controls.")
    let root = frame["root"].string
    if let root {
      var seen = Set<String>()
      func walk(_ id: String, depth: Int) throws {
        guard let node = candidate[id], depth <= 24, seen.insert(id).inserted else {
          throw SevraError("app_tree", "The native tree is cyclic, shared or incomplete.")
        }
        if !["column", "row", "grid", "split", "scroll", "section", "tabs", "disclosure"].contains(
          node.type)
        {
          try require(node.children.isEmpty, "app_tree", "This control cannot contain children.")
        }
        for child in node.children { try walk(child, depth: depth + 1) }
      }
      try walk(root, depth: 0)
      try require(seen.count == candidate.count, "app_tree", "The app has unreachable controls.")
    } else {
      try require(candidate.isEmpty, "app_tree", "An app needs a root control.")
    }
    nodes = candidate
    self.root = root
    return changed
  }
}
