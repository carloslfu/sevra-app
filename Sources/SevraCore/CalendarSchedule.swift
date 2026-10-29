import Foundation

/// A native wall-clock rule. Validation and preview grant no execution authority.
public struct NativeCalendarSchedule: Equatable, Sendable {
  private enum Recurrence: Equatable, Sendable {
    case daily
    case weekly([Int])
    case monthly(Int?)
    case yearly(Int, Int)
  }

  public let timeZone: String
  public let hour: Int
  public let minute: Int
  private let recurrence: Recurrence

  public init(_ value: Value) throws {
    try require(
      Set(value.object.keys) == ["policy", "timeZone", "hour", "minute", "recurrence"]
        && value["policy"] == .string("native-calendar-v1"),
      "schedule", "Use a native-calendar-v1 schedule with its exact declared fields.")
    guard let zone = value["timeZone"].string,
      zone == "UTC" || (zone.contains("/") && TimeZone.knownTimeZoneIdentifiers.contains(zone)),
      TimeZone(identifier: zone) != nil
    else { throw SevraError("schedule_zone", "Choose an explicit named IANA time zone or UTC.") }
    timeZone = zone
    hour = try Self.integer(value["hour"], range: 0...23)
    minute = try Self.integer(value["minute"], range: 0...59)
    let rule = value["recurrence"]
    switch rule["kind"] {
    case .string("daily"):
      try Self.fields(rule, ["kind"])
      recurrence = .daily
    case .string("weekly"):
      try Self.fields(rule, ["kind", "weekdays"])
      guard case .array(let weekdays) = rule["weekdays"], (1...7).contains(weekdays.count) else {
        throw SevraError("schedule", "Choose one to seven distinct ISO weekdays.")
      }
      let days = try weekdays.map { try Self.integer($0, range: 1...7) }
      try require(Set(days).count == days.count, "schedule", "Choose distinct ISO weekdays.")
      recurrence = .weekly(days.sorted())
    case .string("monthly"):
      try Self.fields(rule, ["kind", "day"])
      recurrence = .monthly(
        rule["day"] == .string("last") ? nil : try Self.integer(rule["day"], range: 1...31))
    case .string("yearly"):
      try Self.fields(rule, ["kind", "month", "day"])
      let month = try Self.integer(rule["month"], range: 1...12)
      let day = try Self.integer(rule["day"], range: 1...31)
      // Leap year validates February 29 without normalizing invalid month/day pairs.
      try require(
        DateComponents(year: 2000, month: month, day: day).isValidDate(
          in: Calendar(identifier: .gregorian)),
        "schedule", "Choose a valid month and day; February 29 is allowed.")
      recurrence = .yearly(month, day)
    default: throw SevraError("schedule", "Choose daily, weekly, monthly or yearly recurrence.")
    }
  }

  public var definition: Value {
    let rule: Value
    switch recurrence {
    case .daily: rule = .object(["kind": .string("daily")])
    case .weekly(let days):
      rule = .object([
        "kind": .string("weekly"), "weekdays": .array(days.map { .number(Double($0)) }),
      ])
    case .monthly(let day):
      rule = .object([
        "kind": .string("monthly"), "day": day.map { .number(Double($0)) } ?? .string("last"),
      ])
    case .yearly(let month, let day):
      rule = .object([
        "kind": .string("yearly"), "month": .number(Double(month)), "day": .number(Double(day)),
      ])
    }
    return .object([
      "policy": .string("native-calendar-v1"), "timeZone": .string(timeZone),
      "hour": .number(Double(hour)), "minute": .number(Double(minute)), "recurrence": rule,
    ])
  }

