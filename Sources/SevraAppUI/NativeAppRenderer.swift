import AppKit
import SevraAppProtocol
import SevraCore
import SwiftUI

/// Keyboard traversal must reveal the focused control inside the native app viewport.
@MainActor private final class AppTextField: NSTextField {
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { scrollToVisible(bounds.insetBy(dx: 0, dy: -8)) }
    return accepted
  }
}
@MainActor private final class AppButton: NSButton {
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { scrollToVisible(bounds.insetBy(dx: 0, dy: -8)) }
    return accepted
  }
}

public struct NativeAppSurface: NSViewRepresentable {
  public let session: NativeAppSession
  public init(session: NativeAppSession) { self.session = session }
  public func makeNSView(context: Context) -> NativeAppRenderer {
    NativeAppRenderer(session: session)
  }
  public func updateNSView(_ view: NativeAppRenderer, context: Context) {}
  public func sizeThatFits(
    _ proposal: ProposedViewSize, nsView: NativeAppRenderer, context: Context
  ) -> CGSize? {
    CGSize(width: proposal.width ?? 480, height: proposal.height ?? 480)
  }
  public static func dismantleNSView(_ view: NativeAppRenderer, coordinator: ()) {
    view.disconnect()
  }
}

@MainActor public final class NativeAppRenderer: NSView {
  private let session: NativeAppSession
  private var elements: [String: AppElement] = [:]
  private var rootID: String?
  private let scroll = NSScrollView()
  private var documentWidth: NSLayoutConstraint?
  public init(session: NativeAppSession) {
    self.session = session
    super.init(frame: .zero)
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.autoresizingMask = [.width, .height]
    addSubview(scroll)
    session.onFrame = { [weak self] tree, changed in self?.apply(tree, changed: changed) }
    session.onData = { [weak self] aliases in
      guard let self else { return }
      for element in self.elements.values {
        if aliases.contains(element.node.props["table"].text) { element.table?.reload() }
      }
    }
    apply(session.tree, changed: Set(session.tree.nodes.keys))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  public override var isFlipped: Bool { true }
  public func disconnect() {
    session.onFrame = nil
    session.onData = nil
  }
  public func view(for id: String) -> NSView? { elements[id]?.content }
  private func apply(_ tree: NativeAppTree, changed: Set<String>) {
    for id in elements.keys where tree.nodes[id] == nil {
      elements.removeValue(forKey: id)?.removeFromSuperview()
    }
    for id in changed {
      guard let node = tree.nodes[id] else { continue }
      if let old = elements[id], old.node.type != node.type {
        old.removeFromSuperview()
        elements[id] = nil
      }
      if elements[id] == nil { elements[id] = AppElement(node: node, session: session) }
      elements[id]?.update(node)
    }
    let enabled = tree.interactionEnabled
    for element in elements.values {
      element.arrange(element.node.children.compactMap { elements[$0] })
      element.setInteractionEnabled(enabled[element.node.id] == true)
    }
    if rootID != tree.root || scroll.documentView !== tree.root.flatMap({ elements[$0] }) {
      documentWidth?.isActive = false
      documentWidth = nil
      rootID = tree.root
      scroll.documentView = tree.root.flatMap { elements[$0] }
      if let view = scroll.documentView {
        documentWidth = view.widthAnchor.constraint(
          equalToConstant: max(1, scroll.contentSize.width))
        documentWidth?.isActive = true
      }
    }
    needsLayout = true
  }
  public override func layout() {
    super.layout()
    scroll.frame = bounds
    guard let view = scroll.documentView else { return }
    let width = max(1, scroll.contentSize.width)
    if documentWidth?.constant != width { documentWidth?.constant = width }
    view.layoutSubtreeIfNeeded()
    let height = max(1, min(1_000_000, view.fittingSize.height))
    view.setFrameSize(NSSize(width: width, height: height))
  }

}

@MainActor
final class AppElement: NSView, NSTextFieldDelegate, NSTextViewDelegate, NSTabViewDelegate {
  var node: NativeAppNode
  let session: NativeAppSession
  let content: NSView
  var table: AppTable?
  private var arranged: [String] = []
  private var childConstraints: [NSLayoutConstraint] = []
  private var arrangement = ""
  private var dimensions: [NSLayoutConstraint] = []
  private var inputRevision = 0
  private var applying = false
  private var interactionEnabled = true
  private var disclosureOpen = true
  private var disclosureBody: NSStackView?
  private var disclosureButton: NSButton?
  private var disclosureTitle: NSTextField?
  init(node: NativeAppNode, session: NativeAppSession) {
    self.node = node
    self.session = session
    switch node.type {
    case "text": content = NSTextField(wrappingLabelWithString: "")
    case "button": content = AppButton(title: "", target: nil, action: nil)
    case "textField": content = AppTextField(string: "")
    case "textEditor":
      let scroll = NSScrollView()
      scroll.hasVerticalScroller = true
      let editor = NSTextView()
      editor.isRichText = false
      editor.isAutomaticQuoteSubstitutionEnabled = false
      editor.isVerticallyResizable = true
      editor.autoresizingMask = [.width]
      editor.textContainer?.widthTracksTextView = true
      scroll.documentView = editor
      content = scroll
    case "toggle": content = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    case "picker": content = NSPopUpButton(frame: .zero, pullsDown: false)
    case "slider":
      content = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    case "date":
      let picker = NSDatePicker()
      picker.datePickerStyle = .textFieldAndStepper
      picker.datePickerElements = .yearMonthDay
      content = picker
    case "progress": content = NSProgressIndicator()
    case "split": content = NSSplitView()
    case "tabs": content = NSTabView()
    case "scroll":
      let scroll = NSScrollView()
      scroll.hasVerticalScroller = true
      content = scroll
    case "grid": content = NSGridView()
    case "canvas": content = AppCanvas()
    case "image": content = NSImageView()
    case "table":
      let view = AppTable(session: session, node: node)
      content = view
      table = view
    case "spacer": content = NSView()
    default:
      let stack = NSStackView()
      stack.orientation = node.type == "row" ? .horizontal : .vertical
      stack.alignment = node.type == "row" ? .centerY : .leading
      stack.spacing = 10
      content = stack
    }
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.topAnchor.constraint(equalTo: topAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    if let control = content as? NSControl {
      control.target = self
      control.action = #selector(action)
    }
    if node.type == "textField", let field = content as? NSTextField { field.delegate = self }
    if let editor = (content as? NSScrollView)?.documentView as? NSTextView {
      editor.delegate = self
    }
    if let tabs = content as? NSTabView { tabs.delegate = self }
    if let canvas = content as? AppCanvas {
      canvas.event = { [weak self] region, point, phase in
        guard let self else { return }
        self.session.event(
          node: self.node.id, handler: phase == "end" ? "onDrop" : "onClick",
          value: .string(region),
          extra: ["x": .number(point.x), "y": .number(point.y)])
      }
    }
    if node.type == "disclosure", let stack = content as? NSStackView {
      let button = NSButton(title: "", target: self, action: #selector(disclose))
      button.bezelStyle = .disclosure
      button.setButtonType(.pushOnPushOff)
      let title = NSTextField(wrappingLabelWithString: "")
      let header = NSStackView(views: [button, title])
      header.spacing = 6
      header.alignment = .centerY
      let body = NSStackView()
      body.orientation = .vertical
      body.alignment = .leading
      stack.addArrangedSubview(header)
      stack.addArrangedSubview(body)
      disclosureBody = body
      disclosureButton = button
      disclosureTitle = title
    }
    update(node)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var isFlipped: Bool { true }
  func setInteractionEnabled(_ enabled: Bool) {
    interactionEnabled = enabled
    if let control = content as? NSControl { control.isEnabled = enabled }
    if let editor = (content as? NSScrollView)?.documentView as? NSTextView {
      editor.isEditable = enabled
    }
    disclosureButton?.isEnabled = enabled
    disclosureTitle?.textColor = enabled ? .labelColor : .disabledControlTextColor
    if let tabs = content as? NSTabView {
      tabs.setAccessibilityEnabled(enabled)
      tabs.alphaValue = enabled ? 1 : 0.5
      // Newer AppKit draws the header using a separate native control. Disable that
      // control too, so a refused switch cannot leave its pressed segment highlighted.
      func updateHeader(_ view: NSView) {
        guard !tabs.tabViewItems.contains(where: { $0.view === view }) else { return }
        if let control = view as? NSControl { control.isEnabled = enabled }
        for child in view.subviews { updateHeader(child) }
      }
      for child in tabs.subviews { updateHeader(child) }
    }
    table?.setInteractionEnabled(enabled)
    (content as? AppCanvas)?.setInteractionEnabled(enabled)
  }
  func update(_ next: NativeAppNode) {
    let previous = node.props
    node = next
    let props = node.props
    applying = true
    defer { applying = false }
    content.setAccessibilityLabel(props["label"].string ?? props["title"].string)
    content.setAccessibilityHelp(props["help"].string)
    content.toolTip = props["help"].string
    isHidden = props["hidden"] == .bool(true)
    if let control = content as? NSControl { control.isEnabled = props["enabled"] != .bool(false) }
    if dimensions.isEmpty || previous["width"] != props["width"]
      || previous["height"] != props["height"]
    {
      NSLayoutConstraint.deactivate(dimensions)
      dimensions = []
      for (key, anchor) in [("width", widthAnchor), ("height", heightAnchor)] {
        if let value = props[key].int, value > 0 {
          let constraint = anchor.constraint(equalToConstant: CGFloat(value))
          constraint.priority = .defaultHigh
          dimensions.append(constraint)
        }
      }
      if ["table", "textEditor", "canvas", "scroll", "tabs"].contains(node.type),
        props["height"] == .null
      {
        dimensions.append(
          heightAnchor.constraint(greaterThanOrEqualToConstant: node.type == "table" ? 260 : 160))
      }
      NSLayoutConstraint.activate(dimensions)
    }
    if let stack = content as? NSStackView {
      stack.spacing = CGFloat(props["gap"].int ?? 12)
      if stack.orientation == .horizontal {
        stack.alignment =
          props["alignment"].text == "bottom"
          ? .bottom : props["alignment"].text == "top" ? .top : .centerY
      } else {
        stack.alignment =
          props["alignment"].text == "center"
          ? .centerX : props["alignment"].text == "trailing" ? .trailing : .leading
      }
      let padding = CGFloat(max(0, props["padding"].int ?? 0))
      stack.edgeInsets = .init(top: padding, left: padding, bottom: padding, right: padding)
    }
    let accepted = (props["editRevision"].int ?? 0) >= inputRevision
    switch node.type {
    case "text":
      let label = content as! NSTextField
      label.stringValue = props["text"].text
      label.font = .systemFont(
        ofSize: CGFloat(min(72, max(9, props["size"].int ?? 13))),
        weight: props["weight"].text == "bold"
          ? .bold : props["weight"].text == "semibold" ? .semibold : .regular)
      label.isSelectable = props["selectable"] != .bool(false)
      label.textColor = AppCanvas.color(props["color"].text)
    case "button": (content as! NSButton).title = props["title"].text
    case "textField":
      let field = content as! NSTextField
      field.placeholderString = props["placeholder"].string ?? props["label"].string
      if accepted, field.stringValue != props["value"].text,
        (field.currentEditor() as? NSTextView)?.hasMarkedText() != true
      {
        field.stringValue = props["value"].text
      }
    case "textEditor":
      let editor = (content as! NSScrollView).documentView as! NSTextView
      if accepted, editor.string != props["value"].text, !editor.hasMarkedText() {
        let selection = editor.selectedRange()
        editor.string = props["value"].text
        editor.setSelectedRange(
          NSRange(location: min(selection.location, (editor.string as NSString).length), length: 0))
      }
      editor.isEditable = props["enabled"] != .bool(false)
    case "toggle":
      let button = content as! NSButton
      button.title = props["title"].text
      if accepted { button.state = props["value"] == .bool(true) ? .on : .off }
    case "picker":
      let picker = content as! NSPopUpButton
      let options = props["options"].array.map(\.text)
      if picker.itemTitles != options {
        picker.removeAllItems()
        picker.addItems(withTitles: options)
      }
      if accepted { picker.selectItem(withTitle: props["value"].text) }
    case "slider":
      let slider = content as! NSSlider
      slider.minValue = Double(props["min"].text) ?? 0
      slider.maxValue = max(slider.minValue, Double(props["max"].text) ?? 100)
      if accepted { slider.doubleValue = Double(props["value"].text) ?? 0 }
    case "date":
      if accepted, let date = ISO8601DateFormatter().date(from: props["value"].text) {
        (content as! NSDatePicker).dateValue = date
      }
    case "progress":
      let progress = content as! NSProgressIndicator
      progress.isIndeterminate = props["indeterminate"] == .bool(true)
      progress.minValue = 0
      progress.maxValue = 1
      progress.doubleValue = Double(props["value"].text) ?? 0
      if progress.isIndeterminate {
        progress.startAnimation(nil)
      } else {
        progress.stopAnimation(nil)
      }
    case "split": (content as! NSSplitView).isVertical = props["vertical"] != .bool(false)
    case "tabs":
      let tabs = content as! NSTabView
      if accepted, let index = props["value"].int, tabs.numberOfTabViewItems > index, index >= 0 {
        tabs.selectTabViewItem(at: index)
      }
    case "disclosure":
      disclosureTitle?.stringValue = props["title"].text
      disclosureButton?.setAccessibilityLabel(props["title"].text)
      if accepted, props["value"] != .null { disclosureOpen = props["value"] == .bool(true) }
      disclosureBody?.isHidden = !disclosureOpen
      disclosureButton?.state = disclosureOpen ? .on : .off
    case "canvas": (content as! AppCanvas).update(props)
    case "image":
      (content as! NSImageView).image = NSImage(
        systemSymbolName: props["symbol"].text, accessibilityDescription: props["label"].string)
    case "table": table?.update(next)
    default: break
    }
  }
  func arrange(_ children: [AppElement]) {
    let ids = children.map { $0.node.id }
    let signature =
      ids.joined(separator: ":") + node.props["padding"].text + node.props["columns"].text
      + node.props["titles"].text
      + children.map { $0.node.type + $0.node.props["width"].text }.joined(separator: ":")
    guard signature != arrangement else { return }
    arrangement = signature
    arranged = ids
    applying = true
    defer { applying = false }
    NSLayoutConstraint.deactivate(childConstraints)
    childConstraints = []
    if let stack = disclosureBody ?? content as? NSStackView {
      for view in stack.arrangedSubviews where !children.contains(where: { $0 === view }) {
        stack.removeArrangedSubview(view)
        view.removeFromSuperview()
      }
      if stack.orientation == .vertical {
        for child in children
        where child.node.props["width"] == .null && child.node.type != "button" {
          let constraint = child.widthAnchor.constraint(
            equalTo: stack.widthAnchor,
            constant: -CGFloat(max(0, node.props["padding"].int ?? 0) * 2))
          constraint.priority = .defaultHigh
          childConstraints.append(constraint)
        }
      }
      for (index, child) in children.enumerated() {
        if stack.arrangedSubviews.firstIndex(of: child) != index {
          if stack.arrangedSubviews.contains(child) { stack.removeArrangedSubview(child) }
          child.removeFromSuperview()
          stack.insertArrangedSubview(child, at: index)
        }
      }
      NSLayoutConstraint.activate(childConstraints)
    } else if let split = content as? NSSplitView {
      for view in split.arrangedSubviews { view.removeFromSuperview() }
      for child in children { split.addArrangedSubview(child) }
      split.adjustSubviews()
    } else if let tabs = content as? NSTabView {
      let previous = tabs.selectedTabViewItem?.identifier as? String
      for item in tabs.tabViewItems { tabs.removeTabViewItem(item) }
      for (index, child) in children.enumerated() {
        let item = NSTabViewItem(identifier: child.node.id)
        item.label =
          node.props["titles"].array.indices.contains(index)
          ? node.props["titles"].array[index].text : "Tab \(index + 1)"
        item.view = child
        tabs.addTabViewItem(item)
      }
      // Children must exist before applying the controlled initial selection.
      if let index = node.props["value"].int, tabs.tabViewItems.indices.contains(index) {
        tabs.selectTabViewItem(at: index)
      } else if let previous,
        let item = tabs.tabViewItems.first(where: { $0.identifier as? String == previous })
      {
        tabs.selectTabViewItem(item)
      }
    } else if let scroll = content as? NSScrollView, node.type == "scroll" {
      let stack = NSStackView(views: children)
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.translatesAutoresizingMaskIntoConstraints = false
      scroll.documentView = stack
      NSLayoutConstraint.activate([
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
      ])
    } else if let grid = content as? NSGridView {
      while grid.numberOfRows > 0 { grid.removeRow(at: 0) }
      while grid.numberOfColumns > 0 { grid.removeColumn(at: 0) }
      let count = max(1, min(12, node.props["columns"].int ?? 2))
      for offset in stride(from: 0, to: children.count, by: count) {
        grid.addRow(with: Array(children[offset..<min(children.count, offset + count)]))
      }
    }
  }
  private func changed(_ value: Value) {
    guard !applying, interactionEnabled else { return }
    inputRevision += 1
    session.event(node: node.id, handler: "onChange", value: value, editRevision: inputRevision)
  }
  @objc private func action() {
    switch node.type {
    case "button": session.event(node: node.id, handler: "onClick")
    case "toggle": changed(.bool((content as! NSButton).state == .on))
    case "picker": changed(.string((content as! NSPopUpButton).titleOfSelectedItem ?? ""))
    case "slider": changed(.number((content as! NSSlider).doubleValue))
    case "date":
      changed(.string(ISO8601DateFormatter().string(from: (content as! NSDatePicker).dateValue)))
    default: break
    }
  }
  @objc private func disclose() {
    guard interactionEnabled else { return }
    disclosureOpen.toggle()
    disclosureBody?.isHidden = !disclosureOpen
    changed(.bool(disclosureOpen))
  }
  func controlTextDidChange(_ notification: Notification) {
    let field = content as! NSTextField
    guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
    changed(.string(field.stringValue))
  }
  func textDidChange(_ notification: Notification) {
    guard let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
    changed(.string(editor.string))
  }
  func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
    guard let tabViewItem else { return }
    changed(.number(Double(tabView.indexOfTabViewItem(tabViewItem))))
  }
  func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool {
    guard applying || interactionEnabled else {
      // Accessibility can attempt a press on a disabled tab's native proxy.
      // Refresh AppKit's header from the retained selection after refusing it.
      tabView.needsLayout = true
      tabView.needsDisplay = true
      return false
    }
    return true
  }
}
