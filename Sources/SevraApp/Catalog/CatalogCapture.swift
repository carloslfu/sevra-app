import AppKit
import SevraCore
import SevraTableUI
import SwiftUI

@MainActor enum CatalogCapture {
  static var windows: [ObjectIdentifier: NSWindow] = [:]
  @discardableResult static func openWindow(
    _ session: CatalogSession, width: Double, height: Double, dark: Bool
  )
    -> NSWindow
  {
    if let previous = windows[ObjectIdentifier(session)] { previous.close() }
    let window = NSWindow(
      contentRect: NSRect(
        x: 0, y: 0, width: max(width, session.minimumCanvasWidth), height: height),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = session.story.title + " · Synthetic catalog"
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: session.minimumCanvasWidth, height: 320)
    window.contentView = NSHostingView(
      rootView: CatalogStage(session: session).defaultAppStorage(session.defaults).readingFont(
        .body
      ).background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(dark ? .dark : .light))
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.center()
    window.makeKeyAndOrderFront(nil)
    windows[ObjectIdentifier(session)] = window
    return window
  }
  static func close(_ session: CatalogSession) {
    if let window = windows.removeValue(forKey: ObjectIdentifier(session)) {
      window.contentView = nil
      window.close()
    }
  }
  static func waitUntilReady(_ session: CatalogSession) async throws {
    try require(
      session.ready && session.failure == nil, "catalog_capture",
      session.failure ?? "Example is not ready.")
    if let app = session.app, let book = session.book, let state = session.state {
      let host = state.nativeAppSession(app, book: book)
      let deadline = Date().addingTimeInterval(10)
      while host.status == "starting" && session.story.id != "mini.state.starting"
        && Date() < deadline
      {
        try Task.checkCancellation()
        try await Task.sleep(for: .milliseconds(20))
      }
      try require(
        host.status != "starting" || session.story.id == "mini.state.starting", "catalog_capture",
        "App did not settle before capture.")
    }
    // Let layout and child .task publications drain. This is layout quiescence,
    // after workbook/worker readiness, not a substitute for those state checks.
    for _ in 0..<4 {
      await Task.yield()
      try await Task.sleep(for: .milliseconds(30))
    }
  }
  @discardableResult static func capture(
    _ session: CatalogSession, configuration: CatalogConfiguration, output: URL? = nil
  ) async throws -> URL {
    try configuration.validate()
    session.defaults.set(configuration.readingScale, forKey: ReadingStyle.preference)
    let window = openWindow(
      session, width: configuration.width, height: configuration.height, dark: configuration.dark)
    try await waitUntilReady(session)
    guard let host = window.contentView else {
      throw SevraError("catalog_capture", "No mounted canvas")
    }
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
      throw SevraError("catalog_capture", "Cannot allocate bitmap")
    }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]), data.count > 1000 else {
      throw SevraError("catalog_capture", "Empty canvas bitmap")
    }
    let dir =
      output ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("captures")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stem =
      session.story.id + "-" + session.variant.lowercased().replacingOccurrences(of: " ", with: "-")
      + (configuration.dark ? "-dark" : "-light")
    let file = dir.appendingPathComponent(stem + ".png")
    try data.write(to: file)
    let bundle = Bundle.main
    let receipt: Value = .object([
      "configuration": try Value.parse(configuration.json()), "fixtureRevision": .number(1),
      "points": .array([.number(host.bounds.width), .number(host.bounds.height)]),
      "pixels": .array([.number(Double(bitmap.pixelsWide)), .number(Double(bitmap.pixelsHigh))]),
      "backingScale": .number(window.backingScaleFactor),
      "os": .string(ProcessInfo.processInfo.operatingSystemVersionString),
      "sdk": .string(bundle.object(forInfoDictionaryKey: "CatalogSDK") as? String ?? "unknown"),
      "locale": .string(Locale.current.identifier),
      "timeZone": .string(TimeZone.current.identifier),
      "build": .string(
        bundle.object(forInfoDictionaryKey: "CatalogSourceCommit") as? String ?? "unknown"),
      "binaryIdentity": .string(
        bundle.object(forInfoDictionaryKey: "CatalogBinaryIdentity") as? String ?? "unknown"),
      "dirty": .bool(bundle.object(forInfoDictionaryKey: "CatalogDirty") as? Bool ?? true),
      "serviceMode": .string(
        "real workbook/XPC; scripted inference; controlled file/model/voice/scheduler services"),
      "evidence": .object([
        "registered": .bool(true), "rendered": .bool(true),
        "interactionChecked": .bool(session.interactionChecked),
        "visualReviewed": .bool(session.reviewIsCurrent(configuration)),
      ]),
      "readiness": .string(
        session.story.id == "mini.state.starting"
          ? "intentional controlled starting state"
          : "workbook hydrated; worker settled; native canvas mounted"),
      "visualReviewNote": .string(session.visualReviewNote),
      "workbookID": .string(session.book!.id),
      "events": .array(session.events.map(Value.string)),
      "hostEvents": .array(AppHost.events.map(Value.string)),
      "hostEventsScope": .string("Catalog process; may include multiple fixtures"),
      "captureLimit": .string(
        "Separate sheets/popovers, Quick Look and media layers require live-window review; rendering is not visual approval."
      ),
    ])
    try receipt.json().write(
      to: dir.appendingPathComponent(stem + ".json"), atomically: true, encoding: .utf8)
    try configuration.json().write(
      to: dir.appendingPathComponent(stem + ".config.json"), atomically: true, encoding: .utf8)
    session.events.append("Captured " + file.lastPathComponent)
    return file
  }
}
@MainActor enum CatalogCLI {
  static var isBatch: Bool {
    ["--list", "--check", "--check-flows", "--capture", "--validate-fixtures"].contains(
      where: CommandLine.arguments.contains)
  }
  static func value(_ flag: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: flag), i + 1 < CommandLine.arguments.count
    else { return nil }
    return CommandLine.arguments[i + 1]
  }
  static func configuration() throws -> CatalogConfiguration {
    var c =
      try value("--config").map {
        try JSONDecoder().decode(
          CatalogConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
      } ?? CatalogConfiguration()
    if let id = value("--capture") ?? value("--story") { c.story = id }
    if let variant = value("--variant") { c.variant = variant }
    if let width = value("--width") {
      guard let n = Double(width) else {
        throw SevraError("catalog_config", "Canvas width must be numeric")
      }
      c.width = n
    }
    if let height = value("--height") {
      guard let n = Double(height) else {
        throw SevraError("catalog_config", "Canvas height must be numeric")
      }
      c.height = n
    }
    if let reading = value("--reading") {
      guard let n = Double(reading) else {
        throw SevraError("catalog_config", "Reading size must be numeric")
      }
      c.readingScale = n
    }
    if CommandLine.arguments.contains("--dark") { c.dark = true }
    try c.validate()
    return c
  }
  static func run() async {
    setbuf(stdout, nil)
    do {
      try CatalogRegistry.validate()
      if CommandLine.arguments.contains("--list") {
        print(try CatalogCoverage.manifest().json())
        finish(0)
      }
      let base = try configuration()
      let validate = CommandLine.arguments.contains("--validate-fixtures")
      let check = CommandLine.arguments.contains("--check")
      let flows = CommandLine.arguments.contains("--check-flows")
      let ids =
        validate
        ? CatalogRegistry.stories.map(\.id)
        : flows
          ? CatalogRegistry.stories.filter { $0.group == "Compositions" }.map(\.id)
          : check ? CatalogChecks.stories : [base.story]
      if let from = value("--from") {
        try require(ids.contains(from), "catalog_story", "Unknown resume story")
      }
      guard let steps = Int(value("--steps") ?? "0"), (0...10).contains(steps) else {
        throw SevraError("catalog_config", "Use 0–10 replay steps")
      }
      var completed = 0
      for id in ids.drop(while: { value("--from") != nil && $0 != value("--from")! }) {
        var c = base
        c.story = id
        if check || validate { c.variant = "Default" }
        let story = CatalogRegistry.stories.first { $0.id == id }!
        let session = CatalogSession(
          story: story, variant: c.variant, label: c.label, count: c.rows, spacing: c.spacing,
          columns: c.columns, vertical: c.vertical)
        defer {
          CatalogCapture.close(session)
          session.stop()
        }
        await session.prepare()
        guard session.ready else {
          session.stop()
          throw SevraError("catalog_check", id + ": " + (session.failure ?? "not ready"))
        }
        _ = CatalogCapture.openWindow(session, width: c.width, height: c.height, dark: c.dark)
        try await CatalogCapture.waitUntilReady(session)
        try await session.validateFixture()
        for _ in 0..<(flows ? session.flowSteps.count : steps) { await session.replay() }
        try require(session.failure == nil, "catalog_flow", session.failure ?? "")
        if flows {
          try require(
            session.step == session.flowSteps.count, "catalog_flow",
            "Replay ended before all declared steps")
          session.interactionChecked = true
        }
        if check { try await CatalogChecks.verify(session) }
        if !validate {
          _ = try await CatalogCapture.capture(
            session, configuration: c, output: value("--output").map { URL(fileURLWithPath: $0) })
        }
        CatalogCapture.close(session)
        await session.tearDown()
        print("PASS " + id)
        completed += 1
      }
      print("CATALOG_DONE \(completed)")
      finish(0)
    } catch {
      fputs("\(error)\n", stderr)
      finish(1)
    }
  }
  static func finish(_ code: Int32) -> Never {
    try? FileManager.default.removeItem(at: AppHost.root)
    fflush(stdout)
    exit(code)
  }
}
