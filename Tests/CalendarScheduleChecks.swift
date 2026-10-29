import Foundation
import SevraCore

func checkCalendarSchedules() {
  func date(_ text: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    guard let value = formatter.date(from: text) else { throw SevraError("test", text) }
    return value
  }
  func definition(
    zone: String = "UTC", hour: Int = 9, minute: Int = 0,
    recurrence: Value = .object(["kind": .string("daily")])
  ) -> Value {
    .object([
      "policy": .string("native-calendar-v1"), "timeZone": .string(zone),
      "hour": .number(Double(hour)), "minute": .number(Double(minute)), "recurrence": recurrence,
    ])
  }
  func preview(
    _ value: Value, after: String, count: Int = 3, days: Int = 3660
  ) throws -> Value {
    try NativeCalendarSchedule(value).preview(after: date(after), count: count, horizonDays: days)
  }
  func dates(_ value: Value) -> [String] { value["occurrences"].array.map { $0["localDate"].text } }
  func instants(_ value: Value) -> [String] { value["occurrences"].array.map { $0["due"].text } }

  check("calendar schedules validate exact fields and canonical distinct ISO weekdays") {
    let weekly: Value = .object([
      "kind": .string("weekly"), "weekdays": .array([.number(7), .number(1), .number(3)]),
    ])
    let valid = definition(zone: "America/Bogota", recurrence: weekly)
    let normalized = try NativeCalendarSchedule(valid).definition
    try expect(
      normalized["recurrence"]["weekdays"] == .array([.number(1), .number(3), .number(7)]))
    try expect(try NativeCalendarSchedule(normalized).definition == normalized)
    for (key, value) in [
      ("hour", Value.number(1.5)), ("hour", .number(24)), ("minute", .number(-1)),
      ("minute", .string("0")), ("policy", .string("rfc5545")), ("surprise", .bool(true)),
    ] {
      var invalid = valid.object
      invalid[key] = value
      try refuses("schedule") { _ = try NativeCalendarSchedule(.object(invalid)) }
    }
    for zone in ["PST", "local", "America/Nonexistent", "", "UTC+5"] {
      try refuses("schedule_zone") { _ = try NativeCalendarSchedule(definition(zone: zone)) }
    }
    let invalidRules: [Value] = [
      .object(["kind": .string("daily"), "interval": .number(2)]),
      .object(["kind": .string("weekly"), "weekdays": .array([])]),
      .object(["kind": .string("weekly"), "weekdays": .array([.number(1), .number(1)])]),
      .object(["kind": .string("weekly"), "weekdays": .array([.number(0)])]),
      .object(["kind": .string("monthly"), "day": .string("31")]),
      .object(["kind": .string("monthly"), "day": .number(32)]),
      .object(["kind": .string("yearly"), "month": .number(2), "day": .number(30)]),
      .object(["kind": .string("yearly"), "month": .number(4), "day": .number(31)]),
      .object(["kind": .string("interval"), "seconds": .number(86400)]), .null,
    ]
    for invalid in invalidRules {
      try refuses("schedule") { _ = try NativeCalendarSchedule(definition(recurrence: invalid)) }
    }
  }
  check("calendar preview uses explicit zone and a strict after boundary") {
    let value = try preview(
      definition(zone: "America/Bogota"), after: "2026-10-29T14:00:00Z", count: 2)
    try expect(dates(value) == ["2026-10-30", "2026-10-31"])
    try expect(instants(value) == ["2026-10-30T14:00:00.000Z", "2026-10-31T14:00:00.000Z"])
    try expect(value["scope"].text == "schedule-preview-only" && value["execution"].text == "none")
    try expect(value["countReached"] == .bool(true) && value["stopReason"].text == "count")
    try expect(value["occurrences"].array.allSatisfy { $0["shifted"] == .bool(false) })
    let before = try preview(definition(hour: 0), after: "2026-10-29T23:59:59Z", count: 1)
    try expect(instants(before) == ["2026-10-30T00:00:00.000Z"])
  }
  check("weekly calendar keeps ISO weekdays across a year boundary") {
    let rule = definition(
      recurrence: .object([
        "kind": .string("weekly"), "weekdays": .array([.number(1), .number(7)]),
      ]))
    try expect(
      dates(preview(rule, after: "2026-12-31T00:00:00Z"))
        == ["2027-01-03", "2027-01-04", "2027-01-10"])
  }
  check("nonexistent wall time shifts to the first valid time rather than preserving minutes") {
    let value = try preview(
      definition(zone: "America/New_York", hour: 2, minute: 37),
      after: "2026-03-07T12:00:00Z", count: 2)
    try expect(instants(value) == ["2026-03-08T07:00:00.000Z", "2026-03-09T06:37:00.000Z"])
    let first = value["occurrences"].array[0]
    try expect(first["requestedLocalTime"].text == "02:37:00")
    try expect(first["actualLocalTime"].text == "03:00:00" && first["shifted"] == .bool(true))
    try expect(value["occurrences"].array[1]["shifted"] == .bool(false))
  }
  check("repeated clock time runs only at its first instance even when queried between instances") {
    let rule = definition(zone: "America/New_York", hour: 1, minute: 30)
    let before = try preview(rule, after: "2026-11-01T04:00:00Z", count: 2)
    try expect(instants(before) == ["2026-11-01T05:30:00.000Z", "2026-11-02T06:30:00.000Z"])
    let between = try preview(rule, after: "2026-11-01T05:45:00Z", count: 1)
    try expect(instants(between) == ["2026-11-02T06:30:00.000Z"])
    let exact = try preview(rule, after: "2026-11-01T05:30:00Z", count: 1)
    try expect(instants(exact) == instants(between))
    try expect(before["occurrences"].array[0]["shifted"] == .bool(false))
  }
  check("half-hour DST transitions preserve native gap and first-fold policies") {
    let gap = try preview(
      definition(zone: "Australia/Lord_Howe", hour: 2, minute: 15),
      after: "2026-10-03T03:00:00Z", count: 1)
    try expect(instants(gap) == ["2026-10-03T15:30:00.000Z"])
    try expect(gap["occurrences"].array[0]["actualLocalTime"].text == "02:30:00")
    try expect(gap["occurrences"].array[0]["shifted"] == .bool(true))
    let foldRule = definition(zone: "Australia/Lord_Howe", hour: 1, minute: 45)
    let fold = try preview(foldRule, after: "2026-04-04T12:00:00Z", count: 1)
    try expect(instants(fold) == ["2026-04-04T14:45:00.000Z"])
    let between = try preview(foldRule, after: "2026-04-04T14:50:00Z", count: 1)
    try expect(dates(between) == ["2026-04-06"])
  }
  check("midnight gaps and skipped whole civil dates never invent another occurrence") {
    let midnight = try preview(
      definition(zone: "America/Sao_Paulo", hour: 0),
      after: "2018-11-03T04:00:00Z", count: 1)
    try expect(instants(midnight) == ["2018-11-04T03:00:00.000Z"])
    try expect(midnight["occurrences"].array[0]["actualLocalTime"].text == "01:00:00")
    let skipped = try preview(
      definition(zone: "Pacific/Apia"), after: "2011-12-29T00:00:00Z", count: 3)
    try expect(dates(skipped) == ["2011-12-29", "2011-12-31", "2012-01-01"])
    try expect(Set(skipped["occurrences"].array.map { $0["slotKey"].text }).count == 3)
  }
  check("monthly exact dates skip missing dates while last day remains explicit") {
    let exact = try preview(
      definition(recurrence: .object(["kind": .string("monthly"), "day": .number(31)])),
      after: "2026-01-31T10:00:00Z", count: 3)
    try expect(dates(exact) == ["2026-03-31", "2026-05-31", "2026-07-31"])
    let last = try preview(
      definition(recurrence: .object(["kind": .string("monthly"), "day": .string("last")])),
      after: "2028-01-31T10:00:00Z", count: 3)
    try expect(dates(last) == ["2028-02-29", "2028-03-31", "2028-04-30"])
  }
  check("historic subminute offsets resolve exact minutes and first valid seconds") {
    let shifted = try preview(
      definition(zone: "Africa/Monrovia", hour: 0, minute: 30),
      after: "1972-01-06T12:00:00Z", count: 1)
    try expect(
      instants(shifted) == ["1972-01-07T00:44:30.000Z"], try shifted.json())
    try expect(shifted["occurrences"].array[0]["actualLocalTime"].text == "00:44:30")
    let exact = try preview(
      definition(zone: "Africa/Monrovia", hour: 0, minute: 45),
      after: "1972-01-06T12:00:00Z", count: 1)
    try expect(instants(exact) == ["1972-01-07T00:45:00.000Z"])
    try expect(exact["occurrences"].array[0]["shifted"] == .bool(false))
  }
  check("whole-date repeats use the first slot and malformed native day boundaries refuse safely") {
    let rule = definition(zone: "Pacific/Kwajalein")
    let first = try preview(rule, after: "1969-09-29T18:00:00Z", count: 2)
    try expect(dates(first) == ["1969-09-30", "1969-10-01"])
    try expect(instants(first) == ["1969-09-29T22:00:00.000Z", "1969-10-01T21:00:00.000Z"])
    let between = try preview(rule, after: "1969-09-30T22:00:00Z", count: 1)
    try expect(dates(between) == ["1969-10-01"])
    // Some Foundation versions return a zero-length interval for Apia's 1892 repeat.
    // A valid first-only preview or an explicit date refusal is acceptable, never a loop.
    do {
      let historic = try preview(
        definition(zone: "Pacific/Apia"), after: "1892-07-03T18:00:00Z", count: 2)
      try expect(dates(historic) == ["1892-07-04", "1892-07-05"])
      try expect(historic["occurrences"].array[0]["due"].text == "1892-07-03T20:26:56.000Z")
    } catch let error as SevraError {
      try expect(error.code == "schedule_date", error.message)
    }
  }
  check("yearly February 29 respects leap years including the century exception") {
    let rule = definition(
      recurrence: .object(["kind": .string("yearly"), "month": .number(2), "day": .number(29)]))
    try expect(
      dates(preview(rule, after: "2096-03-01T00:00:00Z", count: 1)) == ["2104-02-29"])
    let bounded = try preview(rule, after: "2026-01-01T00:00:00Z", count: 1, days: 365)
    try expect(bounded["countReached"] == .bool(false) && bounded["stopReason"].text == "horizon")
    try expect(bounded["occurrences"].array.isEmpty && bounded["examinedDays"].int == 365)
    try expect(bounded["scannedThroughExclusive"].text == "2027-01-01T00:00:00.000Z")
  }
  check("calendar pagination stays strictly increasing through offset changes") {
    let rule = definition(zone: "America/New_York", hour: 1, minute: 30)
    let full = try preview(rule, after: "2026-10-30T00:00:00Z", count: 5)
    let first = try preview(rule, after: "2026-10-30T00:00:00Z", count: 2)
    let next = try preview(rule, after: "2026-10-31T05:30:00Z", count: 3)
    try expect(first["occurrences"].array + next["occurrences"].array == full["occurrences"].array)
    let due = instants(full)
    try expect(zip(due, due.dropFirst()).allSatisfy { $0 < $1 })
    let empty = try preview(rule, after: "2026-11-01T05:45:00Z", count: 1, days: 1)
    try expect(empty["occurrences"].array.isEmpty && empty["countReached"] == .bool(false))
    try expect(empty["scannedThroughExclusive"].text == "2026-11-02T05:00:00.000Z")
  }
  check("calendar preview bounds invalid dates, request sizes, cancellation and deadlines") {
    let rule = try NativeCalendarSchedule(definition())
    let after = try date("2026-01-01T00:00:00Z")
    for count in [0, 101, Int.max] {
      try refuses("schedule_limit") { _ = try rule.preview(after: after, count: count) }
    }
    for horizon in [0, 3661, Int.max] {
      try refuses("schedule_limit") { _ = try rule.preview(after: after, horizonDays: horizon) }
    }
    for invalid in [Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: .nan)] {
      try refuses("schedule_date") { _ = try rule.preview(after: invalid) }
    }
    let cancelled = Cancellation()
    cancelled.cancel()
    try refuses("cancelled") { _ = try rule.preview(after: after, cancellation: cancelled) }
    try refuses("deadline") {
      _ = try rule.preview(after: after, cancellation: Cancellation(deadlineAfterSeconds: 0))
    }
  }
}
