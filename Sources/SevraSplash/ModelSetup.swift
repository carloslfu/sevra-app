import Darwin
import Foundation

/// The candidate's setup service, independent of Python, MLX and Slotstream.
/// Run off the main actor; cancellation must be safe to read from this worker.
public enum SplashModelSetup {
  public struct Progress {
    public let phase: String
    public let file: String
    public let completedBytes: Int64
    public let totalBytes: Int64
  }

  public static func install(
    modelsRoot: URL, reusingTarget: URL? = nil, reusingDraft: URL? = nil,
    cancelled: @escaping () -> Bool = { false }, progress: @escaping (Progress) -> Void = { _ in }
  ) throws -> URL {
    try checkHardware()
    return try install(
      pack: .selected(), modelsRoot: modelsRoot, reusingTarget: reusingTarget,
      reusingDraft: reusingDraft, cancelled: cancelled, progress: progress)
  }

  public static func checkHardware() throws {
    var size = 0
    guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0, size < 1024
    else {
      throw SplashError("Cannot identify this Mac for native Splash setup")
    }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else {
      throw SplashError("Cannot identify this Mac for native Splash setup")
    }
    try validateHardware(
      chip: String(cString: bytes), os: ProcessInfo.processInfo.operatingSystemVersion)
  }
  package static func validateHardware(chip: String, os: OperatingSystemVersion) throws {
    let prefix = "Apple M"
    let generation =
      chip.hasPrefix(prefix)
      ? Int(chip.dropFirst(prefix.count).prefix(while: { $0.isNumber })) : nil
    guard let generation, generation >= 3,
      os.majorVersion > 26 || (os.majorVersion == 26 && os.minorVersion >= 4)
    else {
      throw SplashError(
        "The native Splash candidate requires an Apple M3 or newer Mac and macOS 26.4 or newer")
    }
  }

  package static func install(
    pack: SplashModelPack, modelsRoot: URL, reusingTarget: URL? = nil, reusingDraft: URL? = nil,
    configuration: URLSessionConfiguration = .ephemeral,
    capacity: (URL) throws -> Int64 = availableCapacity,
    cancelled: @escaping () -> Bool = { false }, progress: @escaping (Progress) -> Void = { _ in }
  ) throws -> URL {
    try pack.validate()
    if cancelled() { throw SplashError("Model setup cancelled") }
    let fm = FileManager.default
    try fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
    let root = modelsRoot.standardizedFileURL.resolvingSymlinksInPath()
    let lock = try ModelFileLock(
      root.appendingPathComponent(".sevra-download.lock"), cancelled: cancelled)
    defer { lock.unlock() }
    // A previously reused pack is already an installation. Verify it in place
    // instead of downloading a second 21 GB copy when the user clicks Verify.
    if reusingTarget == nil && reusingDraft == nil,
      fm.fileExists(atPath: root.appendingPathComponent(pack.name + "/model.json").path)
    {
      progress(
        .init(phase: "Checking existing model", file: pack.name, completedBytes: 0, totalBytes: 0))
      do {
        return try SplashModelPreparation.installed(
          pack: pack, modelsRoot: root, fullVerification: true, cancelled: cancelled
        ) { state in
          progress(
            .init(
              phase: "Verifying", file: state.file, completedBytes: state.verifiedBytes,
              totalBytes: state.totalBytes))
        }
      } catch let error as SplashError where error.repairable {
        if cancelled() { throw SplashError("Model setup cancelled") }
        // A missing or changed original can be repaired into managed snapshots, and only that
        // starts a 21 GB download. Keep its old selection until the replacement verifies.
      }
    }
    let snapshots = root.appendingPathComponent(".snapshots")
    try directory(snapshots)
    var directories: [URL] = []
    var missing: Int64 = 0
    for (source, reuse) in [(pack.target, reusingTarget), (pack.draft, reusingDraft)] {
      if let reuse {
        directories.append(reuse)
        continue
      }
      let folder = snapshots.appendingPathComponent(
        source.repository.replacingOccurrences(of: "/", with: "--") + "-" + source.revision)
      try directory(folder)
      directories.append(folder)
      for file in source.files where !file.destinations.isEmpty {
        var st = stat()
        let path = folder.appendingPathComponent(file.path).path
        if lstat(path, &st) == 0 {
          guard st.st_mode & S_IFMT == S_IFREG, st.st_nlink == 1, st.st_size <= file.bytes else {
            throw SplashError("Unsafe partial model snapshot")
          }
          missing += file.bytes - st.st_size
        } else if errno == ENOENT {
          missing += file.bytes
        } else {
          throw SplashError("Cannot inspect model snapshot")
        }
      }
    }
    let reserve: Int64 = 256 * 1024 * 1024
    guard try capacity(root) >= missing + reserve else {
      throw SplashError(
        "Model setup needs \(missing + reserve) bytes of free space, including its working reserve")
    }
    for (index, source) in [pack.target, pack.draft].enumerated() {
      if (index == 0 ? reusingTarget : reusingDraft) != nil { continue }
      for file in source.files where !file.destinations.isEmpty {
        if cancelled() { throw SplashError("Model setup cancelled") }
        guard
          try capacity(root) >= file.bytes
            - size(directories[index].appendingPathComponent(file.path)) + reserve
        else {
          throw SplashError("Free space changed during model setup; retry after freeing space")
        }
        let url = URL(string: "https://huggingface.co")!.appendingPathComponent(source.repository)
          .appendingPathComponent("resolve").appendingPathComponent(source.revision)
          .appendingPathComponent(file.path)
        progress(
          .init(
            phase: "Downloading or verifying", file: file.path, completedBytes: 0,
            totalBytes: file.bytes))
        try PinnedModelDownload.fetch(
          url, to: directories[index].appendingPathComponent(file.path), bytes: file.bytes,
          sha256: file.sha256,
          configuration: configuration, cancelled: cancelled
        ) { completed in
          progress(
            .init(
              phase: "Downloading or verifying", file: file.path, completedBytes: completed,
              totalBytes: file.bytes))
        }
      }
    }
    if cancelled() { throw SplashError("Model setup cancelled") }
    return try SplashModelPreparation.prepare(
      pack: pack, target: directories[0], draft: directories[1], modelsRoot: root,
      fullVerification: reusingTarget != nil || reusingDraft != nil, pinnedSources: true,
      cancelled: cancelled
    ) { state in
      progress(
        .init(
          phase: "Preparing", file: state.file, completedBytes: state.verifiedBytes,
          totalBytes: state.totalBytes))
    }
  }
  package static func availableCapacity(_ url: URL) throws -> Int64 {
    guard
      let amount = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        .volumeAvailableCapacityForImportantUsage
    else {
      throw SplashError("Cannot determine free storage for model setup")
    }
    return amount
  }
  private static func directory(_ url: URL) throws {
    var st = stat()
    if lstat(url.path, &st) == 0 {
      guard st.st_mode & S_IFMT == S_IFDIR else {
        throw SplashError("Model cache directory was replaced")
      }
    } else if errno == ENOENT {
      try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    } else {
      throw SplashError("Cannot inspect model cache directory")
    }
  }
  private static func size(_ url: URL) -> Int64 {
    var st = stat()
    return lstat(url.path, &st) == 0 ? st.st_size : 0
  }
}
