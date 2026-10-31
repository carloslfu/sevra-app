import Foundation

enum DisplayText {
  static func date(_ value: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
  }
  /// A time in a recording, as a player shows it.
  static func clock(_ seconds: Double) -> String? {
    guard seconds.isFinite, seconds >= 0, seconds < 1e9 else { return nil }
    let whole = Int(seconds)
    let hours = whole / 3600
    return hours == 0
      ? String(format: "%d:%02d", whole / 60, whole % 60)
      : String(format: "%d:%02d:%02d", hours, whole / 60 % 60, whole % 60)
  }
  static func location(_ value: String) -> String? {
    let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    func field(_ name: String) -> String? {
      parts.first(where: { $0.hasPrefix(name + "=") }).map { String($0.dropFirst(name.count + 1)) }
    }
    if let page = field("page") { return "Page " + page }
    if let sheet = field("sheet") {
      return sheet + (field("row").map { " · Row " + $0 } ?? "")
    }
    if let time = field("time"), let seconds = Double(time), let shown = clock(seconds) {
      return shown
    }
    if parts.first == "image" { return "Image text" }
    return nil
  }
}
