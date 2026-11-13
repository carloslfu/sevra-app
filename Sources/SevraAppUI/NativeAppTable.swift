import AppKit
import SevraAppProtocol
import SevraCore

@MainActor final class AppTable: NSView, NSTableViewDataSource, NSTableViewDelegate {
  private let session: NativeAppSession
  private var node: NativeAppNode
  private let grid = NSTableView()
  private let scroll = NSScrollView()
  private let label = NSTextField(labelWithString: "Loading…")
  private let previous = NSButton(title: "Previous", target: nil, action: nil)
  private let next = NSButton(title: "Next", target: nil, action: nil)
  private var rows: [Value] = []
  private var offset = 0
  private var generation = 0
  private var total = 0
  private var selected: String?
  private var applying = false
  private var lastPublishedID: String?
  private var loading = false
  private var reloadPending = false
  private var sorting: String?
  private var descending = false
  private var interactionEnabled = true
  init(session: NativeAppSession, node: NativeAppNode) {
    self.session = session
    self.node = node
    super.init(frame: .zero)
    sorting = node.props["sort"].string
    descending = node.props["descending"] == .bool(true)
    selected = node.props["selection"].string.flatMap { $0.isEmpty ? nil : $0 }
    grid.delegate = self
    grid.dataSource = self
    grid.usesAlternatingRowBackgroundColors = true
    grid.allowsMultipleSelection = false
    grid.style = .plain
    grid.rowHeight = 28
    grid.intercellSpacing = NSSize(width: 12, height: 0)
    grid.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    grid.target = self
    grid.action = #selector(selectClicked)
    grid.doubleAction = #selector(activate)
    grid.setAccessibilityLabel(node.props["label"].string ?? "App table")
    scroll.documentView = grid
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    let footer = NSStackView(views: [label, previous, next])
    footer.spacing = 8
    footer.alignment = .centerY
    previous.target = self
    previous.action = #selector(back)
    next.target = self
    next.action = #selector(forward)
    for view in [scroll, footer] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
      footer.leadingAnchor.constraint(equalTo: leadingAnchor),
      footer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    reload()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func setInteractionEnabled(_ enabled: Bool) {
    interactionEnabled = enabled
    grid.isEnabled = enabled
    previous.isEnabled = enabled && offset > 0
    next.isEnabled = enabled && offset + rows.count < total
  }
  func selectionShouldChange(in tableView: NSTableView) -> Bool { applying || interactionEnabled }
  override func layout() {
    super.layout()
    let available = scroll.contentSize.width
    if abs(grid.frame.width - available) > 1 {
      grid.setFrameSize(NSSize(width: available, height: grid.frame.height))
    }
    if !grid.tableColumns.isEmpty,
      abs(grid.tableColumns.reduce(0) { $0 + $1.width + grid.intercellSpacing.width } - available)
        > 1
    {
      grid.sizeToFit()
    }
  }
  func update(_ next: NativeAppNode) {
    let changed = ["table", "search", "sort", "descending", "columns"].contains {
      node.props[$0] != next.props[$0]
    }
    let selectionChanged = node.props["selection"] != next.props["selection"]
    node = next
    grid.setAccessibilityLabel(next.props["label"].string ?? "App table")
    if selectionChanged {
      selected = next.props["selection"].string
      if selected == "" { selected = nil }
      if selected == nil { lastPublishedID = nil }
      restoreSelection()
    }
    if changed {
      offset = 0
      sorting = next.props["sort"].string
      descending = next.props["descending"] == .bool(true)
      reload()
    }
  }
  func reload() {
    generation += 1
    guard !loading else {
      reloadPending = true
      return
    }
    loading = true
    let current = generation
    var args: [String: Value] = [
      "table": node.props["table"], "offset": .number(Double(offset)), "limit": .number(200),
      "search": node.props["search"] == .null ? .string("") : node.props["search"],
    ]
    if let sorting {
      args["sort"] = .string(sorting)
      args["descending"] = .bool(descending)
    }
    session.page(.object(args)) { [weak self] result in
      guard let self else { return }
      self.loading = false
      if self.reloadPending || self.generation != current {
        self.reloadPending = false
        self.reload()
        return
      }
      switch result {
      case .failure(let error): self.label.stringValue = error.localizedDescription
      case .success(let page): self.apply(page)
      }
    }
  }
  private func apply(_ page: Value) {
    var columns = page["columns"].array
    let chosen = node.props["columns"].array.map(\.text)
    if !chosen.isEmpty { columns = columns.filter { chosen.contains($0["id"].text) } }
    let columnIDs = columns.map { $0["id"].text }
    if grid.tableColumns.map({ $0.identifier.rawValue }) != columnIDs {
      for column in grid.tableColumns { grid.removeTableColumn(column) }
      for column in columns {
        let view = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column["id"].text))
        view.title = column["title"].text
        view.width = 140
        view.minWidth = 80
        view.headerCell.alignment = column["type"].text == "decimal" ? .right : .left
        if column["formula"] == .null {
          view.sortDescriptorPrototype = NSSortDescriptor(key: column["id"].text, ascending: true)
        }
        grid.addTableColumn(view)
      }
      grid.sizeToFit()
      needsLayout = true
    }
    rows = page["rows"].array
    total = page["total"].int ?? 0
    if offset >= total && offset > 0 {
      offset = max(0, ((total - 1) / 200) * 200)
      reload()
      return
    }
    applying = true
    grid.sortDescriptors = sorting.map { [NSSortDescriptor(key: $0, ascending: !descending)] } ?? []
    grid.reloadData()
    applying = false
    restoreSelection()
    label.stringValue =
      total == 0 ? "No matching records" : "\(offset + 1)–\(offset + rows.count) of \(total)"
    setInteractionEnabled(interactionEnabled)
  }
  private func restoreSelection() {
    applying = true
    if let index = rows.firstIndex(where: { $0["key"].text == selected }) {
      grid.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    } else {
      grid.deselectAll(nil)
    }
    applying = false
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard rows.indices.contains(row), let column = tableColumn else { return nil }
    let id = NSUserInterfaceItemIdentifier("cell")
    let cell = (grid.makeView(withIdentifier: id, owner: self) as? AppTableCell) ?? AppTableCell()
    cell.identifier = id
    cell.textField!.stringValue = rows[row]["values"][column.identifier.rawValue].text
    cell.textField!.alignment = column.headerCell.alignment
    cell.textField!.setAccessibilityLabel(column.title + ": " + cell.textField!.stringValue)
    return cell
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !applying else { return }
    publishSelection(grid.selectedRow)
  }
  @objc private func selectClicked() {
    publishSelection(grid.clickedRow)
  }
  private func publishSelection(_ index: Int) {
    guard !applying, interactionEnabled, rows.indices.contains(index) else { return }
    selected = rows[index]["key"].text
    let version = rows[index]["id"].text
    guard lastPublishedID != version else { return }
    lastPublishedID = version
    session.event(node: node.id, handler: "onSelect", value: rows[index])
  }
  func tableView(
    _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
  ) {
    guard !applying, interactionEnabled else { return }
    sorting = grid.sortDescriptors.first?.key
    descending = grid.sortDescriptors.first?.ascending == false
    offset = 0
    reload()
  }
  @objc private func back() {
    offset = max(0, offset - 200)
    reload()
  }
  @objc private func forward() {
    offset += 200
    reload()
  }
  @objc private func activate() {
    guard interactionEnabled, rows.indices.contains(grid.clickedRow) else { return }
    session.event(node: node.id, handler: "onActivate", value: rows[grid.clickedRow])
  }
}

/// A label's intrinsic height is centered inside the row, instead of stretching its text cell.
@MainActor private final class AppTableCell: NSTableCellView {
  init() {
    super.init(frame: .zero)
    let label = NSTextField(labelWithString: "")
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    textField = label
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor),
      label.trailingAnchor.constraint(equalTo: trailingAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
