import Foundation

enum DisplayText {
  static func date(_ value: String) -> String {
    guard let date = ISO8601DateFormatter().date(from: value) else { return value }
    return date.formatted(date: .abbreviated, time: .shortened)
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
    if let time = field("time"), let seconds = Double(time), seconds.isFinite, seconds >= 0,
      seconds < 1e9
    {
      let whole = Int(seconds)
      return String(format: "%d:%02d", whole / 60, whole % 60)
    }
    if parts.first == "image" { return "Image text" }
    return nil
  }
}
