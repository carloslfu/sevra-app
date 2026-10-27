import CryptoKit
import Foundation
import SevraSplash

private final class ModelHTTPFixture: URLProtocol {
  static var files: [String: Data] = [:]
  static var mode = "normal"
  static var requests: [URLRequest] = []
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  private let stopping = SetupFlag()
  override func startLoading() {
    let mode = Self.mode
    Self.requests.append(request)
    let data = Self.files[request.url!.path] ?? Data()
    let offset =
      Int(request.value(forHTTPHeaderField: "Range")?.dropFirst(6).dropLast() ?? "0") ?? 0
    let partial = offset > 0 && !["ignore", "length"].contains(mode)
    var headers: [String: String] = [:]
    if partial {
      headers["Content-Range"] =
        "bytes \(mode == "range" ? offset + 1 : offset)-\(data.count - 1)/\(data.count)"
    }
    if mode == "length" { headers["Content-Length"] = "1" }
    let status = mode == "http" ? 503 : (partial ? 206 : 200)
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!,
      cacheStoragePolicy: .notAllowed)
    var body = partial ? data.dropFirst(offset) : data[...]
    if mode == "corrupt" { body = Data(repeating: 13, count: body.count)[...] }
    if mode == "oversize" { body.append(99) }
    if mode == "disconnect" {
      client?.urlProtocol(self, didLoad: Data(body.prefix(body.count / 2)))
      client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
      return
    }
    for start in stride(from: 0, to: body.count, by: 32768) {
      if stopping.value { return }
      client?.urlProtocol(self, didLoad: Data(body.dropFirst(start).prefix(32768)))
      if mode == "slow" { Thread.sleep(forTimeInterval: 0.01) }
    }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() { stopping.set() }
}

private final class SetupFlag: @unchecked Sendable {
  let lock = NSLock()
  var stored = false
  var value: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }
  func set() {
    lock.lock()
    stored = true
    lock.unlock()
  }
}

