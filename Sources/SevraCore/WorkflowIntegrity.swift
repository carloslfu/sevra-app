import Foundation

extension Workbook {
  func verifyWorkflows() throws {
    var after = ""
    while true {
      let rows = try db.execute(
        "SELECT id FROM workflow_runs WHERE id>? ORDER BY id LIMIT 100", [.string(after)])
      if rows.isEmpty { break }
      for row in rows {
        let run = try workflowRun(row["id"]!.text)
        let definition = try applicationDefinition(run["definition_id"].text)
        let source = try item(run["source_id"].text)
        let workflow = try DefinitionWorkflow(DefinitionDescriptor(definition.content))
        let steps = run["steps"].array
        try require(
          definition.id == run["definition_id"].text && definition.kind == "workflow"
            && source.kind == "application_invocation" && source.category == "source"
            && source.data["workflowRunID"] == run["id"]
            && source.data["definitionID"] == run["definition_id"]
            && source.data["normalizedArguments"] == run["arguments"]
            && source.data["actor"] == run["actor"] && source.data["policy"] == run["policy"]
            && steps.count == workflow.steps.count,
          "workflow_integrity", "The run disagrees with its pinned workflow or invocation.")
        try JSONDecoder().decode(ChangeActor.self, from: Data(run["actor"].json().utf8)).validate()
        var unfinished = false
        var claimed = 0
        for (index, step) in steps.enumerated() {
          let expected = workflow.steps[index]
          let state = step["state"].text
          try require(
            step["ordinal"].int == index && step["step_id"].text == expected.id
              && step["kind"].text == expected.kind && !(unfinished && state == "completed"),
            "workflow_integrity", "Workflow steps disagree with their pinned order.")
          if state != "completed" { unfinished = true }
          if state == "claimed" { claimed += 1 }
          let output = step["output"]
          if output != .null {
            try require(
              output["readRevision"].int.map { $0 >= 0 } == true
                && output["arguments"].object.count <= 32
                && output["definitionID"] == (expected.binding.map { .string($0.target) } ?? .null),
              "workflow_integrity", "Invalid retained workflow output.")
            if expected.kind == "evaluate" {
              try require(
                output["value"]["definitionID"] == output["definitionID"]
                  && output["value"]["nextCursor"] == .null
                  && output["value"]["readOnly"] == .bool(true),
                "workflow_integrity", "An evaluation output is incomplete or mismatched.")
              if output["value"]["kind"] == .string("query") {
                try validateWorkflowLookupResult(
                  output["value"], stepID: expected.id, workflow: workflow)
              }
            } else if expected.kind == "extract" {
              let value = output["value"]
              try validateWorkflowExtractionOutput(value, runID: run["id"].text, step: expected)
              try require(
                value["kind"] == .string("extraction")
                  && output["readRevision"] == value["request"]["readRevision"]
                  && (state != "completed" || value["complete"] == .bool(true)),
                "workflow_integrity", "An incomplete document cannot complete its workflow step.")
            } else if expected.kind == "intake" {
              let value = output["value"]
              try validateWorkflowIntakeOutput(value, runID: run["id"].text, step: expected)
              try require(
                output["readRevision"] == value["request"]["readRevision"],
                "workflow_integrity", "The intake lost its preparation read revision.")
            } else if expected.kind == "interpret" {
              let value = output["value"]
              let (_, response) = try validatedWorkflowInterpretation(
                .object([
                  "request": value["request"], "response": value["response"],
                  "metrics": value["metrics"],
                ]),
                runID: run["id"].text, step: expected, attemptID: value["request"]["attemptID"].text
              )
              let record = try item(value["recordID"].text)
              let interpretation = try DefinitionInterpretation(
                DefinitionDescriptor(try applicationDefinition(output["definitionID"].text).content)
              )
              try require(
                record.id == value["recordID"].text && record.kind == "interpretation"
                  && record.category == "record" && record.status == "draft"
                  && record.meaning == interpretation.meaning
                  && record.scenario == interpretation.scenario
                  && record.data["response"] == response
                  && record.data["requestID"] == value["request"]["requestID"]
                  && record.data["model"] == value["model"]
                  && value["model"] == value["request"]["model"]
                  && record.data["policy"] == value["request"]["policy"]
                  && value["definitionID"] == output["definitionID"]
                  && output["readRevision"] == value["request"]["readRevision"],
                "workflow_integrity",
                "The saved interpretation disagrees with its exact model request or draft Record.")
            }
          } else {
            try require(
              state != "completed" && state != "waiting_review",
              "workflow_integrity", "A completed step lost its output.")
          }
          let statistics = try db.execute(
            "SELECT count(*) AS total,min(generation) AS first,max(generation) AS last,coalesce(sum(CASE WHEN state='claimed' THEN 1 ELSE 0 END),0) AS active FROM workflow_attempts WHERE run_id=? AND step_id=?",
            [run["id"], step["step_id"]])[0]
          let count = statistics["total"]!.int!
          let base = step["attempt_base"].int ?? -1
          let latest = try db.execute(
            "SELECT state FROM workflow_attempts WHERE run_id=? AND step_id=? ORDER BY generation DESC LIMIT 1",
            [run["id"], step["step_id"]]
          ).first
          try require(
            base >= 0 && base <= count && count - base <= 32
              && (count == 0 || (statistics["first"]?.int == 1 && statistics["last"]?.int == count))
              && statistics["active"]?.int == (state == "claimed" ? 1 : 0)
              && (state != "claimed" || latest?["state"] == .string("claimed")),
            "workflow_integrity", "Invalid worker claim generations or retry budget.")
          if expected.kind == "review" {
            let action = steps.first { $0["step_id"].text == expected.review }
            let proposals = action?["output"]["value"]["proposals"].array ?? []
            let approvals = try db.execute(
              "SELECT * FROM workflow_approvals WHERE run_id=? AND step_id=? ORDER BY proposal_id LIMIT 51",
              [run["id"], step["step_id"]])
            try require(
              approvals.count <= 50
                && Set(approvals.map { $0["proposal_id"]!.text }) == Set(proposals.map(\.text)),
              "workflow_integrity", "Review approvals disagree with the exact action proposals.")
            for approval in approvals {
              if let acceptedID = approval["accepted_id"]?.string {
                let proposal = try item(approval["proposal_id"]!.text)
                let accepted = try item(acceptedID)
                try require(
                  accepted.id == acceptedID && workflowAcceptedVersion(proposal, accepted),
                  "workflow_integrity", "An approval changed its exact business interpretation.")
              } else {
                try require(
                  state != "completed", "workflow_integrity",
                  "A completed review has no accepted version.")
              }
            }
          }
        }
        try require(
          claimed <= 1 && (claimed == 1) == (run["state"] == .string("running"))
            && ((run["state"] == .string("completed")) == !unfinished),
          "workflow_integrity", "The run status disagrees with its saved steps.")
        after = run["id"].text
      }
    }
  }
}
