"""Static adapter checks complement the executable headless behavior suite.
These do not inspect an accessibility tree or claim rendered/OS-level behavior.
"""
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
checks = 0

def source(path):
    return (root / path).read_text()

def check(name, requirements):
    global checks
    for path, pattern in requirements:
        assert re.search(pattern, source(path), re.S), f'{name}: missing adapter contract in {path}: {pattern}'
    checks += 1
    print('PASS static wiring ' + name)

check('A1 focus decisions reach native editing and paste', [
    ('Sources/SevraTableUI/NativeTable.swift', r'TableCellNavigation.destination\('),
    ('Sources/SevraTableUI/NativeTable.swift', r'focusCell\(row: cell.row, column: cell.column\).*?beginCellEditing\('),
    ('Sources/SevraTableUI/NativeTable.swift', r'parent.onSelect\(selected, column\)'),
    ('Sources/SevraApp/ContentViews.swift', r'TableClipboard.edits\(.*?column: column\).*?expectedRevision: page.revision'),
])
check('A2 all three data surfaces use the shared presentation', [
    (p, r'EvidenceTable\(') for p in ['Sources/SevraApp/ContentViews.swift','Sources/SevraApp/DefinitionComponentView.swift','Sources/SevraApp/StructuredValueView.swift']
] + [('Sources/SevraApp/EvidenceTable.swift', r'content: .evidence\(')])
check('A3 labels, hints, errors and explicit validation focus', [
    ('Sources/SevraApp/FormComponentView.swift', r'private var presentation: FormFieldPresentation'),
    ('Sources/SevraApp/FormComponentView.swift', r'accessibilityLabel\(accessibleTitle\).accessibilityHint\(fieldHelp\)'),
    ('Sources/SevraApp/FormComponentView.swift', r'path: fieldPath \+ \[.number\(Double\(index\)\), .string\(field\["id"\].text\)\]'),
    ('Sources/SevraApp/FormComponentView.swift', r'await session.prepare\(\).*?workspace.route == origin.*?validationFocused = true'),
])
check('A4 exact reading API, status, truncation and image descriptions', [
    ('Sources/SevraApp/ExtractedTextView.swift', r'workbook.extractedTextPage\(.*?expectedRevision: expected'),
    ('Sources/SevraApp/ExtractedTextView.swift', r'chunk\["truncated"\].int == 1'),
    ('Sources/SevraApp/ExtractedTextView.swift', r'openOriginal\(chunk\["locator"\].string\)'),
    ('Sources/SevraApp/Viewers.swift', r'Button\("Read extracted text…"\)'),
    ('Sources/SevraApp/Viewers.swift', r'accessibilityLabel\("Image: " \+ title\)'),
    ('Sources/SevraApp/ImageDescriptionView.swift', r'workbook.saveImageDescription\('),
])
check('A5 charts consume tested metadata and retain an exact alternative', [
    ('Sources/SevraApp/ContentViews.swift', r'ChartReadingPresentation\('),
    ('Sources/SevraApp/ContentViews.swift', r'chartXAxisLabel\(xTitle\).*?chartYAxisLabel\(yTitle\).*?accessibilityValue\(presentation.summary\)'),
    ('Sources/SevraApp/ContentViews.swift', r'DisclosureGroup\("Exact values and sources"\).*?snapshotTable\(data\)'),
])
check('A6 native posting is gated by tested policy at low priority', [
    ('Sources/SevraTableUI/ReadingStyle.swift', r'owner.policy.update\(message\)'),
    ('Sources/SevraTableUI/ReadingStyle.swift', r'owner.policy.canDeliver\(.*?ownWindowIsKey: window.isKeyWindow.*?appIsActive: NSApp.isActive'),
    ('Sources/SevraTableUI/ReadingStyle.swift', r'NSAccessibility.post\(.*?announcement: event.text.*?NSAccessibilityPriorityLevel.low'),
    ('Sources/SevraApp/WorkbookView.swift', r'announceStatus\(state.error \?\? state.terminalStatus\)'),
])
check('A7 own-window policy, message return and named panes remain wired', [
    ('Sources/SevraApp/WorkspaceState.swift', r'ReadingFocusPolicy.canRequest\('),
    ('Sources/SevraApp/WorkbookView.swift', r'ReadingFocusPolicy.canApply\(.*?await Task.yield\(\).*?ReadingFocusPolicy.canApply\('),
    ('Sources/SevraApp/WorkbookView.swift', r'ReadingFocusPolicy.destination\('),
    ('Sources/SevraApp/WorkbookView.swift', r'accessibilityLabel\("Workspace"\)'),
    ('Sources/SevraApp/WorkbookView.swift', r'accessibilityLabel\("Conversation"\)'),
    ('Sources/SevraApp/ConversationViews.swift', r'returningTo: .message\(message.id\)'),
])
check('A8 metrics reach controls, native text and flexible sheets', [
    ('Sources/SevraTableUI/NativeTable.swift', r'rowHeight = ReadingStyle.points\(30, scale: textScale\)'),
    ('Sources/SevraPreviewUI/ReadOnlyTableView.swift', r'ReadingStyle.points\(13, scale: parent.textScale\)'),
    ('Sources/SevraPreviewUI/LongTextViews.swift', r'ReadingStyle.scale\(textScale\)'),
    ('Sources/SevraApp/ReadingSizeCommands.swift', r'@AppStorage\(ReadingStyle.preference\)'),
    ('Sources/SevraApp/SpeechAndSettings.swift', r'@AppStorage\(ReadingStyle.preference\)'),
    ('Sources/SevraApp/WorkbookView.swift', r'private struct ConversationNameSheet.*?ScrollView.*?minWidth:.*?idealWidth:'),
])
check('A9 native action/press/keyboard routes use the tested immutable action set', [
    ('Sources/SevraPreviewUI/ReadOnlyTableView.swift', r'setAccessibilityCustomActions\(.*?actionSet.perform\('),
    ('Sources/SevraPreviewUI/ReadOnlyTableView.swift', r'field.press =.*?actionSet.perform\(\s*0,'),
    ('Sources/SevraPreviewUI/ReadOnlyTableView.swift', r'func open\(row:.*?actions.primaryIndex.*?actions.perform\('),
    ('Sources/SevraPreviewUI/ReadOnlyTableView.swift', r'PreviewCellActions.opensOnClick\('),
])
check('A10 PDF matching and both user routes carry Reduce Motion', [
    ('Sources/SevraApp/Viewers.swift', r'private var search = PDFMatchSearch\('),
    ('Sources/SevraApp/Viewers.swift', r'func nextMatch\(reduceMotion: Bool = true\)'),
    ('Sources/SevraApp/Viewers.swift', r'setCurrentSelection\(selection, animate: match.animate\)'),
])
assert source('Sources/SevraApp/Viewers.swift').count('controls.nextMatch(reduceMotion: reduceMotion)') == 2

# This target is intentionally separate from existing UI checks. Do not silently add a UI runner.
for file in (root / 'IntegrationTests/AccessibilityHeadless').glob('*.swift'):
    assert not re.search(r'\b(NSApp|NSApplication|NSWindow|NSView|NSHostingView|NSEvent|NSPasteboard|NSWorkspace|UserDefaults|PDFView|RunLoop)\b|NSAccessibility\.post', file.read_text()), f'UI/global-state API in {file}'
print(f'{checks} static adapter groups passed. No UI or accessibility-tree inspection.')