  /// Each inspected civil date has at most one slot. Horizon exhaustion is explicit.
  public func preview(
    after: Date, count: Int = 5, horizonDays: Int = 3660,
    cancellation: Cancellation = .init()
  ) throws -> Value {
    try cancellation.check()
    try require(
      (1...100).contains(count) && (1...3660).contains(horizonDays), "schedule_limit",
      "Preview 1 to 100 occurrences within 1 to 3660 local calendar days.")
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(identifier: timeZone)!
    try Self.validate(after, calendar: calendar)
    guard var day = calendar.dateInterval(of: .day, for: after)?.start else {
      throw SevraError("schedule_date", "The query has no supported calendar day.")
    }
    let startDate = Self.civilDate(day, calendar: calendar)
    var inspected = 0
    var occurrences: [Value] = []
    while inspected < horizonDays && occurrences.count < count {
      try cancellation.check()
      try Self.validate(day, calendar: calendar)
      guard let interval = calendar.dateInterval(of: .day, for: day), interval.end > day else {
        throw SevraError("schedule_date", "The calendar cannot advance to another local day.")
      }
      inspected += 1
      if matches(day, calendar: calendar),
        let candidate = try resolve(interval, calendar: calendar, cancellation: cancellation),
        candidate > after
      {
        let components = calendar.dateComponents([.hour, .minute, .second], from: candidate)
        let localDate = Self.civilDate(day, calendar: calendar)
        occurrences.append(
          .object([
            "slotKey": .string(localDate), "localDate": .string(localDate),
            "due": .string(Self.instant(candidate)), "timeZone": .string(timeZone),
            "requestedLocalTime": .string(String(format: "%02d:%02d:00", hour, minute)),
            "actualLocalTime": .string(
              String(
                format: "%02d:%02d:%02d", components.hour!, components.minute!, components.second!)),
            "shifted": .bool(
              components.hour != hour || components.minute != minute || components.second != 0),
          ]))
      }
      day = interval.end
    }
    try cancellation.check()
    return .object([
      "scope": .string("schedule-preview-only"), "execution": .string("none"),
      "schedule": definition, "after": .string(Self.instant(after)),
      "occurrences": .array(occurrences), "requestedCount": .number(Double(count)),
      "countReached": .bool(occurrences.count == count),
      "stopReason": .string(occurrences.count == count ? "count" : "horizon"),
      "examinedDays": .number(Double(inspected)), "firstLocalDate": .string(startDate),
      "scannedThroughExclusive": .string(Self.instant(day)),
    ])
  }

  private func resolve(
    _ interval: DateInterval, calendar: Calendar, cancellation: Cancellation
  ) throws -> Date? {
    try require(
      interval.duration > 0 && interval.duration <= 172_800, "schedule_date",
      "The local day exceeds the supported 48-hour resolution bound.")
    let requested = hour * 3600 + minute * 60
    func clock(_ date: Date) -> Int {
      let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
      return parts.hour! * 3600 + parts.minute! * 60 + parts.second!
    }
    // Scan chronologically, so a fold can never select its second instance.
    // Resolve the first crossing to whole seconds, including historic subminute gaps.
    // Calendar.nextDate(.nextTime) skips Lord Howe's half-hour gap on qualified macOS.
    var lower = interval.start
    if clock(lower) >= requested { return lower }
    while lower < interval.end {
      try cancellation.check()
      let upper = min(lower.addingTimeInterval(60), interval.end)
      let last = upper < interval.end ? upper : upper.addingTimeInterval(-1)
      if last > lower
        && (clock(last) >= requested
          || calendar.timeZone.secondsFromGMT(for: lower)
            != calendar.timeZone.secondsFromGMT(for: last))
      {
        var candidate = lower.addingTimeInterval(1)
        while candidate <= last {
          try cancellation.check()
          if clock(candidate) >= requested { return candidate }
          candidate = candidate.addingTimeInterval(1)
        }
      }
      lower = upper
    }
    return nil
  }

  private func matches(_ day: Date, calendar: Calendar) -> Bool {
    let parts = calendar.dateComponents([.weekday, .month, .day], from: day)
    switch recurrence {
    case .daily: return true
    case .weekly(let days): return days.contains((parts.weekday! + 5) % 7 + 1)
    case .monthly(let chosen):
      return parts.day == (chosen ?? calendar.range(of: .day, in: .month, for: day)!.count)
    case .yearly(let month, let chosen): return parts.month == month && parts.day == chosen
    }
  }

  private static func integer(_ value: Value, range: ClosedRange<Int>) throws -> Int {
    guard case .number(let number) = value, number.isFinite, number.rounded() == number,
      number >= Double(range.lowerBound), number <= Double(range.upperBound)
    else { throw SevraError("schedule", "Use an integer within the declared schedule range.") }
    return Int(number)
  }

  private static func fields(_ value: Value, _ fields: Set<String>) throws {
    try require(
      Set(value.object.keys) == fields, "schedule", "Use only the declared recurrence fields.")
  }

  private static func validate(_ date: Date, calendar: Calendar) throws {
    try require(
      date.timeIntervalSince1970.isFinite, "schedule_date", "Use a finite calendar instant.")
    let parts = calendar.dateComponents([.era, .year], from: date)
    try require(
      parts.era == 1 && (1...9998).contains(parts.year ?? 0), "schedule_date",
      "Use Gregorian calendar years 1 through 9998.")
  }

  private static func civilDate(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }

  private static func instant(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
  }
}
