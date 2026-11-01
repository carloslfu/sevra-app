import Darwin
import Foundation
import SevraCore

/// Fixtures for one run. Made on first use, so a worker mode makes none, and removed however
/// the run ends: `exit`, a failed check, an uncaught error, a crash or a stop signal.
let temp: URL = {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
    "sevra-checks-" + identifier())
  try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  // A dying process must not allocate, so its arguments are built here.
  let arguments: [String] = ["/bin/rm", "-rf", folder.path]
  removal = arguments.map { strdup($0) } + [nil]
  atexit { spawnRemoval() }
  for number in [SIGINT, SIGTERM, SIGHUP, SIGABRT, SIGILL, SIGTRAP, SIGSEGV, SIGBUS] {
    signal(number) { number in
      spawnRemoval()
      signal(number, SIG_DFL)
      raise(number)
    }
  }
  return folder
}()
private var removal: [UnsafeMutablePointer<CChar>?] = []
private func spawnRemoval() {
  var process: pid_t = 0
  guard posix_spawn(&process, "/bin/rm", nil, nil, removal, nil) == 0 else { return }
  var status: Int32 = 0
  waitpid(process, &status, 0)
}
