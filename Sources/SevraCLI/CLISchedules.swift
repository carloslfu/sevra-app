import Foundation
import SevraCore

extension CLI {
  static func runSchedulePreview(_ args: [String], cancellation: Cancellation) throws -> Value {
    try require(
      (3...5).contains(args.count), "usage",
      "schedule-preview SCHEDULE_JSON_OR_@FILE AFTER_ISO [COUNT] [HORIZON_DAYS]")
    let raw: String
    if args[1].hasPrefix("@") {
      let path = String(args[1].dropFirst())
      try require(!path.isEmpty, "schedule", "Choose a schedule JSON file.")
      let url = URL(fileURLWithPath: path)
      let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      try require(
        attributes.isRegularFile == true, "schedule", "Choose a regular schedule JSON file.")
      try require(
        (attributes.fileSize ?? Int.max) <= 65_536, "schedule_limit",
        "Schedule input is limited to 64 KiB.")
      let file = try FileHandle(forReadingFrom: url)
      defer { try? file.close() }
      let data = try file.read(upToCount: 65_537) ?? Data()
      try require(data.count <= 65_536, "schedule_limit", "Schedule input is limited to 64 KiB.")
      guard let text = String(data: data, encoding: .utf8) else {
        throw SevraError("schedule", "Schedule input must be UTF-8 JSON.")
      }
      raw = text
    } else {
      raw = args[1]
      try require(
        raw.utf8.count <= 65_536, "schedule_limit", "Schedule input is limited to 64 KiB.")
    }
    let rule = try NativeCalendarSchedule(Value.parseExact(raw))
    return try rule.preview(
      after: scheduleInstant(args[2]), count: scheduleLimit(args, 3, default: 5),
      horizonDays: scheduleLimit(args, 4, default: 3660), cancellation: cancellation)
  }

  static func runAutomationPreview(
    _ args: [String], book: Workbook, cancellation: Cancellation
  ) throws -> Value {
    try require(
      (4...6).contains(args.count), "usage",
      "automation-preview WORKBOOK EXACT_DEFINITION_ID AFTER_ISO [COUNT] [HORIZON_DAYS]")
    return try book.previewAutomation(
      args[2], after: scheduleInstant(args[3]), count: scheduleLimit(args, 4, default: 5),
      horizonDays: scheduleLimit(args, 5, default: 3660), cancellation: cancellation)
  }

  static func scheduleInstant(_ raw: String) throws -> Date {
    try require(raw.contains("T"), "date", "Use a timestamp with seconds and an explicit zone.")
    let normalized = try BusinessTime.normalized(raw)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let after = formatter.date(from: normalized) else {
      throw SevraError("schedule_date", "The query timestamp could not be read.")
    }
    return after
  }

  static func scheduleLimit(_ args: [String], _ index: Int, default fallback: Int) throws -> Int {
    guard args.count > index else { return fallback }
    guard let value = Int(args[index]) else {
      throw SevraError("schedule_limit", "Use integer preview limits.")
    }
    return value
  }
}
