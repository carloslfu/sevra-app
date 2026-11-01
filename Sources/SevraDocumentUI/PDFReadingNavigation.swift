import Foundation
import PDFKit

/// A locator is a navigation request, not a request to reload the file. Repeated
/// SwiftUI updates leave manual reading alone; a new locator in the same file
/// still opens the requested page.
@MainActor public final class PDFReadingNavigation {
  private weak var view: PDFView?
  private var url: URL?
  private var locator: String?
  public init() {}

  @discardableResult public func apply(_ view: PDFView, url: URL, locator: String?) -> Bool {
    let newView = self.view !== view
    // An unreadable file stays without a document, so it is tried once per file and view.
    let newFile = newView || self.url != url
    let newLocator = self.locator != locator
    self.view = view
    self.url = url
    self.locator = locator
    if newFile { view.document = PDFDocument(url: url) }
    guard newView || newFile || newLocator, let locator,
      let match = locator.range(of: "(?:^|;)page=([0-9]+)(?:;|$)", options: .regularExpression)
    else { return false }
    let component = locator[match].split(separator: ";").first { $0.hasPrefix("page=") }
    guard let component, let number = Int(component.dropFirst(5)), number > 0,
      let page = view.document?.page(at: number - 1)
    else { return false }
    if view.currentPage !== page { view.go(to: page) }
    return true
  }
}
