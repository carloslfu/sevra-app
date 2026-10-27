import AVFoundation
import Foundation

@MainActor public protocol PlaybackParticipant: AnyObject { func pause() }
extension AVPlayer: PlaybackParticipant {}

/// Tracks all live players without extending a viewer/window's lifetime.
@MainActor public final class PlaybackRegistry {
  public static let shared = PlaybackRegistry()
  private struct Entry {
    weak var player: (any PlaybackParticipant)?
    let owner: UUID
  }
  private var entries: [ObjectIdentifier: Entry] = [:]
  public init() {}
  public func register(_ player: any PlaybackParticipant, owner: UUID) {
    entries = entries.filter { $0.value.player != nil }
    entries[ObjectIdentifier(player)] = Entry(player: player, owner: owner)
  }
  public func pauseAll() {
    entries = entries.filter { $0.value.player != nil }
    for entry in entries.values { entry.player?.pause() }
  }
  public func close(owner: UUID) {
    for entry in entries.values where entry.owner == owner { entry.player?.pause() }
    entries = entries.filter { $0.value.owner != owner && $0.value.player != nil }
  }
}
