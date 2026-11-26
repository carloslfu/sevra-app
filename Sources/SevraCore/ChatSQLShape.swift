import Foundation

/// What sql reads from a table's declaration so the workbook table keeps it: defaults, the
/// numbering of an INTEGER PRIMARY KEY, required and unique columns, and computed columns.
extension SQLScratch {
  /// One column of a scratch table, as SQLite declares it.
  struct LayoutColumn {
    let name: String
    let type: String
    let notNull: Bool
    let defaultSQL: String?
    /// Its place in the primary key, from 1, or 0.
    let key: Int
    let generated: Bool
  }

  /// What a column of a new or altered table asks the workbook to keep.
  struct ColumnShape {
    var required = false
    var unique = false
    var autoNumber = false
    var initial: ColumnDefault?
    /// A computed column's SQL expression.
    var generated: String?
  }

  // MARK: Code and data in SQL text

  /// The statement cut into code and the parts SQLite reads as data or names: quoted values,
  /// quoted names and comments. A rewrite touches only the code.
  static func pieces(_ sql: String) -> [(text: String, code: Bool)] {
    var pieces: [(text: String, code: Bool)] = []
    var current = ""
    var code = true
    let characters = Array(sql)
    var index = 0
    func flush(_ next: Bool) {
      if !current.isEmpty { pieces.append((current, code)) }
      current = ""
      code = next
    }
    while index < characters.count {
      let character = characters[index]
      let next = index + 1 < characters.count ? characters[index + 1] : nil
      var close: String?
      if character == "'" || character == "\"" || character == "`" {
        close = String(character)
      } else if character == "[" {
        close = "]"
      } else if character == "-", next == "-" {
        close = "\n"
      } else if character == "/", next == "*" {
        close = "*/"
      }
      guard let close else {
        current.append(character)
        index += 1
        continue
      }
      flush(false)
      current.append(character)
      index += 1
      if close == "*/" {
        current.append("*")
        index += 1
      }
      while index < characters.count {
        current.append(characters[index])
        index += 1
        if current.count > 1 && current.hasSuffix(close) {
          // A doubled quote inside a quoted value or name is that quote, not its end.
          if close.count == 1, "'\"`".contains(close), index < characters.count,
            String(characters[index]) == close
          {
            current.append(characters[index])
            index += 1
            continue
          }
          break
        }
      }
      flush(true)
    }
    flush(true)
    return pieces
  }

  /// The statement with `body` applied to its code only.
  static func rewritingCode(_ sql: String, _ body: (String) -> String) -> String {
    pieces(sql).map { $0.code ? body($0.text) : $0.text }.joined()
  }