func checkNativeSetup() {
  func configuration() -> URLSessionConfiguration {
    let c = URLSessionConfiguration.ephemeral
    c.protocolClasses = [ModelHTTPFixture.self]
    return c
  }
  let bytes = Data((0..<(1024 * 1024)).map { UInt8(truncatingIfNeeded: $0) })
  let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  let url = URL(string: "https://fixture.example/weights")!
  func reset(_ mode: String) {
    ModelHTTPFixture.mode = mode
    ModelHTTPFixture.files = [url.path: bytes]
    ModelHTTPFixture.requests = []
  }
  func download(
    _ file: URL, cancelled: @escaping () -> Bool = { false },
    progress: @escaping (Int64) -> Void = { _ in }
  ) throws {
    try PinnedModelDownload.fetch(
      url, to: file, bytes: Int64(bytes.count), sha256: digest, configuration: configuration(),
      cancelled: cancelled, progress: progress)
  }
  test("native download resumes, verifies and reuses completed bytes without network") {
    let f = try ModelFixture()
    defer { f.remove() }
    let file = f.root.appendingPathComponent("partial")
    try bytes.prefix(65536).write(to: file)
    reset("normal")
    try download(file)
    try expect(
      ModelHTTPFixture.requests.first?.value(forHTTPHeaderField: "Range") == "bytes=65536-")
    try expect(try Data(contentsOf: file) == bytes)
    ModelHTTPFixture.requests = []
    try download(file)
    try expect(ModelHTTPFixture.requests.isEmpty)
  }
  test("ignored ranges restart, unexpected ranges and HTTP failures preserve partial bytes") {
    for mode in ["ignore", "range", "http", "length"] {
      let f = try ModelFixture()
      defer { f.remove() }
      let file = f.root.appendingPathComponent("partial")
      try bytes.prefix(65536).write(to: file)
      reset(mode)
      if mode == "ignore" {
        try download(file)
        try expect(try Data(contentsOf: file) == bytes)
      } else {
        try rejects { try download(file) }
        try expect(try Data(contentsOf: file) == bytes.prefix(65536))
      }
    }
  }
  test("corrupt, oversized and linked downloads cannot become a model") {
    for mode in ["corrupt", "oversize", "link", "hardlink"] {
      let f = try ModelFixture()
      defer { f.remove() }
      let file = f.root.appendingPathComponent("partial")
      reset(mode)
      if mode == "link" {
        try FileManager.default.createSymbolicLink(
          at: file, withDestinationURL: f.target.appendingPathComponent("config.json"))
      }
      if mode == "hardlink" {
        try FileManager.default.linkItem(
          at: f.target.appendingPathComponent("config.json"), to: file)
      }
      try rejects { try download(file) }
      if mode == "corrupt" { try expect(try Data(contentsOf: file).isEmpty) }
    }
    try expect(!PinnedModelDownload.permitted(URL(string: "http://example.com/file")!))
    try expect(
      !PinnedModelDownload.permitted(URL(string: "https://user:password@example.com/file")!))
  }
  test("interrupted and cancelled model transfers retain resumable partial bytes") {
    for mode in ["disconnect", "slow"] {
      let f = try ModelFixture()
      defer { f.remove() }
      let file = f.root.appendingPathComponent("partial")
      reset(mode)
      try bytes.prefix(4096).write(to: file)
      let flag = SetupFlag()
      try rejects {
        try download(file, cancelled: { flag.value }) { n in
          if mode == "slow" && n >= 65536 { flag.set() }
        }
      }
      let partial = try Data(contentsOf: file).count
      try expect(
        partial >= 4096 && partial <= bytes.count,
        "\(mode): retained \(partial) of \(bytes.count) bytes"
      )
      reset("normal")
      try download(file)
      if partial == bytes.count {
        try expect(ModelHTTPFixture.requests.isEmpty)
      } else {
        try expect(
          ModelHTTPFixture.requests.first?.value(forHTTPHeaderField: "Range") == "bytes=\(partial)-"
        )
      }
      try expect(try Data(contentsOf: file) == bytes)
    }
  }
  test("Swift setup downloads both synthetic packs and atomically prepares exact source identities")
  {
    let f = try ModelFixture()
    defer { f.remove() }
    reset("normal")
    ModelHTTPFixture.files = [:]
    for (source, folder) in [(f.pack.target, f.target), (f.pack.draft, f.draft)] {
      for file in source.files {
        ModelHTTPFixture.files["/\(source.repository)/resolve/\(source.revision)/\(file.path)"] =
          try Data(contentsOf: folder.appendingPathComponent(file.path))
      }
    }
    let assembly = try SplashModelSetup.install(
      pack: f.pack, modelsRoot: f.cache, configuration: configuration(),
      capacity: { _ in 1_000_000_000 })
    try expect(ModelHTTPFixture.requests.count == 6)
    let record =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: assembly.appendingPathComponent("model.json"))) as! [String: Any]
    let sources = record["sources"] as! [String: [String: Any]]
    try expect(sources["target"]?["revision"] as? String == f.pack.target.revision)
    try expect(sources["draft"]?["revision"] as? String == f.pack.draft.revision)
    ModelHTTPFixture.requests = []
    let again = try SplashModelSetup.install(
      pack: f.pack, modelsRoot: f.cache, configuration: configuration(),
      capacity: { _ in 1_000_000_000 })
    try expect(again == assembly && ModelHTTPFixture.requests.isEmpty)
  }
  test("storage and cancellation refusals preserve the previous usable selection") {
    let f = try ModelFixture()
    defer { f.remove() }
    let prior = try f.prepare()
    reset("normal")
    try rejects {
      _ = try SplashModelSetup.install(
        pack: f.pack, modelsRoot: f.cache, configuration: configuration(), capacity: { _ in 0 })
    }
    try rejects {
      _ = try SplashModelSetup.install(
        pack: f.pack, modelsRoot: f.cache, configuration: configuration(),
        capacity: { _ in 1_000_000_000 }, cancelled: { true })
    }
    try expect(ModelHTTPFixture.requests.isEmpty)
    try expect(
      try FileManager.default.destinationOfSymbolicLink(
        atPath: f.cache.appendingPathComponent(f.pack.name).path) == prior.path)
    _ = try SplashModelSetup.install(
      pack: f.pack, modelsRoot: f.cache, reusingTarget: f.target, reusingDraft: f.draft,
      configuration: configuration(), capacity: { _ in 1_000_000_000 })
    try expect(ModelHTTPFixture.requests.isEmpty)
  }
  test("native hardware preflight refuses unsupported chip and OS combinations") {
    try SplashModelSetup.validateHardware(
      chip: "Apple M5 Pro", os: .init(majorVersion: 26, minorVersion: 6, patchVersion: 2))
    for (chip, minor) in [("Apple M2 Max", 6), ("Apple M3", 3), ("Intel Core", 6)] {
      try rejects {
        try SplashModelSetup.validateHardware(
          chip: chip, os: .init(majorVersion: 26, minorVersion: minor, patchVersion: 0))
      }
    }
  }
  test("installed native selection reopens only exact pinned sources and verifies originals") {
    let f = try ModelFixture()
    defer { f.remove() }
    _ = try f.prepare()
    try rejects { _ = try SplashModelPreparation.installed(pack: f.pack, modelsRoot: f.cache) }
    let installed = try SplashModelSetup.install(
      pack: f.pack, modelsRoot: f.cache, reusingTarget: f.target, reusingDraft: f.draft,
      configuration: configuration(), capacity: { _ in 1_000_000_000 })
    let reopened = try SplashModelPreparation.installed(pack: f.pack, modelsRoot: f.cache)
    try expect(installed == reopened)
    try rejects {
      _ = try SplashModelPreparation.installed(
        pack: f.pack, modelsRoot: f.cache, cancelled: { true })
    }
    let original = f.target.appendingPathComponent("config.json")
    let bytes = try Data(contentsOf: original)
    try Data("corrupted".utf8).write(to: original)
    try rejects { _ = try SplashModelPreparation.installed(pack: f.pack, modelsRoot: f.cache) }
    try bytes.write(to: original)
    _ = try SplashModelPreparation.installed(pack: f.pack, modelsRoot: f.cache)
  }
  test("verifying an installed reused model does not download duplicate weights") {
    let f = try ModelFixture()
    defer { f.remove() }
    reset("normal")
    let first = try SplashModelSetup.install(
      pack: f.pack, modelsRoot: f.cache, reusingTarget: f.target, reusingDraft: f.draft,
      configuration: configuration(), capacity: { _ in 1_000_000_000 })
    let again = try SplashModelSetup.install(
      pack: f.pack, modelsRoot: f.cache, configuration: configuration(),
      capacity: { _ in 1_000_000_000 })
    try expect(first == again && ModelHTTPFixture.requests.isEmpty)
    let snapshots = f.cache.appendingPathComponent(".snapshots")
    try expect(try FileManager.default.contentsOfDirectory(atPath: snapshots.path).isEmpty)
  }
}
