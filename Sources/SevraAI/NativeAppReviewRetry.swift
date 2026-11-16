import CryptoKit
import Foundation
import SevraCore

/// One request's last rejected review, scoped to identical package, fixtures and
/// tests. It informs the next review but never carries forward passed checks.
package struct NativeAppReviewRetry {
  private var fingerprint: String?
  private var diagnostic: Value = .null
  package init() {}

  package mutating func context(for arguments: Value) throws -> Value {
    let next = SHA256.hash(data: Data(try arguments.json().utf8))
      .map { String(format: "%02x", $0) }.joined()
    if fingerprint != next {
      fingerprint = next
      diagnostic = .null
    }
    return diagnostic
  }

  package mutating func observe(_ metric: Value, receiptID: String) {
    guard fingerprint != nil, metric["host"] == .string("native_app_review_probe"),
      case .object = metric["probe"]
    else { return }
    var fields = metric["probe"].object
    fields["result"] = Self.reviewerFeedback(metric["probe"]["result"])
    var probe = Value.object(fields)
    if (try? probe.json().utf8.count) ?? Int.max > 16_384 {
      let result = probe["result"]
      probe = .object([
        "result": .object([
          // Bound UTF-8 bytes rather than grapheme clusters, then reserve for
          // JSON escaping (up to six bytes per input byte for control text).
          "status": .string(
            String(decoding: result["status"].text.utf8.prefix(128), as: UTF8.self)),
          "error": .string(String(decoding: result["error"].text.utf8.prefix(2000), as: UTF8.self)),
          "notice": .string(
            "The larger previous verdict was omitted. This is diagnostic feedback only."),
        ])
      ])
    }
    diagnostic = .object(["receiptID": .string(receiptID), "probe": probe])
  }

  /// Retain detailed checks in the audit receipt. The reviewer needs their
  /// outcome, and can use the existing original and interface evidence.
  static func reviewerFeedback(_ feedback: Value) -> Value {
    guard case .object(let check) = feedback["check"] else { return feedback }
    let outcome = Set(["status", "assertions", "steps", "transactions"])
    var result = feedback.object
    result["check"] = .object(check.filter { outcome.contains($0.key) })
    return .object(result)
  }

  package mutating func discard() {
    fingerprint = nil
    diagnostic = .null
  }
}
