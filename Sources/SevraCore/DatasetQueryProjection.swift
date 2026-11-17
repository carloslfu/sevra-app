import Foundation

struct QueryDomain {
  let first: Int
  let last: Int
  let excluded: [Int]

  init(_ value: Value) throws {
    let fields = try queryObject(value, keys: ["firstRow", "lastRow", "excludeRows"])
    func row(_ value: Value?) throws -> Int {
      guard let number = value?.int, value == .number(Double(number)),
        (1...1_048_576).contains(number)
      else { throw SevraError("query_domain", "Use an exact Excel row number.") }
      return number
    }
    first = try row(fields["firstRow"])
    last = try row(fields["lastRow"])
    if let raw = fields["excludeRows"] {
      guard case .array(let rows) = raw, rows.count <= 128 else {
        throw SevraError("query_domain", "List up to 128 inspected header or total rows.")
      }
      excluded = try rows.map { try row($0) }
    } else {
      excluded = []
    }
    try require(
      first <= last && Set(excluded).count == excluded.count,
      "query_domain", "Use an ordered Excel row range and distinct exclusions.")
  }
}

struct QueryProjection {
  let reference: QueryColumn
  let descriptor: Value
  let format: String
  let bucket: String?
  let zone: TimeZone?
  let bin: Decimal?
  let origin: Decimal
  var type: String {
    ["decimal", "en-US", "de-DE"].contains(format) ? "decimal" : "date"
  }

  init(_ value: Value) throws {
    let fields = try queryObject(
      value,
      keys: ["column", "format", "bucket", "timeZone", "binWidth", "binOrigin"])
    reference = try QueryColumn(fields["column"] ?? .null)
    guard let format = fields["format"]?.string,
      [
        "decimal", "en-US", "de-DE", "isoDate", "isoInstant", "mdy", "dmy", "excel1900",
        "excel1904",
      ].contains(format)
    else { throw SevraError("query_projection", "Declare a supported decimal or date format.") }
    self.format = format
    descriptor = value
    bucket = fields["bucket"]?.string
    zone = fields["timeZone"]?.string.flatMap(TimeZone.init(identifier:))
    try require(
      fields["bucket"] == nil
        || bucket.map { ["day", "week", "month", "year"].contains($0) } == true,
      "query_projection", "Use day, week, month or year for a Gregorian time bucket.")
    try require(
      fields["timeZone"] == nil || zone != nil, "query_projection", "Name a valid time zone.")
    func decimal(_ key: String) throws -> Decimal? {
      guard let raw = fields[key] else { return nil }
      guard let text = raw.string, text.utf8.count <= 128 else {
        throw SevraError("query_projection", "Bin boundaries must be exact decimal strings.")
      }
      return try Numbers.decimal(text)
    }
    bin = try decimal("binWidth")
    origin = try decimal("binOrigin") ?? 0
    try require(
      type == "decimal"
        ? bucket == nil && zone == nil && (bin.map { $0 > 0 } ?? (fields["binOrigin"] == nil))
        : bin == nil && fields["binOrigin"] == nil && (zone == nil || bucket != nil)
          && (bucket == nil || format != "isoInstant" || zone != nil),
      "query_projection",
      "Use positive decimal bins or declared time buckets with an instant time zone.")
  }

  func apply(_ input: String) throws -> String {
    try require(input.utf8.count <= 256, "query_projection", "A projected cell is too large.")
    if type == "decimal" {
      let text: String
      switch format {
      case "en-US", "de-DE":
        let grouping = format == "en-US" ? "," : "."
        let separator = format == "en-US" ? "." : ","
        let group = NSRegularExpression.escapedPattern(for: grouping)
        let dot = NSRegularExpression.escapedPattern(for: separator)
        let grammar = "^[+-]?(?:[0-9]+|[0-9]{1,3}(?:\(group)[0-9]{3})+)(?:\(dot)[0-9]+)?\\z"
        try require(
          input.range(of: grammar, options: .regularExpression) != nil,
          "query_projection", "A decimal cell does not match the declared locale.")
        text = input.replacingOccurrences(of: grouping, with: "")
          .replacingOccurrences(of: separator, with: ".")
      default: text = input
      }
      let number = try Numbers.decimal(text)
      guard let bin else { return Numbers.string(number) }
      let q = try Numbers.binary(Numbers.binary(number, origin, op: "-"), bin, op: "/")
      var quotient = q
      var index = Decimal()
      NSDecimalRound(&index, &quotient, 0, .down)
      var lower = try Numbers.binary(Numbers.binary(index, bin, op: "*"), origin, op: "+")
      // Division can round onto the next boundary at full Decimal precision.
      if lower > number { lower = try Numbers.binary(lower, bin, op: "-") }
      let upper = try Numbers.binary(lower, bin, op: "+")
      try require(
        lower <= number && number < upper, "query_projection",
        "This value is too close to a bin boundary at the available precision.")
      return Numbers.string(lower)
    }
    let source: String
    switch format {
    case "mdy", "dmy":
      let parts = input.split(separator: "/", omittingEmptySubsequences: false)
      try require(
        parts.count == 3 && parts[0].utf8.count == 2
          && parts[1].utf8.count == 2 && parts[2].utf8.count == 4,
        "query_projection", "Use the declared two-digit day/month and four-digit year.")
      source = "\(parts[2])-\(parts[format == "mdy" ? 0 : 1])-\(parts[format == "mdy" ? 1 : 0])"
    case "isoDate":
      try require(input.utf8.count == 10, "query_projection", "Use an ISO date without a time.")
      source = input
    case "isoInstant":
      try require(
        input.utf8.count > 10, "query_projection", "Use an ISO timestamp with a time zone.")
      source = input
    default:
      let serial = try Numbers.decimal(input)
      let number = NSDecimalNumber(decimal: serial).doubleValue
      guard let date = ExcelDate.serial(number, epoch1904: format == "excel1904") else {
        throw SevraError("query_projection", "This Excel serial has no Gregorian date.")
      }
      source = date.formatted(.iso8601)
    }
    let normalized = try BusinessTime.normalized(source)
    guard let bucket else { return normalized }
    guard let instant = VisualChartData.parseInstant(normalized) else {
      throw SevraError("query_projection", "This date cannot be bucketed.")
    }
    var calendar = Calendar(identifier: .gregorian)
    // Civil dates and Excel wall-clock values have no offset to convert.
    calendar.timeZone = (format == "isoInstant" ? zone : nil) ?? TimeZone(secondsFromGMT: 0)!
    calendar.firstWeekday = 2
    calendar.minimumDaysInFirstWeek = 4
    let component: Calendar.Component =
      switch bucket {
      case "week": .weekOfYear
      case "month": .month
      case "year": .year
      default: .day
      }
    guard let interval = calendar.dateInterval(of: component, for: instant) else {
      throw SevraError("query_projection", "This time bucket is outside the supported calendar.")
    }
    let date = calendar.dateComponents([.year, .month, .day], from: interval.start)
    return try BusinessTime.normalized(
      String(
        format: "%04d-%02d-%02d",
        date.year!, date.month!, date.day!))
  }
}
