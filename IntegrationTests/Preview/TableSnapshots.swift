import AppKit
import Foundation
import SevraCore
import SevraPreviewUI
import SwiftUI

/// Offscreen component snapshots for visual review when screen capture of the
/// installed app is unavailable. Each Markdown answer is composed like a
/// conversation message; each CSV/TSV uses the original-file grid. This renders
/// the shipped components, not the installed application window.
@MainActor func renderTableSnapshots(in directory: URL) throws {
  let files = try FileManager.default.contentsOfDirectory(
    at: directory, includingPropertiesForKeys: nil
  ).sorted { $0.lastPathComponent < $1.lastPathComponent }
  try require(!files.isEmpty, "arguments", "Add .md answers or .csv/.tsv originals to render.")
  func grids(_ view: NSView) -> [NSTableView] {
    (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(grids)
  }
  func render<V: View>(_ view: V, width: CGFloat, dark: Bool, name: String) throws {
    let host = NSHostingView(
      rootView: view.frame(width: width, alignment: .leading).padding(16)
        .background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width + 32, height: 900), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = host
    for _ in 0..<3 {
      host.layoutSubtreeIfNeeded()
      window.setContentSize(host.fittingSize)
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      throw SevraError("snapshot", "Could not allocate the snapshot bitmap.")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      throw SevraError("snapshot", "Could not encode the snapshot.")
    }
    try png.write(to: directory.appendingPathComponent(name + ".png"))
    for (index, grid) in grids(host).enumerated() {
      let visible = grid.enclosingScrollView?.contentView.bounds ?? .zero
      let columns = grid.tableColumns.reduce(0) { $0 + $1.width }
      let rows = (0..<grid.numberOfRows).reduce(0) {
        $0 + grid.rect(ofRow: $1).height
      }
      let cell = grid.numberOfRows > 0 ? grid.view(atColumn: 0, row: 0, makeIfNecessary: true) : nil
      print("\(name) first cell \(Int(cell?.frame.width ?? 0)) in column \(Int(grid.tableColumns.first?.width ?? 0))")
      let first = grid.numberOfColumns > 0 ? grid.rect(ofColumn: 0) : .zero
      let spacing = first.width - (grid.tableColumns.first?.width ?? 0)
      let extent = grid.numberOfColumns > 0 ? grid.rect(ofColumn: grid.numberOfColumns - 1).maxX : 0
      print(
        "\(name) grid \(index + 1): \(grid.numberOfColumns) columns, \(grid.numberOfRows) rows, columns \(Int(columns)) (inset \(Int(first.minX)), spacing \(Int(spacing)), extent \(Int(extent))) of visible \(Int(visible.width)), rows \(Int(rows)) + header \(Int(grid.headerView?.frame.height ?? 0)) in visible \(Int(visible.height)), host \(Int(host.bounds.width))x\(Int(host.bounds.height))"
      )
    }
  }
  for file in files {
    let stem = file.deletingPathExtension().lastPathComponent
    switch file.pathExtension.lowercased() {
    case "md":
      let presentation = ConversationPresentation(try String(contentsOf: file, encoding: .utf8))
      let message = VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(presentation.blocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text(ConversationPresentation(text.trimmingCharacters(in: .newlines)).text)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
          case .table(let table):
            ReadOnlyTableView(content: table, label: "Comparison table", inline: true)
          }
        }
      }
      for (suffix, width, dark) in [
        ("narrow", 340.0, false), ("medium", 560.0, false), ("wide", 900.0, false),
        ("narrow-dark", 340.0, true),
      ] {
        try render(message, width: width, dark: dark, name: stem + "-" + suffix)
      }
    case "csv", "tsv":
      let preview = try DelimitedPreview.load(file)
      let viewer = VStack(alignment: .leading, spacing: 10) {
        Text(preview.detail).font(.caption).foregroundStyle(.secondary)
        ReadOnlyTableView(content: preview.table, label: "Original table values")
          .frame(height: 420)
      }
      for (suffix, width, dark) in [("window", 900.0, false), ("compact-dark", 520.0, true)] {
        try render(viewer, width: width, dark: dark, name: stem + "-" + suffix)
      }
    default: continue
    }
  }
}
