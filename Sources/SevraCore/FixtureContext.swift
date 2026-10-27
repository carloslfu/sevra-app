import CryptoKit
import Foundation

/// Package-internal, task-scoped qualification seam. Product code never installs
/// this context; ordinary identifiers and timestamps retain their normal source.
package final class FixtureContext: @unchecked Sendable {
  @TaskLocal package static var current: FixtureContext?
  private let lock = NSLock()
  private var counter: UInt64 = 0
  private let seed: UInt32
  package let date: String
  package init(seed: UInt32, date: String = "2026-10-27T00:00:00Z") {
    self.seed = seed
    self.date = date
  }
  package func identifier() -> String {
    lock.lock()
    defer { lock.unlock() }
    counter += 1
    var bytes = Array(SHA256.hash(data: Data("sevra-fixture:\(seed):\(counter)".utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    let hex = bytes.map { String(format: "%02x", $0) }
    return [hex[0..<4], hex[4..<6], hex[6..<8], hex[8..<10], hex[10..<16]]
      .map { $0.joined() }.joined(separator: "-")
  }
}
