import Darwin
import Foundation

extension Workbook {
  /// Publish a complete pre-rendered small result at a user-owned destination.
  /// Rename with exclusive admission keeps an existing file intact across races.
  @discardableResult public func publishSmallExport(
    _ data: Data, to destination: URL, cancellation: Cancellation = .init()
  ) throws -> URL {
    try require(data.count <= 32 * 1024 * 1024, "export_size", "This export exceeds 32 MiB.")
    try cancellation.check()
    let target = try assetCopyDestination(destination)
    let parent = target.deletingLastPathComponent()
    let temporary = parent.appendingPathComponent(".sevra-export-" + identifier())
    let descriptor = Darwin.open(
      temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer {
      try? handle.close()
      try? FileManager.default.removeItem(at: temporary)
    }
    try handle.write(contentsOf: data)
    try require(Self.flush(descriptor), "export_write", "Could not persist this export.")
    try handle.close()
    try cancellation.check()
    try require(
      try assetCopyDestination(target) == target, "path", "The destination folder changed.")
    if renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) != 0 {
      let code = errno
      if code == EEXIST { throw SevraError("file_exists", "Choose a new filename for the export.") }
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }
    Self.flush(parent)
    return target
  }

  public func promoteConversationVisual(
    _ messageID: String, index: Int, conversation: String, expectedVersion: Int,
    token: String = identifier()
  ) throws -> Space {
    let capture = try conversationVisual(messageID, index: index, conversation: conversation)
    try require(
      capture.appReference == nil, "app_permission",
      "Open the enabled app view and pin it with its existing access.")
    return try addVisualToHome(
      capture.definition, title: nil, expectedVersion: expectedVersion, token: token,
      origin: VisualOrigin(messageID: messageID, index: index, conversation: conversation))
  }

  func addVisualToHome(
    _ visual: VisualDefinition, title: String?, expectedVersion: Int, token: String,
    origin: VisualOrigin? = nil
  ) throws -> Space {
    let name: String
    if let title = title ?? visual.title {
      name = title
    } else if let image = visual.image {
      name = try item(image.reference.sourceID).title
    } else {
      throw SevraError("visual", "Choose a supported visual to add to Home.")
    }
    let component = Component(
      id: "visual-" + token, type: visual.kind == .image ? "image" : "visual", title: name,
      visual: visual, visualOrigin: origin)
    return try editSpace(
      "home", expectedVersion: expectedVersion,
      edits: [.init(operation: "insert", at: "last", component: component)], token: token)
  }

  public func conversationVisual(
    _ messageID: String, index: Int, conversation: String
  ) throws -> VisualResult {
    try require(
      (0...1).contains(index), "visual_capture", "Choose an exact visual within this message.")
    return try synchronized {
      let message = try historyMessage(messageID, conversation: conversation)
      let payload = try messagePayload(messageID, conversation: conversation)
      let visual = payload["visuals"].array
      try require(
        ["assistant", "event"].contains(message.role) && message.state == "complete"
          && (payload["tool"] == .string("finish")
            || payload["kind"] == .string("conversation_attachment"))
          && visual.indices.contains(index),
        "visual_capture", "This message does not contain a published visual.")
      let result = try JSONDecoder().decode(
        VisualResult.self, from: Data(visual[index].json().utf8))
      try result.validate()
      return result
    }
  }
}

extension VisualChartData {
  /// Exact data, tied to the captured query and data identity. Values that
  /// may be interpreted as formulas by spreadsheet clients remain text.
  public func csv(_ chart: VisualChart) -> Data {
    func field(_ input: String, numeric: Bool = false) -> String {
      let first = input.drop(while: { $0.isWhitespace }).first
      let value = !numeric && (first.map { "=+-@".contains($0) } ?? false) ? "'" + input : input
      return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    var rows = [
      [
        field(chart.x), field(chart.y), field(chart.series ?? "series"), field("unit"),
        field("source versions"),
        field("capture snapshot"), field("query hash"), field("capture revision"),
        field("source scope"),
        field("filters"), field("period start"), field("period end (exclusive)"),
        field("observed through (exclusive)"), field("missing value count"),
        field("source manifest"),
      ].joined(separator: ",")
    ]
    rows += points.map { point in
      let period = [chart.periods?.current, chart.periods?.baseline].compactMap { $0 }
        .first { $0.key == point.label }
      return [
        field(point.label, numeric: chart.style == .scatter),
        field(point.amount, numeric: !isTextValue), field(point.series ?? ""), field(unit ?? ""),
        field(point.sourceIDs.joined(separator: " ")),
        field(snapshot), field(queryHash), field(revision.map(String.init) ?? "", numeric: true),
        field((try? scope.json()) ?? ""), field((try? chart.query["filters"].json()) ?? ""),
        field(period?.start ?? ""), field(period?.end ?? ""), field(period?.observedThrough ?? ""),
        field(String(unknown), numeric: true), field(manifestID ?? ""),
      ].joined(separator: ",")
    }
    return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
  }
}
