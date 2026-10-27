import AVKit
import SwiftUI

/// A direct AppKit player also creates a strong AVKit framework reference in the
/// packaged binary. The SwiftUI VideoPlayer overlay alone did not retain that
/// dependency in our optimized build and crashed on superclass initialization.
struct NativeMediaPlayer: NSViewRepresentable {
  let player: AVPlayer?

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .inline
    view.showsSharingServiceButton = false
    view.player = player
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
    if view.player !== player { view.player = player }
  }

  static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
    // Playback ownership belongs to the workbook registry. Detach this view
    // without stopping an explicitly retained background player.
    view.player = nil
  }
}
