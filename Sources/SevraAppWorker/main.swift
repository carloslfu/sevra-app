import Darwin
import Foundation
import SevraAppProtocol
import SevraAppRuntime
import SevraCore

final class Worker: NSObject, NativeAppWorkerProtocol {
  private let runtime = NativeAppRuntime()
  private let queue = DispatchQueue(label: "com.sevra.app-worker")
  func exchange(_ request: Data, withReply reply: @escaping (Data) -> Void) {
    guard request.count <= NativeAppWire.byteLimit else {
      reply(Data())
      return
    }
    if let message = try? NativeAppWire.decode(request), message["kind"].text == "sandboxProbe" {
      let file = message["file"].text
      guard file.hasPrefix("/private/tmp/sevra-app-probe-") && file.utf8.count < 1024 else {
        reply(Data())
        return
      }
      let fd = open(file, O_RDONLY | O_NOFOLLOW)
      let fileError = fd < 0 ? errno : 0
      if fd >= 0 { close(fd) }
      let socketFD = socket(AF_INET, SOCK_STREAM, 0)
      var networkError = socketFD < 0 ? errno : 0
      if socketFD >= 0 {
        _ = fcntl(socketFD, F_SETFL, O_NONBLOCK)
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
          pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
          }
        }
        networkError = result < 0 ? errno : 0
        close(socketFD)
      }
      reply(
        (try? NativeAppWire.encode(
          .object([
            "fileErrno": .number(Double(fileError)), "networkErrno": .number(Double(networkError)),
          ]))) ?? Data())
      return
    }
    queue.async {
      // The independent watchdog also catches blocking native engine defects. It kills only this service.
      let done = DispatchSemaphore(value: 0)
      DispatchQueue.global(qos: .userInitiated).async {
        if done.wait(timeout: .now() + 3) == .timedOut { _exit(70) }
      }
      let result = self.runtime.exchange(request)
      done.signal()
      reply(result)
    }
  }
}
final class Listener: NSObject, NSXPCListenerDelegate {
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
    -> Bool
  {
    connection.exportedInterface = NSXPCInterface(with: NativeAppWorkerProtocol.self)
    connection.exportedObject = Worker()
    connection.resume()
    return true
  }
}
let delegate = Listener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
