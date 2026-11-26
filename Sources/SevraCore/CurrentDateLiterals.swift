import Foundation

/// A view's query and a saved tool run again on later days. A model asked for rows past their
/// date often writes today out, `due < '2026-11-26'`, and the view goes stale the next day.
/// Before such SQL is saved, a quoted value that is exactly today, or now to the minute, and
/// that a comparison reads, becomes the sql function that means it: date('now'),
/// datetime('now') or a strftime of 'now' in the same shape. Every other date is data and
/// stays, and so does a value that is written rather than compared, such as SET or VALUES.
/// The chat sql date functions read 'now' as the Mac's local time, so the result is the same
/// value today and the current one after.
public enum CurrentDateLiterals {
  /// The line a save's result adds when it rewrote something, naming what it wrote.
  public static func notice(_ written: [String]) -> String {
    var seen = Set<String>()
    let names = written.filter { seen.insert($0).inserted }
    let dateOnly = names.allSatisfy { ["date('now')", "'now'"].contains($0) }
    return "Wrote " + names.joined(separator: " and ")
      + (dateOnly ? " for today's date" : " for the current date and time")
      + " so it stays current."
  }

  /// The text with today's and now's compared literals rewritten, and whether any was.
  /// `now` is the moments that count as now: the request's start and the save, so a value
  /// copied from the request's Now line still matches minutes later.
  public static func rewrite(
    _ sql: String, now: [Date], timeZone: TimeZone = .current
  ) -> (text: String, written: [String]) {
    guard !now.isEmpty, sql.contains("'") else { return (sql, []) }
    let format = DateFormatter()
    format.calendar = Calendar(identifier: .gregorian)
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = timeZone
    func formatted(_ pattern: String, _ dates: [Date]) -> Set<String> {
      format.dateFormat = pattern
      return Set(dates.map { format.string(from: $0) })
    }
    // Every minute from the earliest moment to the latest, at most a day of them.
    let start = now.min()!
    let end = now.max()!
    var minutesSeen: [Date] = []
    var moment = start
    while moment <= end, minutesSeen.count < 1_440 {
      minutesSeen.append(moment)
      moment += 60
    }
    minutesSeen.append(end)
    let days = formatted("yyyy-MM-dd", now)
    let months = formatted("yyyy-MM", now)
    let minutes = formatted("yyyy-MM-dd HH:mm", minutesSeen)
    let times = formatted("HH:mm", minutesSeen)

    let pieces = SQLScratch.pieces(sql)
    // Code as it reads around each piece: other values and names blanked to one token.
    let masked = pieces.map { $0.code ? $0.text : " _ " }
    let monthFormat = pieces.contains { !$0.code && $0.text == "'%Y-%m'" }
    let comparison = #"(?:<=|>=|<>|!=|==|<|>|=|\bBETWEEN|\bIS(?:\s+NOT)?|\bBETWEEN\s+\S+\s+AND)\s*$"#
    var written: [String] = []
    var output = ""
    for (index, piece) in pieces.enumerated() {
      guard !piece.code, piece.text.count >= 2, piece.text.hasPrefix("'"), piece.text.hasSuffix("'")
      else {
        output += piece.text
        continue
      }
      let value = String(piece.text.dropFirst().dropLast())
      let before = masked[..<index].joined()
      let after = masked[(index + 1)...].joined()
      // A value a SET writes is data even though an = comes before it.
      if let set = before.range(of: #"\bSET\b"#, options: [.regularExpression, .caseInsensitive, .backwards]),
        before.range(of: #"\bWHERE\b"#, options: [.regularExpression, .caseInsensitive, .backwards])
          .map({ $0.lowerBound < set.lowerBound }) ?? true
      {
        output += piece.text
        continue
      }
      let compared =
        before.range(of: comparison, options: [.regularExpression, .caseInsensitive]) != nil
        || after.range(
          of: #"^\s*(?:<=|>=|<>|!=|==|<|>|=|NOT\s+BETWEEN\b|BETWEEN\b)"#,
          options: [.regularExpression, .caseInsensitive]) != nil
      // date('2026-11-26', '+7 days') compared: the first argument is the moment, so it is 'now'.
      let dateArgument =
        before.range(
          of: #"(?:<=|>=|<>|!=|==|<|>|=|\bBETWEEN|\bBETWEEN\s+\S+\s+AND)\s*(?:date|datetime|julianday)\s*\(\s*$"#,
          options: [.regularExpression, .caseInsensitive]) != nil
      var replacement: String?
      let minute = String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
      if dateArgument, days.contains(value) || (value.count >= 16 && minutes.contains(minute)) {
        replacement = "'now'"
      } else if compared {
        replacement = function(for: value, days: days, months: months, minutes: minutes, times: times,
          monthFormat: monthFormat)
      }
      if let replacement {
        output += replacement
        written.append(replacement)
      } else {
        output += piece.text
      }
    }
    return written.isEmpty ? (sql, []) : (output, written)
  }

  /// The function that writes `value` for now, when `value` is today, this month or this minute.
  private static func function(
    for value: String, days: Set<String>, months: Set<String>, minutes: Set<String>,
    times: Set<String>, monthFormat: Bool
  ) -> String? {
    func matches(_ pattern: String) -> Bool {
      value.range(of: pattern, options: .regularExpression) != nil
    }
    if matches(#"^\d{4}-\d{2}-\d{2}$"#) {
      return days.contains(value) ? "date('now')" : nil
    }
    if matches(#"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$"#) {
      let separator = value.dropFirst(10).prefix(1)
      let minute = value.prefix(10) + " " + value.dropFirst(11).prefix(5)
      guard minutes.contains(String(minute)) else { return nil }
      if value.count == 19 && separator == " " { return "datetime('now')" }
      return "strftime('%Y-%m-%d" + separator + "%H:%M" + (value.count == 19 ? ":%S" : "")
        + "','now')"
    }
    if matches(#"^\d{2}:\d{2}(:\d{2})?$"#) {
      guard times.contains(String(value.prefix(5))) else { return nil }
      return value.count == 8 ? "time('now')" : "strftime('%H:%M','now')"
    }
    if monthFormat, matches(#"^\d{4}-\d{2}$"#), months.contains(value) {
      return "strftime('%Y-%m','now')"
    }
    return nil
  }

  /// A view definition's component queries, children included, rewritten. What was written.
  public static func rewrite(_ components: inout [Component], now: [Date]) -> [String] {
    var written: [String] = []
    for index in components.indices {
      if let query = components[index].query {
        let rewritten = rewrite(query, now: now)
        if !rewritten.written.isEmpty {
          components[index].query = rewritten.text
          written += rewritten.written
        }
      }
      if var children = components[index].children {
        let inner = rewrite(&children, now: now)
        if !inner.isEmpty {
          components[index].children = children
          written += inner
        }
      }
    }
    return written
  }
}
