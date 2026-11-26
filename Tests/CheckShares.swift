import Foundation

/// The default run's independent groups, in order. Each makes its own workbooks under `temp`,
/// so separate processes can run different groups at once.
private let groups: [() -> Void] = [
  { checkSpaceSnapshots(at: temp) },
  { checkAssetPreview(at: temp) },
  { checkAssetCopies(at: temp) },
  { checkCorruptMetadata(at: temp) },
  { checkRecentItems(at: temp) },
  { checkSearchSnippets(at: temp) },
  { checkConversationContext(at: temp) },
  { checkChats(at: temp) },
  { checkContinuationEvidence(at: temp) },
  { checkToolReceipts(at: temp) },
  { checkDocumentComposition(at: temp) },
  { checkDocumentCopyChoices(at: temp) },
  { checkFoldersAndTemplates(at: temp) },
  { checkReferences(at: temp) },
  { checkInlineReferences(at: temp) },
  { checkFileReferences(at: temp) },
  { checkAgentReferences(at: temp) },
  { checkContextualIntake(at: temp) },
  { checkExtractedContent(at: temp) },
  { checkTableIntake(at: temp) },
  { checkManagedDatasets(at: temp) },
  { checkDatasetDefinitions(at: temp) },
  { checkSheetFormulas(at: temp) },
  { checkDatasetQueries(at: temp) },
  { checkApplicationDefinitions(at: temp) },
  { checkApplicationActions(at: temp) },
  { checkDocumentActions(at: temp) },
  { checkToolActions(at: temp) },
  { checkDefinitionTools(at: temp) },
  { checkWorkflowTools(at: temp) },
  { checkWorkflowInterpretations(at: temp) },
  { checkWorkflowExtractions(at: temp) },
  { checkWorkflowIntakes(at: temp) },
  { checkDefinitionResults(at: temp) },
  { checkWorkflows(at: temp) },
  { checkPersistence(at: temp) },
  { checkBusinessEvents(at: temp) },
  { checkAutomaticAncestry(at: temp) },
  { checkSpaceEditing(at: temp) },
  { checkCalendarSchedules() },
  { checkAutomationDefinitions(at: temp) },
  { checkAutomationPlanning(at: temp) },
  { checkAutomationExecution(at: temp) },
  { checkCheckAutomations(at: temp) },
  { checkAutomationCausality(at: temp) },
  { checkSharedBusinessAdmissions(at: temp) },
  { checkDerivationRoles(at: temp) },
  { checkBusinessOrigins(at: temp) },
  { checkBusinessInputs(at: temp) },
  { checkReviewFollowUps(at: temp) },
  { checkRemoval(at: temp) },
  { check("Chat operations and immutable table changes") { try checkChatOperations() } },
]

/// `--share I/N`: run share I of N, numbered from 0, so N processes split the default checks.
/// Share 0 also runs the opening sequence in main.swift, whose checks build on one workbook.
func checkShare() -> (index: Int, count: Int)? {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard arguments.first == "--share" else { return nil }
  let parts = arguments.count == 2 ? arguments[1].split(separator: "/").compactMap { Int($0) } : []
  guard parts.count == 2, parts[1] > 0, (0..<parts[1]).contains(parts[0]) else {
    fputs("Usage: sevra-checks --share I/N, with 0 <= I < N\n", stderr)
    exit(2)
  }
  return (parts[0], parts[1])
}

/// Runs every group, or every Nth one starting at I for share I of N.
func runGroups(_ share: (index: Int, count: Int)?) {
  for (number, group) in groups.enumerated()
  where share.map({ number % $0.count == $0.index }) ?? true {
    group()
  }
}
