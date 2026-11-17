import Foundation
import SevraCore
import SwiftUI

public struct VisualDiagramView: View {
  let definition: VisualDiagram
  let data: VisualDiagramData
  let openRecord: ((String) -> Void)?
  @State private var geometry: DiagramGeometry?
  @State private var selected: VisualDiagramData.Node?
  @State private var failed = false
  @State private var showRelationships = false
  @State private var zoom: Double? = nil
  @State private var relatedOnly = false

  public init(
    definition: VisualDiagram, data: VisualDiagramData, openRecord: ((String) -> Void)? = nil
  ) {
    self.definition = definition
    self.data = data
    self.openRecord = openRecord
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(definition.title).font(.headline).accessibilityAddTraits(.isHeader)
      if data.nodes.isEmpty {
        Text("No records match.").font(.callout).foregroundStyle(.secondary)
      } else {
        Text(
          "\(data.nodes.count) records · \(data.edges.count) relationships · \(data.componentCount) connected groups"
        )
        .font(.caption).foregroundStyle(.secondary)
        let cyclicNodes = data.cyclicNodes.count
        if cyclicNodes > 0 {
          Label(
            "\(cyclicNodes) records are part of a cycle.",
            systemImage: "arrow.trianglehead.clockwise"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        if let geometry {
          zoomControls
          GeometryReader { viewport in
            let scale =
              zoom
              ?? min(
                1,
                max(
                  0.15,
                  min(
                    viewport.size.width / geometry.width,
                    viewport.size.height / geometry.height)))
            ScrollView([.horizontal, .vertical]) {
              graph(geometry)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                  width: geometry.width * scale, height: geometry.height * scale,
                  alignment: .topLeading)
            }
          }.frame(height: min(315, max(120, geometry.height + 12)))
        } else if failed {
          Label(
            "The layout is unavailable. You can still inspect each relationship.",
            systemImage: "arrow.triangle.branch"
          )
          .font(.callout).foregroundStyle(.secondary)
        } else {
          ProgressView("Arranging relationships…")
        }
        if let selected, let openRecord {
          Button("Open " + selected.label) { openRecord(selected.source) }
            .buttonStyle(.link)
        }
        if selected != nil {
          Toggle("Selected record and its direct relationships", isOn: $relatedOnly)
            .font(.caption)
        }
        relationships
      }
    }
    .task(id: LayoutRequest(data: data, positions: definition.positions)) {
      geometry = nil
      selected = selected.flatMap { prior in data.nodes.first { $0.id == prior.id } }
      if selected == nil { relatedOnly = false }
      failed = false
      guard !data.nodes.isEmpty else { return }
      let cancellation = Cancellation()
      await withTaskCancellationHandler {
        do {
          let result = try await Task.detached { [data, positions = definition.positions] in
            try data.layout(positions: positions, cancellation: cancellation)
          }.value
          try Task.checkCancellation()
          geometry = result
        } catch {
          guard !Task.isCancelled else { return }
          failed = true
          showRelationships = true
        }
      } onCancel: {
        cancellation.cancel()
      }
    }
  }

  private struct LayoutRequest: Equatable {
    let data: VisualDiagramData
    let positions: [String: DiagramGeometry.Position]?
  }

