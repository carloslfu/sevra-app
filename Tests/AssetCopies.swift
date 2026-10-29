import Foundation
import SevraCore

func checkAssetCopies(at root: URL) {
  check("external editing uses a verified independent copy of included or linked evidence") {
    let folder = root.appendingPathComponent("asset-copies")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let book = try Workbook.create(at: folder.appendingPathComponent("Copy.sevra"), title: "Copy")
    let original = folder.appendingPathComponent("original.txt")
    let bytes = Data("Original evidence, before external editing.".utf8)
    try bytes.write(to: original)
    for linked in [false, true] {
      let item = try book.importFile(original, linked: linked)
      let assetID = item.assetID!
      let revision = try book.revision()
      let copy = folder.appendingPathComponent(linked ? "linked copy.txt" : "included copy.txt")
      try expect(try book.copyAsset(assetID, to: copy) == copy)
      try expect(try Data(contentsOf: copy) == bytes)
      try Data("Changed in an external editor".utf8).write(to: copy)
      try expect(try Data(contentsOf: book.assetURL(assetID, verify: true)) == bytes)
      try expect(try Data(contentsOf: original) == bytes)
      try expect(try book.revision() == revision, "Copying changed the workbook")
      try refuses("file_exists") { try book.copyAsset(assetID, to: copy) }
      try expect(try String(contentsOf: copy, encoding: .utf8) == "Changed in an external editor")
    }
    let empty = folder.appendingPathComponent("empty.txt")
    try Data().write(to: empty)
    let source = try book.importFile(empty)
    let emptyCopy = folder.appendingPathComponent("empty copy.txt")
    try book.copyAsset(source.assetID!, to: emptyCopy)
    try expect(try Data(contentsOf: emptyCopy).isEmpty)
    _ = try book.verify()
  }

  check("cancelled or changed asset copies publish nothing and retain bounded progress") {
    let folder = root.appendingPathComponent("asset-copy-failures")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let book = try Workbook.create(at: folder.appendingPathComponent("Copy.sevra"), title: "Copy")
    let original = folder.appendingPathComponent("source.bin")
    try Data(repeating: 0x42, count: 3_145_728).write(to: original)
    let source = try book.importFile(original)
    let assetID = source.assetID!
    let saved = try book.assetURL(assetID)
    let revision = try book.revision()
    let destination = folder.appendingPathComponent("result.bin")
    let cancel = Cancellation()
    var progress: [Int64] = []
    try refuses("cancelled") {
      try book.copyAsset(assetID, to: destination, cancellation: cancel) { count, total in
        progress.append(count)
        if total == 3_145_728 { cancel.cancel() }
      }
    }
    try expect(progress == [1_048_576], "Stop read more than one copy chunk")
    try expect(!FileManager.default.fileExists(atPath: destination.path))
    try expect(
      try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
        $0.hasPrefix(".sevra-copy-")
      })
    // Same-length corruption must not be mistaken for the recorded original.
    try Data(repeating: 0x43, count: 3_145_728).write(to: saved)
    try refuses("changed_asset") { try book.copyAsset(assetID, to: destination) }
    try expect(!FileManager.default.fileExists(atPath: destination.path))
    try expect(
      try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
        $0.hasPrefix(".sevra-copy-")
      })
    try expect(try book.revision() == revision)
  }

  check("copy destinations cannot overwrite evidence, aliases or competing files") {
    let folder = root.appendingPathComponent("asset-copy-boundaries")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let book = try Workbook.create(at: folder.appendingPathComponent("Copy.sevra"), title: "Copy")
    let original = folder.appendingPathComponent("source.bin")
    try Data(repeating: 0x44, count: 2_097_152).write(to: original)
    let source = try book.importFile(original, linked: true)
    let id = source.assetID!
    try refuses("path") { try book.copyAsset(id, to: book.url.appendingPathComponent("extra.bin")) }
    let alias = folder.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: book.url)
    try refuses("path") { try book.copyAsset(id, to: alias.appendingPathComponent("extra.bin")) }
    let broken = folder.appendingPathComponent("broken")
    try FileManager.default.createSymbolicLink(
      at: broken, withDestinationURL: folder.appendingPathComponent("missing"))
    try refuses("file_exists") { try book.copyAsset(id, to: broken) }

    let target = folder.appendingPathComponent("race.bin")
    var created = false
    try refuses("file_exists") {
      try book.copyAsset(id, to: target) { _, _ in
        if !created {
          created = FileManager.default.createFile(
            atPath: target.path, contents: Data("Other writer".utf8))
        }
      }
    }
    let competingContent = try String(contentsOf: target, encoding: .utf8)
    try expect(created && competingContent == "Other writer")
    try expect(
      try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
        $0.hasPrefix(".sevra-copy-")
      })
    // A changed external reference is refused by the same streaming copy path.
    try Data("Changed linked original".utf8).write(to: original)
    let changed = folder.appendingPathComponent("changed.bin")
    try refuses("changed_asset") { try book.copyAsset(id, to: changed) }
    try expect(!FileManager.default.fileExists(atPath: changed.path))
  }
}
