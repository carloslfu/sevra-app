import Foundation

/// Where new workbooks go and what they are called, so starting one needs no save panel.
public enum WorkbookLibrary {
  public static let preferenceKey = "workbooksFolder"
  public static let untitled = "Untitled"

  /// A plain folder in the home folder. It is outside Documents on purpose: Documents can sync to
  /// iCloud, which must not carry a live database, and it asks for permission on first use.
  public static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Sevra Workbooks")
  }

  public static func directory(_ defaults: UserDefaults = .standard) -> URL {
    defaults.string(forKey: preferenceKey).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
      ?? defaultDirectory
  }

  /// A name a file can carry: one line, no path separators, no leading dot, at most 80 characters.
  public static func name(from text: String) -> String {
    let allowed = text.precomposedStringWithCanonicalMapping.unicodeScalars.map {
      scalar -> Character in
      if scalar == "/" || scalar == ":" || scalar.properties.generalCategory == .control
        || scalar.properties.generalCategory == .format
      {
        return " "
      }
      return Character(scalar)
    }
    var name = String(allowed).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    while name.hasPrefix(".") { name.removeFirst() }
    name = String(name.prefix(80)).trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? untitled : name
  }

  /// A workbook started by a message is named after the start of it. A greeting or a word or two
  /// says nothing about the work, so that stays untitled until the person names it.
  public static func name(fromMessage text: String) -> String {
    let title = Workbook.chatTitle(from: text)
    guard title != Workbook.newChatTitle else { return untitled }
    let words = title.split(separator: " ")
    guard words.count >= 3 else { return untitled }
    var short = words.prefix(8).joined(separator: " ")
    var shortened = words.count > 8
    while short.count > 56 {
      short = short.split(separator: " ").dropLast().joined(separator: " ")
      shortened = true
    }
    while let last = short.last, ".,;:?!…".contains(last) { short.removeLast() }
    guard !short.isEmpty else { return untitled }
    return name(from: short.prefix(1).uppercased() + short.dropFirst() + (shortened ? "…" : ""))
  }

  /// A workbook started from files is named after the first of them.
  public static func name(fromFiles files: [URL]) -> String {
    files.first.map { name(from: $0.deletingPathExtension().lastPathComponent) } ?? untitled
  }

  /// A free place for a workbook of this name: "Name.sevra", then "Name 2.sevra" and so on.
  public static func available(_ name: String, in directory: URL) -> URL {
    let name = Self.name(from: name)
    var url = directory.appendingPathComponent(name + ".sevra")
    var number = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = directory.appendingPathComponent("\(name) \(number).sevra")
      number += 1
    }
    return url
  }

  /// A free place in the workbooks folder, which is made if it is not there yet.
  public static func newURL(_ name: String, defaults: UserDefaults = .standard) throws -> URL {
    let directory = Self.directory(defaults)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return available(name, in: directory)
  }

  /// Where a rename would put the workbook. A name already taken in that folder is refused, so
  /// nothing is ever replaced. A change of letter case alone is the same file on a Mac disk.
  public static func renameTarget(_ url: URL, to requested: String) throws -> URL {
    let name = Self.name(from: requested)
    let target = url.deletingLastPathComponent().appendingPathComponent(name + ".sevra")
    let same = target.lastPathComponent.lowercased() == url.lastPathComponent.lowercased()
    try require(
      same || !FileManager.default.fileExists(atPath: target.path), "exists",
      "A workbook named “\(name)” is already in this folder.")
    return target
  }

  /// Renames a closed workbook where it is: the file and the title in its manifest together.
  @discardableResult public static func rename(_ url: URL, to requested: String) throws -> URL {
    let target = try renameTarget(url, to: requested)
    let name = target.deletingPathExtension().lastPathComponent
    let manifestName = "manifest.json"
    let manifest = try Value.parse(
      String(contentsOf: url.appendingPathComponent(manifestName), encoding: .utf8))
    try require(manifest["format"].text == "sevra", "format", "This is not a Sevra workbook.")
    let sameFile = target.lastPathComponent == url.lastPathComponent
    if !sameFile { try FileManager.default.moveItem(at: url, to: target) }
    do {
      guard case .object(var fields) = manifest else {
        throw SevraError("manifest", "The workbook manifest is not readable.")
      }
      fields["title"] = .string(name)
      // The person named it, so Sevra no longer changes the name.
      fields["titleSource"] = .string("person")
      try Data(try Value.object(fields).json().utf8).write(
        to: target.appendingPathComponent(manifestName), options: .atomic)
    } catch {
      if !sameFile { try? FileManager.default.moveItem(at: target, to: url) }
      throw error
    }
    return target
  }

  /// The name a workbook shows: its manifest title, or its file name when that cannot be read.
  public static func displayName(_ path: String) -> String {
    let url = URL(fileURLWithPath: path)
    let file = url.deletingPathExtension().lastPathComponent
    guard let text = try? String(contentsOf: url.appendingPathComponent("manifest.json"), encoding: .utf8),
      text.utf8.count <= 64_000, let title = (try? Value.parse(text))?["title"].string,
      !title.isEmpty
    else { return file }
    return title
  }

  /// A closed workbook whose name Sevra chose, moved to a file named like it: "Name.sevra", or
  /// "Name 2.sevra" when that is taken. Nil when there is nothing to move.
  public static func fileMatchingAutomaticTitle(_ url: URL) throws -> URL? {
    let manifest = try Value.parse(
      String(contentsOf: url.appendingPathComponent("manifest.json"), encoding: .utf8))
    guard manifest["format"].text == "sevra", Workbook.automaticTitle(manifest) else { return nil }
    let name = Self.name(from: manifest["title"].text)
    let current = url.deletingPathExtension().lastPathComponent
    // "Name 2" is already this name's file when "Name" was taken.
    guard current != name, current.range(
      of: "^" + NSRegularExpression.escapedPattern(for: name) + " [0-9]+$",
      options: .regularExpression) == nil
    else { return nil }
    let target = available(name, in: url.deletingLastPathComponent())
    try FileManager.default.moveItem(at: url, to: target)
    return target
  }
}
