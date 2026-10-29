import Foundation

/// Trusted fixture-only barriers for killing a worker inside/after its real
/// checkpoint transaction. No product path installs one, and workbook contents
/// or process environment cannot enable this observer.
package enum WorkflowPublicationProbe {
  package enum Stage { case prepared, committed }
  @TaskLocal package static var observer: (@Sendable (Stage, String) -> Void)?
}
