import Foundation

struct PlayerState: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artworkURL: URL?
    var isPlaying: Bool = false
    var isEditing: Bool = false

    static let empty = PlayerState()

    var hasTrack: Bool { !title.isEmpty }

    var displayText: String {
        guard hasTrack else { return "" }
        return artist.isEmpty ? title : "\(title) · \(artist)"
    }
}
