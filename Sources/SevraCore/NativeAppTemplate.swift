import Foundation

extension Workbook {
  @discardableResult public func exportNativeAppTemplate(
    _ spaceID: String, to destination: URL, cancellation: Cancellation = .init()
  ) throws -> URL {
    guard var package = try space(spaceID).definition.app else {
      throw SevraError("app_package", "Choose a mini app.")
    }
    try require(
      package.images?.isEmpty != false, "app_template_images",
      "This app uses included images. Export a portable workbook to keep the images with it.")
    try require(
      package.excelBehavior == nil, "app_template_excel",
      "This app uses saved Excel behavior. Export a portable workbook to keep the original and its calculations."
    )
    for key in package.datasets.keys { package.datasets[key]?.datasetID = nil }
    try require(
      destination.pathExtension.lowercased() == "sevraapp", "export_path",
      "Use a .sevraapp destination for the app template.")
    return try publishSmallExport(
      Data(encoded(package).json().utf8), to: destination, cancellation: cancellation)
  }
}