  private var zoomControls: some View {
    HStack(spacing: 12) {
      Button("Fit") { zoom = nil }
      Button {
        zoom = max(0.25, (zoom ?? 1) / 1.25)
      } label: {
        Image(systemName: "minus.magnifyingglass")
      }
      .accessibilityLabel("Zoom out")
      Button {
        zoom = min(3, (zoom ?? 1) * 1.25)
      } label: {
        Image(systemName: "plus.magnifyingglass")
      }
      .accessibilityLabel("Zoom in")
      if let zoom { Text(zoom.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit() }
    }.buttonStyle(.borderless).font(.caption)
  }

  private var shownEdgeIndices: [Int] {
    guard relatedOnly, let selected else { return Array(data.edges.indices) }
    return data.edges.indices.filter {
      data.edges[$0].from == selected.id || data.edges[$0].to == selected.id
    }
  }

  private func graph(_ geometry: DiagramGeometry) -> some View {
    let edges = shownEdgeIndices
    let visibleNodes: Set<String>
    if relatedOnly, let selected {
      visibleNodes = Set(edges.flatMap { [data.edges[$0].from, data.edges[$0].to] }).union([
        selected.id
      ])
    } else {
      visibleNodes = Set(data.nodes.map(\.id))
    }
    return ZStack(alignment: .topLeading) {
      Canvas { context, _ in
        for index in edges {
          for vertices in geometry.edges[index] {
            var path = Path()
            path.addLines(vertices.map { CGPoint(x: $0.x, y: $0.y) })
            if let end = vertices.last, let previous = vertices.dropLast().last {
              let angle = atan2(end.y - previous.y, end.x - previous.x)
              path.move(
                to: CGPoint(
                  x: end.x - 9 * cos(angle - 0.42),
                  y: end.y - 9 * sin(angle - 0.42)))
              path.addLine(to: CGPoint(x: end.x, y: end.y))
              path.addLine(
                to: CGPoint(
                  x: end.x - 9 * cos(angle + 0.42),
                  y: end.y - 9 * sin(angle + 0.42)))
            }
            context.stroke(path, with: .color(.secondary), lineWidth: 1.2)
          }
        }
      }.accessibilityHidden(true).allowsHitTesting(false)
      ForEach(
        Array(data.nodes.enumerated()).filter { visibleNodes.contains($0.element.id) },
        id: \.element.id
      ) { index, node in
        let position = geometry.nodes[index]
        Button {
          selected = node
        } label: {
          Text(node.label).lineLimit(2).font(.callout).padding(.horizontal, 8)
            .frame(width: DiagramGeometry.nodeWidth - 6, height: DiagramGeometry.nodeHeight - 6)
            .background(
              selected?.id == node.id
                ? Color.accentColor.opacity(0.16)
                : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                  selected?.id == node.id ? Color.accentColor : Color.secondary.opacity(0.25))
            }
        }
        .buttonStyle(.plain).help(node.label).accessibilityLabel(node.label)
        .position(
          x: position.x + DiagramGeometry.nodeWidth / 2,
          y: position.y + DiagramGeometry.nodeHeight / 2)
      }
    }
    .frame(width: geometry.width, height: geometry.height)
  }

  private var relationships: some View {
    let labels = Dictionary(uniqueKeysWithValues: data.nodes.map { ($0.id, $0.label) })
    return DisclosureGroup("Relationships and sources", isExpanded: $showRelationships) {
      if data.edges.isEmpty {
        Text("There are no relationships in this view.").foregroundStyle(.secondary)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(shownEdgeIndices.map { data.edges[$0] }) { edge in
              let relationship =
                (labels[edge.from] ?? edge.from) + " → " + (labels[edge.to] ?? edge.to)
              if let openRecord {
                Button(relationship) { openRecord(edge.source) }.buttonStyle(.link)
              } else {
                Text(relationship)
              }
            }
          }.padding(.vertical, 6)
        }.frame(maxHeight: 220)
      }
    }.font(.callout)
  }
}

public struct LiveVisualDiagramView: View {
  let definition: VisualDiagram
  let revision: String
  let load: @MainActor () async throws -> VisualDiagramData
  let openRecord: ((String) -> Void)?
  @State private var result: VisualDiagramData?
  @State private var error: String?

  public init(
    definition: VisualDiagram, revision: String,
    load: @escaping @MainActor () async throws -> VisualDiagramData,
    openRecord: ((String) -> Void)? = nil
  ) {
    self.definition = definition
    self.revision = revision
    self.load = load
    self.openRecord = openRecord
  }

  public var body: some View {
    Group {
      if let error {
        Label(error, systemImage: "arrow.triangle.branch").font(.callout).foregroundStyle(
          .secondary)
      } else if let result {
        VisualDiagramView(definition: definition, data: result, openRecord: openRecord)
      } else {
        ProgressView("Loading relationships…")
      }
    }
    .task(id: revision + "/" + ((try? encoded(definition).json()) ?? "")) {
      result = nil
      error = nil
      do {
        let values = try await load()
        try Task.checkCancellation()
        result = values
      } catch {
        guard !Task.isCancelled else { return }
        self.error = error.localizedDescription
      }
    }
  }
}
