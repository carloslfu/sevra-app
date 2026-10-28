import Foundation
import SevraCore

func checkContextualIntake(at root: URL) {
  check("capture request retry survives a missing input and refuses changed intent") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("CaptureRetry.sevra"), title: "Retry")
    let file = root.appendingPathComponent("capture-retry.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: file)
    let first = try book.captureIntake(file, role: .reference, token: "one-capture")
    try FileManager.default.removeItem(at: file)
    let retry = try book.captureIntake(file, role: .reference, token: "one-capture")
    try expect(first.id == retry.id && first.sourceID == retry.sourceID)
    try expect(try book.counts()["sources"].int == 1)
    try refuses("idempotency") {
      _ = try book.captureIntake(file, role: .values, token: "one-capture")
    }
    try refuses("idempotency") {
      _ = try book.captureIntake(
        root.appendingPathComponent("another.csv"), role: .reference,
        token: "one-capture")
    }
    try expect(try book.runIntake(first.id).role == .reference)
  }
  check("interrupted capture registration recovers its requested use without guessing from suffix")
  {
    let book = try Workbook.create(
      at: root.appendingPathComponent("CaptureRecovery.sevra"), title: "Recovery")
    let file = root.appendingPathComponent("capture-recovery.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: file)
    let first = try book.captureIntake(file, role: .reference, token: "interrupted-capture")
    // Model process exit immediately after the file receipt and before job registration.
    _ = try referenceSQL(
      book, "DELETE FROM intake_jobs; DELETE FROM operations WHERE kind='intake_begin';")
    try book.resumeIntake(first.sourceID)
    try expect(try book.intakeJob(first.id).role == .reference)
    try expect(try book.intakeJob(first.id).state == "ready" && book.datasets().isEmpty)
  }
  check("ambiguous capture survives reopen and reference resume never creates tables") {
    let book = try Workbook.create(at: root.appendingPathComponent("Roles.sevra"), title: "Roles")
    let file = root.appendingPathComponent("roles.csv")
    try Data("sku,quantity\n0012,4\n".utf8).write(to: file)
    let source = try book.importFile(file)
    let job = try book.beginIntake(sourceID: source.id, token: "ambiguous-role")
    let awaiting = try book.runIntake(job.id)
    try expect(awaiting.state == "awaiting_role" && awaiting.datasetIDs.isEmpty)
    try expect(try book.datasets().isEmpty)
    try FileManager.default.removeItem(at: file)
    let reopened = try Workbook(book.url)
    try expect(try reopened.intakeJob(job.id).state == "awaiting_role")
    _ = try reopened.chooseIntakeRole(job.id, role: .reference, token: "reference-choice")
    let ready = try reopened.runIntake(job.id)
    try reopened.resumeIntake(source.id)
    try expect(ready.role == .reference && ready.state == "ready")
    try expect(try reopened.datasets().isEmpty)
    try refuses("idempotency") {
      _ = try reopened.beginIntake(sourceID: source.id, role: .values, token: "ambiguous-role")
    }
    try refuses("intake_role") { _ = try reopened.chooseIntakeRole(job.id, role: .values) }
    try expect(try reopened.search("0012").hits.contains { $0.itemID == source.id })
  }
  check("analysis and explicit values share original identity with resumable conversion") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("RoleReuse.sevra"), title: "Reuse")
    let file = root.appendingPathComponent("reuse.csv")
    try Data("sku,quantity\n0012,4\n0013,5\n".utf8).write(to: file)
    let source = try book.importFile(file)
    let input = try book.beginIntake(sourceID: source.id, role: .analysis, token: "analysis-use")
    let analysis = try book.runIntake(input.id)
    try expect(analysis.report["inspection"]["sheets"].array[0]["rows"].int == 3)
    try expect(analysis.datasetIDs.isEmpty && analysis.state == "ready")
    try expect(try book.datasets().isEmpty)
    let conversion = try book.beginIntake(sourceID: source.id, role: .values, token: "values-use")
    let cancel = Cancellation()
    cancel.cancel()
    try refuses("cancelled") { _ = try book.runIntake(conversion.id, cancellation: cancel) }
    try expect(try book.intakeJob(conversion.id).state == "captured")
    let first = try book.runIntake(conversion.id)
    try expect(first.state == "ready" && first.datasetIDs.count == 1)
    let rows = try book.rows(first.datasetIDs[0])
    try expect(rows.count == 2 && rows[0].data["sku"].text == "0012")
    let revision = try book.revision()
    let retry = try book.runIntake(conversion.id)
    try expect(first.datasetIDs == retry.datasetIDs && book.revision() == revision)
    let again = try book.beginIntake(
      sourceID: source.id, role: .values, token: "another-values-use")
    try expect(try book.runIntake(again.id).datasetIDs == first.datasetIDs)
    try expect(try book.datasets().count == 1)
    let portable = root.appendingPathComponent("Roles.sevraz")
    try book.export(to: portable)
    let restored = try Workbook.openArchive(
      portable, at: root.appendingPathComponent("RolesRestored.sevra"))
    try expect(try restored.intakeJob(conversion.id).datasetIDs == first.datasetIDs)
    try expect(try restored.verify()["ok"] == .bool(true))
  }
  check("failed structured interpretation retains source and never reports a converted table") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("RoleFailure.sevra"), title: "Failure")
    let file = root.appendingPathComponent("bad-roles.csv")
    try Data("header\n\"unterminated".utf8).write(to: file)
    let source = try book.importFile(file)
    let job = try book.beginIntake(sourceID: source.id, role: .values)
    try refuses { _ = try book.runIntake(job.id) }
    let failed = try book.intakeJob(job.id)
    try expect(failed.state == "failed" && failed.datasetIDs.isEmpty)
    try expect(try book.assetURL(source.assetID!, verify: true).isFileURL)
    try expect(try book.datasets().isEmpty)
    let reference = try book.beginIntake(sourceID: source.id, role: .reference)
    try expect(try book.runIntake(reference.id).state == "ready")
    try expect(try book.datasets().isEmpty)
  }
  check("previous development format is refused without erasing its contents") {
    let book = try Workbook.create(
      at: root.appendingPathComponent("UnsupportedRoleV7.sevra"), title: "V7")
    _ = try book.addItem(category: "source", kind: "note", title: "Preserve me")
    _ = try referenceSQL(book, "DROP TABLE intake_jobs; PRAGMA user_version=7;")
    let database = book.url.appendingPathComponent("workbook.sqlite")
    let before = try Data(contentsOf: database)
    try refuses("schema") { _ = try Workbook(book.url) }
    try expect(try Data(contentsOf: database) == before)
  }
}
