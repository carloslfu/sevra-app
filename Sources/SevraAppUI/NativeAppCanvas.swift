import AppKit
import SevraCore

@MainActor final class AppCanvas: NSView {
  private var props: Value = .null
  private var regions: [String: CanvasRegion] = [:]
  var event: ((String, NSPoint, String) -> Void)?
  private var selected: String?
  private var origin: NSPoint?
  private var delta = NSPoint.zero
  private var interactionEnabled = true
  func setInteractionEnabled(_ enabled: Bool) {
    interactionEnabled = enabled
    for region in regions.values { region.setAccessibilityEnabled(enabled) }
    if !enabled {
      origin = nil
      delta = .zero
      needsDisplay = true
    }
  }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  func update(_ value: Value) {
    props = value
    needsDisplay = true
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    let visible = Set(props["regions"].array.map { $0["id"].text })
    if let selected, !visible.contains(selected) {
      self.selected = nil
      origin = nil
      delta = .zero
    }
    regions = regions.filter { visible.contains($0.key) }
    let children = props["regions"].array.map { region in
      let id = region["id"].text
      let child = regions[id] ?? CanvasRegion()
      regions[id] = child
      child.setAccessibilityParent(self)
      child.setAccessibilityRole(.button)
      child.setAccessibilityEnabled(props["enabled"] != .bool(false))
      child.setAccessibilityLabel(region["label"].string ?? region["id"].text)
      child.setAccessibilityFrameInParentSpace(rect(region))
      child.press = { [weak self, weak child] in
        guard let self, let child, self.regions[id] === child,
          self.interactionEnabled, self.props["enabled"] != .bool(false)
        else {
          return false
        }
        self.selected = id
        self.window?.makeFirstResponder(self)
        self.event?(id, .zero, "click")
        return true
      }
      return child
    }
    setAccessibilityChildren(children)
  }
  static func color(_ name: String) -> NSColor {
    switch name {
    case "secondary": return .secondaryLabelColor
    case "accent": return .controlAccentColor
    case "green": return .systemGreen
    case "red": return .systemRed
    case "orange": return .systemOrange
    case "blue": return .systemBlue
    case "background": return .controlBackgroundColor
    case "separator": return .separatorColor
    default: return .labelColor
    }
  }
  private func number(_ value: Value, _ key: String) -> CGFloat {
    CGFloat(Double(value[key].text) ?? 0)
  }
  private func rect(_ value: Value) -> NSRect {
    NSRect(
      x: number(value, "x"), y: number(value, "y"), width: max(0, number(value, "width")),
      height: max(0, number(value, "height")))
  }
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    for shape in props["shapes"].array {
      NSGraphicsContext.saveGraphicsState()
      if shape["id"].text == selected, origin != nil {
        let transform = AffineTransform(translationByX: delta.x, byY: delta.y)
        (transform as NSAffineTransform).concat()
      }
      Self.color(shape["color"].text).set()
      switch shape["type"].text {
      case "rect": NSBezierPath(roundedRect: rect(shape), xRadius: 6, yRadius: 6).fill()
      case "circle": NSBezierPath(ovalIn: rect(shape)).fill()
      case "line":
        let path = NSBezierPath()
        path.move(to: .init(x: number(shape, "x"), y: number(shape, "y")))
        path.line(to: .init(x: number(shape, "x2"), y: number(shape, "y2")))
        path.stroke()
      case "text":
        (shape["text"].text as NSString).draw(
          at: .init(x: number(shape, "x"), y: number(shape, "y")),
          withAttributes: [
            .font: NSFont.systemFont(
              ofSize: max(9, min(72, number(shape, "size") == 0 ? 13 : number(shape, "size")))),
            .foregroundColor: Self.color(shape["color"].text),
          ])
      default: break
      }
      NSGraphicsContext.restoreGraphicsState()
    }
    if window?.firstResponder === self {
      NSColor.keyboardFocusIndicatorColor.set()
      NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2)).stroke()
    }
  }
  override func mouseDown(with event: NSEvent) {
    guard interactionEnabled, props["enabled"] != .bool(false) else { return }
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    selected =
      props["regions"].array.reversed().first(where: { rect($0).contains(point) })?["id"].string
    origin = point
    delta = .zero
    needsDisplay = true
  }
  override func mouseDragged(with event: NSEvent) {
    guard let origin else { return }
    let point = convert(event.locationInWindow, from: nil)
    delta = .init(x: point.x - origin.x, y: point.y - origin.y)
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    if interactionEnabled, props["enabled"] != .bool(false), let selected {
      self.event?(selected, delta, delta == .zero ? "click" : "end")
    }
    origin = nil
    delta = .zero
    needsDisplay = true
  }
  override func keyDown(with event: NSEvent) {
    guard interactionEnabled, props["enabled"] != .bool(false) else { return }
    guard let selected = selected ?? props["regions"].array.first?["id"].string else { return }
    switch event.keyCode {
    case 36, 49: self.event?(selected, .zero, "click")
    case 123: self.event?(selected, .init(x: -10, y: 0), "end")
    case 124: self.event?(selected, .init(x: 10, y: 0), "end")
    case 125: self.event?(selected, .init(x: 0, y: 10), "end")
    case 126: self.event?(selected, .init(x: 0, y: -10), "end")
    default: super.keyDown(with: event)
    }
  }
}
private final class CanvasRegion: NSAccessibilityElement {
  var press: (() -> Bool)?
  override func accessibilityPerformPress() -> Bool {
    press?() ?? false
  }
}
