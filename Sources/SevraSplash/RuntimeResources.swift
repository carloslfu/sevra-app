import Foundation

/// Resolve shipped resources at their installed location. Never fall back to
/// an absolute contributor build path when a packaged resource is missing.
public enum SplashRuntimeResources {
  public static func resource(_ name: String, extension ext: String, bundle: String) throws -> URL {
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath().deletingLastPathComponent()
    let root = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.resourceURL! : executable
    guard let resources = Bundle(url: root.appendingPathComponent(bundle + ".bundle")),
      let resource = resources.url(forResource: name, withExtension: ext)
    else { throw SplashError("Required native resource is missing: " + name) }
    return resource
  }
}
