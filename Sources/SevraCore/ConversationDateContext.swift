import Foundation

/// The local civil day at submission, retained with the original human text.
package struct ConversationDateContext: Codable, Equatable, Sendable {
  let instant: String
  let locale: String
  let calendar: String
  let timeZone: String
  let today: String
  let yesterday: String
  let tomorrow: String

  package init(now: Date = Date(), calendar local: Calendar = .current, locale: Locale = .current) {
    instant = now.ISO8601Format()
    self.locale = locale.identifier
    calendar = String(describing: local.identifier)
    timeZone = local.timeZone.identifier
    let day = Date.ISO8601FormatStyle(timeZone: local.timeZone).year().month().day()
      .dateSeparator(.dash)
    today = now.formatted(day)
    yesterday = local.date(byAdding: .day, value: -1, to: now)?.formatted(day) ?? today
    tomorrow = local.date(byAdding: .day, value: 1, to: now)?.formatted(day) ?? today
  }

  func resolveDay(_ literal: String) -> String {
    switch literal.lowercased() {
    case "today": today
    case "yesterday": yesterday
    case "tomorrow": tomorrow
    default: literal
    }
  }

  /// The Mac's local date, weekday, time and time zone in one short line, for every chat
  /// request, so "overdue", "this month" or "every Monday" need no guess.
  package static func nowLine(
    _ now: Date = Date(), calendar local: Calendar = .current
  ) -> String {
    let format = DateFormatter()
    format.calendar = Calendar(identifier: .gregorian)
    format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = local.timeZone
    format.dateFormat = "EEEE yyyy-MM-dd HH:mm"
    return "Now: " + format.string(from: now) + ", time zone " + local.timeZone.identifier + "."
  }
}
