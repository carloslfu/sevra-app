import Foundation
import SevraCore
import SwiftUI

@MainActor enum CatalogCoverage {
  static let limits = [
    "OS accessibility, VoiceOver, system appearance/contrast/motion and hardware are manual qualification.",
    "Scripted inference proves interface and transaction paths, not local-model task reliability.",
    "Declared app image views are unsupported; native Image aliases use the app's grant.",
    "View capture excludes separate sheets/popovers and may omit Quick Look/media layers. Use a dedicated window.",
    "Arbitrary generated programs and unbounded data arrangements are not a finite coverage set.",
  ]
  static func manifest() throws -> Value {
    .object([
      "schema": .string("sevra-ui-catalog-v1"), "fixtureRevision": .number(1),
      "limits": .array(limits.map(Value.string)),
      "stories": .array(
        try CatalogRegistry.stories.map { story in
          var fields = try encoded(story).object
          fields["actions"] = .array(story.actions.map(Value.string))
          fields["level"] = .string(story.level)
          fields["automatedInteraction"] = .bool(CatalogChecks.stories.contains(story.id))
          fields["readiness"] = .string(story.readiness)
          fields["statePolicy"] = .string(story.statePolicy)
          fields["evidence"] = .string("registered")
          fields["exclusions"] = .array(story.exclusions.map(Value.string))
          fields["configuration"] = try Value.parse(CatalogConfiguration(story: story.id).json())
          return .object(fields)
        }),
    ])
  }
}
struct CatalogCoverageView: View {
  let session: CatalogSession?
  let configuration: CatalogConfiguration
  @Environment(\.dismiss) var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Coverage and boundaries").font(.title2)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text(
        "Registration maps the product. Rendering, interaction checks and visual review are separate evidence for a configuration and build."
      ).foregroundStyle(.secondary)
      List {
        Section("Current configuration") {
          if let session {
            LabeledContent(
              session.story.id,
              value: session.failure != nil
                ? "Blocked: fixture failed"
                : session.rendered ? "Rendered" : "Missing render evidence")
            LabeledContent(
              "Interaction", value: session.interactionChecked ? "Checked" : "Missing evidence")
            LabeledContent(
              "Visual review",
              value: session.reviewIsCurrent(configuration)
                ? "Reviewed"
                : session.visualReviewed ? "Review belongs to an earlier state" : "Missing evidence"
            )
          }
        }
        ForEach(CatalogRegistry.groups, id: \.self) { group in
          Section(group) {
            ForEach(CatalogRegistry.stories.filter { $0.group == group }) { story in
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                  Text(story.title)
                  Text(story.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(story.variants.count) states · Registered").font(.caption).foregroundStyle(
                  .secondary)
              }
            }
          }
        }
        Section("Not applicable / manual qualification") {
          ForEach(CatalogCoverage.limits, id: \.self) { Text($0).font(.caption) }
        }
      }
    }.padding(24).frame(minWidth: 680, idealWidth: 850, minHeight: 600)
  }
}
