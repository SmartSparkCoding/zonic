import Foundation

struct PlayerState: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkURL: URL?
    var isPlaying: Bool = false
    var isEditing: Bool = false
    var position: Double = 0
    var duration: Double = 0
    var canSeek: Bool = false

    static let empty = PlayerState()

    var hasTrack: Bool { !title.isEmpty }

    var displayText: String {
        guard hasTrack else { return "" }
        return artist.isEmpty ? title : "\(title) · \(artist)"
    }

    var progressText: String {
        guard duration > 0 else { return "" }
        return "\(PlayerState.clock(position)) / \(PlayerState.clock(duration))"
    }

    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
