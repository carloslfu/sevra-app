import Darwin
import Foundation
import SevraCore

extension CLI {
  static func runConditionPreview(_ args: [String], cancellation: Cancellation) throws -> Value {
    try require(
      args.count == 3, "usage",
      "condition-preview RULE_JSON_OR_@FILE OBSERVATIONS_JSON_OR_@FILE")
    let rule = try NativeConditionRule(conditionJSON(args[1]))
    return try rule.preview(conditionJSON(args[2]), cancellation: cancellation)
  }

  private static func conditionJSON(_ argument: String) throws -> Value {
    let text: String
    if argument.hasPrefix("@") {
      let path = String(argument.dropFirst())
      try require(!path.isEmpty, "condition", "Choose a condition JSON file.")
      let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
      try require(descriptor >= 0, "condition_file", "Cannot open a regular condition JSON file.")
      let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      defer { try? file.close() }
      var info = stat()
      try require(
        fstat(descriptor, &info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
        "condition_file", "Choose a regular file without symbolic links.")
      try require(
        info.st_size <= 65_536, "condition_limit", "Condition JSON input is limited to 64 KiB.")
      let data = try file.read(upToCount: 65_537) ?? Data()
      try require(
        data.count <= 65_536, "condition_limit", "Condition JSON input is limited to 64 KiB.")
      guard let utf8 = String(data: data, encoding: .utf8) else {
        throw SevraError("condition", "Condition input must be UTF-8 JSON.")
      }
      text = utf8
    } else {
      try require(
        argument.utf8.count <= 65_536, "condition_limit",
        "Condition JSON input is limited to 64 KiB.")
      text = argument
    }
    return try Value.parse(text)
  }
}
