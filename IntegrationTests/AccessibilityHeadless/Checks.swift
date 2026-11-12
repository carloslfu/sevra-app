import Foundation
import SevraCore

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
  if try !condition() { throw SevraError("headless_check", message) }
}
func refuses(_ code: String, _ body: () throws -> Void) throws {
  do { try body() } catch let error as SevraError {
    try expect(error.code == code, "Expected \(code), got \(error.code): \(error)")
    return
  }
  throw SevraError("headless_check", "Expected refusal: " + code)
}
struct Suite {
  var passed = 0
  var failed = 0
  mutating func check(_ title: String, _ body: () throws -> Void) {
    do {
      try body()
      passed += 1
      print("PASS " + title)
    } catch {
      failed += 1
      print("FAIL " + title + ": " + error.localizedDescription)
    }
  }
}
@main struct Checks {
  static func main() throws {
    let failures = try runChecks()
    if failures > 0 { exit(1) }
  }
  static func runChecks() throws -> Int {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".build/accessibility-headless/" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    var suite = Suite()
    evidenceChecks(root, &suite)
    decisionChecks(&suite)
    presentationChecks(root, &suite)
    print(
      "HEADLESS RESULT: \(suite.passed) passed, \(suite.failed) failed. No app, windows, events, speech, clipboard, or preference changes."
    )
    return suite.failed
  }
}
