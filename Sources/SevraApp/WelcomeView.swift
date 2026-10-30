import SwiftUI

struct WelcomeView: View {
  let startFromFiles: () -> Void
  let open: () -> Void
  let create: () -> Void
  let demo: () -> Void
  let openRecent: (String) -> Void
  @State private var recents = UserDefaults.standard.stringArray(forKey: "recentWorkbooks") ?? []
  @State private var showingAll = false

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 28) {
          VStack(spacing: 18) {
            HStack(spacing: 13) {
              ObserverMark().fill(.primary).frame(width: 70, height: 70)
              SevraWordmark().fill(.primary).frame(width: 189, height: 40)
            }.accessibilityElement(children: .ignore).accessibilityLabel("Sevra")
            Text("A workbook for the work in front of you.").font(.title2)
            Text(
              "Bring your files together. Ask questions, compare options, and build tables with the evidence at hand."
            )
            .foregroundStyle(.secondary).frame(maxWidth: 450)
          }.multilineTextAlignment(.center)
          VStack(spacing: 12) {
            HStack(spacing: 12) {
              Button("Start from files…", action: startFromFiles).buttonStyle(.borderedProminent)
                .controlSize(.large)
              Button("Open workbook…", action: open).controlSize(.large)
            }
            HStack(spacing: 18) {
              Button("Create blank…", action: create).buttonStyle(.link)
              Button("Try an example…", action: demo).buttonStyle(.link)
            }
          }
          if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("Recent workbooks").font(.headline)
              VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(recents.prefix(showingAll ? 10 : 5)), id: \.self) { path in
                  Button {
                    openRecent(path)
                  } label: {
                    HStack(spacing: 10) {
                      Image(systemName: "doc").foregroundStyle(.secondary)
                      Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                        .foregroundStyle(Color.primary).lineLimit(1).truncationMode(.middle)
                      Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.vertical, 5).contentShape(Rectangle())
                  }.buttonStyle(.borderless).help(path)
                }
              }
              if recents.count > 5 {
                Button(showingAll ? "Show fewer" : "Show all \(min(recents.count, 10))") {
                  showingAll.toggle()
                }.buttonStyle(.link)
              }
            }.frame(maxWidth: 360)
          }
          VStack(spacing: 10) {
            Text("Your work stays on this Mac.").font(.callout).foregroundStyle(.secondary)
            SettingsLink { Text("Local AI settings…") }
          }
        }.frame(maxWidth: 520).padding(32)
          .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
      }
    }.background(Color(nsColor: .windowBackgroundColor))
      .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) {
        _ in
        let saved = UserDefaults.standard.stringArray(forKey: "recentWorkbooks") ?? []
        if saved != recents { recents = saved }
      }
  }
}
