import AppKit
import SevraAutomationUI
import SevraCore
import SevraProduct

@MainActor final class NativeAutomationHost {
  static let shared = NativeAutomationHost()
  let controller: NativeAutomationController
  private var timer: Timer?
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var pressure: DispatchSourceMemoryPressure?
  private var busyOwners: Set<UUID> = []
  private var active = false
  private var systemSleeping = false
  private var screensSleeping = false
  private var sessionInactive = false
  private var memoryConstrained = false
  private var stopping = false
  private var terminating = false
  private init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[
      0
    ]
    .appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.sevra.native", isDirectory: true)
    .appendingPathComponent("DeviceSchedules", isDirectory: true)
    controller = NativeAutomationController(registry: .init(directory: support)) {
      book, session, control in
      let path =
        UserDefaults.standard.string(forKey: ProductAI.preferenceKey)
        .map { URL(fileURLWithPath: $0) } ?? ProductAI.defaultDirectory
      return try await ProductAI.shared.continueWorkflow(
        workbook: book, session: session, owner: "schedule:" + identifier(),
        modelDirectory: path, cancellation: control)
    }
  }
  func start() {
    guard timer == nil, !CommandLine.arguments.contains("--check-resources") else { return }
    let local = NotificationCenter.default
    let workspace = NSWorkspace.shared.notificationCenter
    observe(local, NSApplication.didBecomeActiveNotification) {
      $0.active = true
      $0.tick()
    }
    observe(local, NSApplication.didResignActiveNotification) {
      $0.active = false
      $0.tick()
    }
    observe(workspace, NSWorkspace.willSleepNotification) {
      $0.systemSleeping = true
      $0.tick()
    }
    observe(workspace, NSWorkspace.screensDidSleepNotification) {
      $0.screensSleeping = true
      $0.tick()
    }
    observe(workspace, NSWorkspace.didWakeNotification) {
      $0.systemSleeping = false
      $0.tick()
    }
    observe(workspace, NSWorkspace.screensDidWakeNotification) {
      $0.screensSleeping = false
      $0.tick()
    }
    observe(workspace, NSWorkspace.sessionDidResignActiveNotification) {
      $0.sessionInactive = true
      $0.tick()
    }
    observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) {
      $0.sessionInactive = false
      $0.tick()
    }
    observe(local, ProcessInfo.thermalStateDidChangeNotification) { $0.tick() }
    let pressure = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical], queue: .main)
    pressure.setEventHandler { [weak self, weak pressure] in
      Task { @MainActor in
        guard let self, let pressure else { return }
        self.memoryConstrained = !pressure.data.contains(.normal)
        self.tick()
      }
    }
    pressure.resume()
    self.pressure = pressure
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    Task { await controller.reload() }
  }
  private func observe(
    _ center: NotificationCenter, _ name: Notification.Name,
    _ receive: @escaping @MainActor (NativeAutomationHost) -> Void
  ) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { if let self { receive(self) } }
    }
    observers.append((center, token))
  }
  func setBusy(_ owner: UUID, _ busy: Bool) {
    if busy { busyOwners.insert(owner) } else { busyOwners.remove(owner) }
    if busy { controller.deferWork("Deferred for your current work.") }
  }
  func yieldForInteractive() async { await controller.quiesce("Deferred for your current work.") }
  func beginTermination() {
    terminating = true
    controller.deferWork("Sevra is saving before closing.")
  }
  func cancelTermination() {
    terminating = false
    tick()
  }
  func stop() async {
    stopping = true
    timer?.invalidate()
    timer = nil
    await controller.quiesce("Sevra is stopping. Work will resume when eligible after reopen.")
  }
  private func tick() {
    let reason: String?
    if stopping || terminating {
      reason = "Sevra is stopping."
    } else if !active || !NSApp.isActive {
      reason = "Paused while Sevra is inactive."
    } else if NSApp.keyWindow == nil {
      reason = "Paused while no Sevra window is active."
    } else if systemSleeping || screensSleeping || sessionInactive {
      reason = "Deferred while the screen or user session is inactive."
    } else if !busyOwners.isEmpty {
      reason = "Deferred for your current work."
    } else if memoryConstrained {
      reason = "Deferred while memory is constrained."
    } else if [.serious, .critical].contains(ProcessInfo.processInfo.thermalState) {
      reason = "Deferred while the Mac is hot."
    } else if ProcessInfo.processInfo.isLowPowerModeEnabled {
      reason = "Deferred in Low Power Mode."
    } else {
      reason = nil
    }
    controller.poll(deferral: reason)
  }
}
