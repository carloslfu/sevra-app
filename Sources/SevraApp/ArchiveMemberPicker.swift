import SevraCore
import SwiftUI

struct ArchiveMemberPicker: View {
  let source: Item
  @ObservedObject var state: WorkspaceState
  @Environment(\.dismiss) private var dismiss
  @State private var members: [ArchiveMember] = []
  @State private var selected = Set<String>()
  @State private var error: String?
  @State private var loading = true
  var total: UInt64 {
    members.filter { selected.contains($0.path) }.reduce(0) { total, member in
      let sum = total.addingReportingOverflow(member.bytes)
      return sum.overflow ? UInt64.max : sum.partialValue
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Choose files from " + source.title).font(.title2)
      Text("The ZIP stays in your workbook. Include up to 50 files and 1 GB per selection.")
        .foregroundStyle(.secondary)
      if loading { ProgressView("Reading file list") }
      if let error { Text(error).foregroundStyle(.red) }
      List(members) { member in
        Toggle(
          isOn: Binding(
            get: { selected.contains(member.path) },
            set: { value in
              if value { selected.insert(member.path) } else { selected.remove(member.path) }
            })
        ) {
          HStack {
            Text(member.path).lineLimit(2)
            Spacer()
            Text(
              ByteCountFormatter.string(
                fromByteCount: Int64(clamping: member.bytes), countStyle: .file)
            ).foregroundStyle(.secondary)
          }
        }
      }
      HStack {
        Text(
          "\(selected.count) selected · "
            + ByteCountFormatter.string(fromByteCount: Int64(clamping: total), countStyle: .file)
        ).font(.caption)
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Include selected") {
          let paths = selected.sorted()
          state.run("Including selected files") { book, cancel in
            _ = try book.includeArchiveMembers(source.id, paths: paths, cancellation: cancel)
          }
          dismiss()
        }.keyboardShortcut(.defaultAction).disabled(
          selected.isEmpty || selected.count > 50 || total > 1_000_000_000 || state.busy)
      }
    }.padding(22).frame(width: 620, height: 460).task {
      do {
        if let book = state.workbook {
          members = try await Task.detached { try book.archiveMembers(source.id) }.value
        }
      } catch { self.error = error.localizedDescription }
      loading = false
    }
  }
}
