#if SEVRA_DISTRIBUTION
  import AppKit
  import Sparkle
  import SwiftUI

  @MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    private lazy var controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    func start() {
      controller.startUpdater()
      controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
      controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
    }

    func check() {
      let bundle = Bundle.main.bundleURL
      if (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true {
        let alert = NSAlert()
        alert.messageText = "Move Sevra to Applications"
        alert.informativeText =
          "Quit Sevra, drag it into Applications, then open the installed copy to check for updates."
        alert.runModal()
        return
      }
      controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
      controller.updater.automaticallyChecksForUpdates = enabled
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
      Bundle.main.object(forInfoDictionaryKey: "SevraDistributionStage") as? String == "early-access"
        ? ["early-access"] : []
    }
  }

  struct CheckForUpdatesCommand: View {
    @ObservedObject var updates: AppUpdates

    var body: some View {
      Button("Check for Updates…", action: updates.check).disabled(!updates.canCheck)
    }
  }

  struct DistributionSettings: View {
    @ObservedObject var updates: AppUpdates

    var body: some View {
      ModelSettingsView(
        automaticUpdateChecks: Binding(
          get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
    }
  }
#endif
