import Foundation

/// Resolve shipped resources at their installed location. Never fall back to
/// an absolute contributor build path when a packaged resource is missing.
public enum SplashRuntimeResources {
  public static var executableDirectory: URL {
    (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath().deletingLastPathComponent()
  }

  public static var installedBundleContents: URL? {
    let executable = executableDirectory
    let contents = executable.deletingLastPathComponent()
    guard executable.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
      contents.deletingLastPathComponent().pathExtension == "app"
    else { return nil }
    return contents
  }

  public static var resourceRoot: URL {
    installedBundleContents?.appendingPathComponent("Resources") ?? executableDirectory
  }

  public static func resource(_ name: String, extension ext: String, bundle: String) throws -> URL {
    guard let resources = Bundle(url: resourceRoot.appendingPathComponent(bundle + ".bundle")),
      let resource = resources.url(forResource: name, withExtension: ext)
    else { throw SplashError("Required native resource is missing: " + name) }
    return resource
  }
}
