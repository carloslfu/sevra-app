import CryptoKit
import Foundation
import SevraSplash

func checkModelPreparation() {
  test("selected model has immutable target and matching draft pins") {
    let pack = try SplashModelPack.selected()
    try pack.validate()
    try expect(pack.target.files.count == 16 && pack.draft.files.count == 4)
    try expect(pack.target.revision == "38740b847e4cb78f352aba30aa41c76e08e6eb46")
    try expect(pack.draft.revision == "51ef7b6923ad6c14cb1bb41c37a9041446496ab6")
  }
  test("native assembly verifies, publishes atomically and reuses original bytes") {
    let f = try ModelFixture()
    defer { f.remove() }
    let one = try f.prepare()
    let two = try f.prepare()
    try expect(one == two)
    let record =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: one.appendingPathComponent("model.json"))) as! [String: Any]
    try expect(record["version"] as? Int == 1 && record["vision_format"] as? String == "none")
    let sources = record["sources"] as! [String: [String: Any]]
    try expect(sources["target"]!["revision"] is NSNull)
    try expect(sources["target"]!["repo"] as? String == f.target.path)
    try expect(
      try FileManager.default.destinationOfSymbolicLink(
        atPath: one.appendingPathComponent("target/weights.safetensors").path)
        == f.target.appendingPathComponent("weights.safetensors").path)
    try expect(
      try Data(contentsOf: one.appendingPathComponent("target/weights.safetensors"))
        == Data("synthetic target weights".utf8))
    let full = try SplashModelPreparation.prepare(
      pack: f.pack, target: f.target, draft: f.draft,
      modelsRoot: f.cache, fullVerification: true)
    try expect(full == one)
  }
  test("changed, missing and linked bytes refuse without replacing a prior selection") {
    for mode in ["changed", "missing", "link"] {
      let f = try ModelFixture()
      defer { f.remove() }
      let good = try f.prepare()
      let file = f.target.appendingPathComponent("weights.safetensors")
      if mode == "changed" {
        try Data(repeating: 65, count: 24).write(to: file)
      } else {
        try FileManager.default.removeItem(at: file)
        if mode == "link" {
          let alternate = f.root.appendingPathComponent("elsewhere")
          try Data("synthetic target weights".utf8).write(to: alternate)
          try FileManager.default.createSymbolicLink(at: file, withDestinationURL: alternate)
        }
      }
      try rejects { _ = try f.prepare() }
      try expect(
        try FileManager.default.destinationOfSymbolicLink(
          atPath: f.cache.appendingPathComponent(f.pack.name).path) == good.path)
    }
  }
  test("cancelled preparation publishes nothing and preserves source data") {
    let f = try ModelFixture()
    defer { f.remove() }
    try rejects {
      _ = try SplashModelPreparation.prepare(
        pack: f.pack, target: f.target,
        draft: f.draft, modelsRoot: f.cache, cancelled: { true })
    }
    try expect(
      !FileManager.default.fileExists(atPath: f.cache.appendingPathComponent(f.pack.name).path))
    try expect(
      try Data(contentsOf: f.target.appendingPathComponent("weights.safetensors"))
        == Data("synthetic target weights".utf8))
  }
  test("damaged assemblies and real files at selection paths are preserved and refused") {
    for mode in ["record", "extra", "selection"] {
      let f = try ModelFixture()
      defer { f.remove() }
      if mode == "selection" {
        try FileManager.default.createDirectory(at: f.cache, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: f.cache.appendingPathComponent(f.pack.name))
      } else {
        let assembly = try f.prepare()
        if mode == "record" {
          try Data("{}".utf8).write(to: assembly.appendingPathComponent("model.json"))
        } else {
          try Data("unexpected".utf8).write(
            to: assembly.appendingPathComponent("target/extra.safetensors"))
        }
      }
      try rejects { _ = try f.prepare() }
      if mode == "selection" {
        try expect(
          try String(contentsOf: f.cache.appendingPathComponent(f.pack.name), encoding: .utf8)
            == "keep me")
      }
    }
  }
  test("unsafe and duplicated manifest paths are rejected") {
    let f = try ModelFixture()
    defer { f.remove() }
    for wrong in [
      "../escape", "/absolute", "target//double", "model.json", "target/weights.safetensors",
    ] {
      var json = f.json
      var source = json["draft"] as! [String: Any]
      var files = source["files"] as! [[String: Any]]
      files[0]["destinations"] = [wrong]
      source["files"] = files
      json["draft"] = source
      let pack = try JSONDecoder().decode(
        SplashModelPack.self, from: JSONSerialization.data(withJSONObject: json))
      try rejects { try pack.validate() }
    }
  }
}

struct ModelFixture {
  let root: URL, target: URL, draft: URL, cache: URL
  let json: [String: Any]
  let pack: SplashModelPack
  init() throws {
    root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
      "sevra-model-" + UUID().uuidString)
    target = root.appendingPathComponent("target")
    draft = root.appendingPathComponent("draft")
    cache = root.appendingPathComponent("models")
    for dir in [target, draft] {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    func file(_ directory: URL, _ name: String, _ text: String, _ paths: [String]) throws
      -> [String: Any]
    {
      let bytes = Data(text.utf8)
      try bytes.write(to: directory.appendingPathComponent(name))
      return [
        "path": name, "bytes": bytes.count, "destinations": paths,
        "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      ]
    }
    let targetFiles = try [
      file(
        target, "config.json", "{\"family\":\"test\"}",
        ["config.json", "target/config.json", "tokenizer/config.json"]),
      file(target, "tokenizer.json", "{}", ["tokenizer/tokenizer.json"]),
      file(target, "tokenizer_config.json", "{}", ["tokenizer/tokenizer_config.json"]),
      file(
        target, "weights.safetensors", "synthetic target weights", ["target/weights.safetensors"]),
    ]
    let draftFiles = try [
      file(draft, "config.json", "{}", ["draft/config.json"]),
      file(draft, "weights.safetensors", "synthetic draft weights", ["draft/weights.safetensors"]),
    ]
    json = [
      "schemaVersion": 1, "name": "test-model", "family": "Test",
      "target": [
        "repository": "test/target", "revision": String(repeating: "a", count: 40),
        "files": targetFiles,
      ],
      "draft": [
        "repository": "test/draft", "revision": String(repeating: "b", count: 40),
        "files": draftFiles,
      ],
    ]
    pack = try JSONDecoder().decode(
      SplashModelPack.self, from: JSONSerialization.data(withJSONObject: json))
  }
  func prepare() throws -> URL {
    try SplashModelPreparation.prepare(pack: pack, target: target, draft: draft, modelsRoot: cache)
  }
  func remove() { try? FileManager.default.removeItem(at: root) }
}
