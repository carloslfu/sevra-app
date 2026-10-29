import Foundation

/// Package-only fault-injection seam for process-death checks. Product code
/// never installs an observer; workbook data and environment variables cannot
/// enable it. The prepared boundary is inside the real SQLite transaction.
package enum CheckpointPublicationProbe {
  package enum Stage: String, Sendable { case prepared, published }
  @TaskLocal package static var observer: (@Sendable (Stage, String) -> Void)?
}
