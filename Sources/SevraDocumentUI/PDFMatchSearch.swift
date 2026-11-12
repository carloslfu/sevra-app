import Foundation

/// PDF text search and motion decisions, independent of PDFView and application state.
public struct PDFMatchSearch {
  public struct Match: Equatable {
    public let page: Int
    public let range: NSRange
    public let animate: Bool
  }
  public enum Result: Equatable {
    case invalidQuery, noMatch
    case match(Match)
  }
  private var previousQuery = ""
  private var previousDocument = ""
  private var lastPage = -1
  private var lastEnd = 0
  public init() {}
  public mutating func next(
    query: String, documentID: String, pageCount: Int,
    currentPage: Int, reduceMotion: Bool, text: (Int) -> String?
  ) -> Result {
    guard !query.isEmpty && query.utf8.count <= 2048 else { return .invalidQuery }
    guard pageCount > 0 else { return .noMatch }
    if previousQuery != query || previousDocument != documentID {
      lastPage = -1
      lastEnd = 0
      previousQuery = query
      previousDocument = documentID
    }
    let startPage =
      lastPage >= 0 ? min(lastPage, pageCount - 1) : min(max(0, currentPage), pageCount - 1)
    for step in 0...pageCount {
      let index = (startPage + step) % pageCount
      guard let value = text(index) else { continue }
      let body = value as NSString
      let start = step == 0 && lastPage == index ? min(lastEnd, body.length) : 0
      let match = body.range(
        of: query, options: .caseInsensitive,
        range: NSRange(location: start, length: body.length - start))
      if match.location != NSNotFound {
        lastPage = index
        lastEnd = NSMaxRange(match)
        return .match(.init(page: index, range: match, animate: !reduceMotion))
      }
    }
    return .noMatch
  }
}