  /// AUTOINCREMENT numbers rows as an INTEGER PRIMARY KEY does here, so it is dropped. The
  /// current date and time keywords become the date functions, which read the Mac's local time.
  static func prepared(_ sql: String) -> String {
    rewritingCode(sql) { code in
      var code = code
      for (pattern, replacement) in [
        (#"\bAUTOINCREMENT\b"#, ""),
        (#"\bCURRENT_TIMESTAMP\b"#, "(datetime('now'))"),
        (#"\bCURRENT_DATE\b"#, "(date('now'))"),
        (#"\bCURRENT_TIME\b"#, "(time('now'))"),
      ] {
        code = code.replacingOccurrences(
          of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
      }
      return code
    }
  }

  // MARK: Column declarations

  /// The text of each column's declaration in a CREATE TABLE statement, by lower-case name.
  static func declarations(_ tableSQL: String) -> [String: String] {
    // The same text with data and names blanked, so brackets and commas are only code.
    var masked: [Character] = []
    for piece in pieces(tableSQL) {
      masked += piece.code ? Array(piece.text) : Array(repeating: "x", count: piece.text.count)
    }
    let original = Array(tableSQL)
    guard let open = masked.firstIndex(of: "(") else { return [:] }
    var parts: [Range<Int>] = []
    var depth = 0
    var start = open + 1
    for index in (open + 1)..<masked.count {
      switch masked[index] {
      case "(": depth += 1
      case ")":
        if depth == 0 {
          parts.append(start..<index)
          start = -1
        } else {
          depth -= 1
        }
      case "," where depth == 0:
        parts.append(start..<index)
        start = index + 1
      default: break
      }
      if start < 0 { break }
    }
    var found: [String: String] = [:]
    for part in parts {
      let text = String(original[part]).trimmingCharacters(in: .whitespacesAndNewlines)
      guard let name = leadingName(text) else { continue }
      if ["constraint", "primary", "unique", "check", "foreign"].contains(name.lowercased()),
        !"\"`[".contains(text.first!)
      {
        continue
      }
      found[name.lowercased()] = text
    }
    return found
  }

  /// The first name in a declaration, unquoted.
  static func leadingName(_ text: String) -> String? {
    guard let first = text.first else { return nil }
    let closing: Character? = first == "[" ? "]" : "\"`".contains(first) ? first : nil
    if let closing {
      var name = ""
      var index = text.index(after: text.startIndex)
      while index < text.endIndex {
        let character = text[index]
        index = text.index(after: index)
        if character == closing {
          if index < text.endIndex, text[index] == closing, closing != "]" {
            name.append(closing)
            index = text.index(after: index)
            continue
          }
          return name
        }
        name.append(character)
      }
      return nil
    }
    let name = text.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
    return name.isEmpty ? nil : String(name)
  }

  /// A computed column's expression: the text inside `AS (...)` of its declaration.
  static func generatedExpression(_ declaration: String) -> String? {
    var masked: [Character] = []
    for piece in pieces(declaration) {
      masked += piece.code ? Array(piece.text) : Array(repeating: "x", count: piece.text.count)
    }
    let original = Array(declaration)
    var depth = 0
    var index = 0
    while index < masked.count {
      let character = masked[index]
      if character == "(" { depth += 1 }
      if character == ")" { depth -= 1 }
      if depth == 0, index + 1 < masked.count,
        String(masked[index...index + 1]).uppercased() == "AS",
        index == 0 || !(masked[index - 1].isLetter || masked[index - 1].isNumber
          || masked[index - 1] == "_")
      {
        var open = index + 2
        while open < masked.count, masked[open].isWhitespace { open += 1 }
        if open < masked.count, masked[open] == "(" {
          var level = 0
          for close in open..<masked.count {
            if masked[close] == "(" { level += 1 }
            if masked[close] == ")" {
              level -= 1
              if level == 0 {
                return String(original[(open + 1)..<close]).trimmingCharacters(
                  in: .whitespacesAndNewlines)
              }
            }
          }
          return nil
        }
      }
      index += 1
    }
    return nil
  }

  /// A default as the workbook keeps it, from the text SQLite saved for it.
  static func columnDefault(_ sql: String, column: String) throws -> ColumnDefault? {
    var text = sql.trimmingCharacters(in: .whitespaces)
    while text.hasPrefix("("), text.hasSuffix(")") {
      text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }
    let compact = text.lowercased().filter { !$0.isWhitespace }
    if compact == "null" { return nil }
    for (clock, forms) in [
      ("date", ["date('now')", "date('now','localtime')", "strftime('%y-%m-%d','now')",
                "strftime('%y-%m-%d','now','localtime')", "current_date"]),
      ("datetime", ["datetime('now')", "datetime('now','localtime')",
                    "strftime('%y-%m-%d%h:%m:%s','now')", "strftime('%y-%m-%d%h:%m:%s','now','localtime')",
                    "current_timestamp"]),
      ("time", ["time('now')", "time('now','localtime')", "current_time"]),
    ] where forms.contains(compact) {
      return ColumnDefault(now: clock)
    }
    if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
      return ColumnDefault(
        value: String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'"))
    }
    if compact == "true" { return ColumnDefault(value: "1") }
    if compact == "false" { return ColumnDefault(value: "0") }
    if let number = try? Numbers.decimal(text) { return ColumnDefault(value: Numbers.string(number)) }
    throw SevraError(
      "sql_shape",
      "The default of \(column) is \(sql). A default is a fixed value, such as 'open' or 0, or the current date or time: CURRENT_DATE, CURRENT_TIMESTAMP or CURRENT_TIME. Nothing was changed."
    )
  }

  // MARK: Computed columns

  static let computedHelp =
    "A computed column calculates from this table's number columns with numbers, + - * /, comparisons, round, min, max, iif and parentheses, such as total REAL AS (quantity * price)."

  /// A computed column's SQL expression in the workbook's formula language, which names
  /// columns by id. `columns` holds each column's id by lower-case SQL name, and whether it
  /// holds numbers.
  static func formula(
    _ expression: String, column: String, columns: [String: (id: String, numeric: Bool)]
  ) throws -> String {
    func refuse(_ why: String) -> SevraError {
      SevraError(
        "sql_shape", "\(column) cannot be computed from \(expression): \(why). \(computedHelp) Nothing was changed.")
    }
    let characters = Array(expression)
    var output = ""
    var index = 0
    // Each open bracket: whether it is round's, and how many commas it has seen.
    var brackets: [(round: Bool, commas: Int)] = []
    var pendingRound = false
    while index < characters.count {
      let character = characters[index]
      let next = index + 1 < characters.count ? characters[index + 1] : nil
      if character.isWhitespace {
        index += 1
        continue
      }
      if character.isNumber || (character == "." && next?.isNumber == true) {
        var number = ""
        while index < characters.count, characters[index].isNumber || characters[index] == "." {
          number.append(characters[index])
          index += 1
        }
        output += number
        continue
      }
      if character.isLetter || character == "_" || "\"`[".contains(character) {
        var name = ""
        if "\"`[".contains(character) {
          let close: Character = character == "[" ? "]" : character
          index += 1
          while index < characters.count, characters[index] != close {
            name.append(characters[index])
            index += 1
          }
          guard index < characters.count else { throw refuse("a quoted name is not closed") }
          index += 1
        } else {
          while index < characters.count,
            characters[index].isLetter || characters[index].isNumber || characters[index] == "_"
          {
            name.append(characters[index])
            index += 1
          }
        }
        var after = index
        while after < characters.count, characters[after].isWhitespace { after += 1 }
        let call = after < characters.count && characters[after] == "(" && !"\"`[".contains(character)
        if call {
          switch name.lowercased() {
          case "round":
            output += "ROUND"
            pendingRound = true
          case "min": output += "MIN"
          case "max": output += "MAX"
          case "iif": output += "IF"
          default: throw refuse("\(name) is not one of the functions it can use")
          }
          continue
        }
        guard let target = columns[name.lowercased()] else {
          throw refuse(
            "\(name) is not a column of this table"
              + (["case", "when", "and", "or", "not", "null", "is", "like", "in", "between"]
                .contains(name.lowercased()) ? ", and \(name.uppercased()) is not available" : ""))
        }
        guard target.numeric else { throw refuse("\(name) holds text") }
        let plain = target.id.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
        output += plain ? target.id : "[" + target.id + "]"
        continue
      }
      switch character {
      case "(":
        brackets.append((pendingRound, 0))
        pendingRound = false
        output += "("
      case ")":
        guard let bracket = brackets.popLast() else { throw refuse("a bracket is not opened") }
        // SQLite's round(x) rounds to a whole number, which ROUND writes as ROUND(x, 0).
        output += bracket.round && bracket.commas == 0 ? ", 0)" : ")"
      case ",":
        guard !brackets.isEmpty else { throw refuse("a comma is outside a function") }
        brackets[brackets.count - 1].commas += 1
        output += ", "
      case "+", "-", "*", "/":
        output += " \(character) "
      case "<", ">", "=", "!":
        var op = String(character)
        if let next, "=>".contains(next), !(character == ">" && next == ">") {
          op.append(next)
          index += 1
        }
        switch op {
        case "==", "=": op = "="
        case "!=", "<>": op = "<>"
        case "<", ">", "<=", ">=": break
        default: throw refuse("\(op) is not available")
        }
        output += " \(op) "
      case "'": throw refuse("a computed column calculates numbers, not text")
      default: throw refuse("\(character) is not available")
      }
      index += 1
    }
    do {
      var parser = try Formula(output)
      _ = try parser.parse()
    } catch let error as SevraError {
      throw refuse(error.message.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased())
    }
    return output.trimmingCharacters(in: .whitespaces)
  }
}
