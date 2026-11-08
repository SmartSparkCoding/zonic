import AppKit
import MediaPlayer

/// Publishes the current track to Control Center, the menu bar now-playing widget and
/// the lock screen style media controls, and receives the hardware media keys.
final class NowPlayingCenter {
    static let shared = NowPlayingCenter()

    var commandHandler: ((String) -> Void)?

    private var latest = PlayerState.empty
    private var artworkURL: URL?
    private var artwork: MPMediaItemArtwork?

    func activate() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true

        _ = center.playCommand.addTarget { [weak self] _ in
            self?.commandHandler?("play")
            return .success
        }
        _ = center.pauseCommand.addTarget { [weak self] _ in
            self?.commandHandler?("pause")
            return .success
        }
        _ = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.commandHandler?("toggle")
            return .success
        }
        _ = center.nextTrackCommand.addTarget { [weak self] _ in
            self?.commandHandler?("next")
            return .success
        }
        _ = center.previousTrackCommand.addTarget { [weak self] _ in
            self?.commandHandler?("previous")
            return .success
        }

        let unsupported: [MPRemoteCommand] = [
            center.seekForwardCommand,
            center.seekBackwardCommand,
            center.skipForwardCommand,
            center.skipBackwardCommand,
            center.changePlaybackPositionCommand,
            center.changePlaybackRateCommand,
            center.ratingCommand,
            center.likeCommand,
            center.dislikeCommand,
            center.bookmarkCommand
        ]
        unsupported.forEach { $0.isEnabled = false }
    }

    func update(with state: PlayerState) {
        latest = state

        guard state.hasTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }

        publish()
        loadArtwork(from: state.artworkURL)
    }

    private func publish() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: latest.title,
            MPNowPlayingInfoPropertyPlaybackRate: latest.isPlaying ? 1.0 : 0.0
        ]
        if !latest.artist.isEmpty { info[MPMediaItemPropertyArtist] = latest.artist }
        if !latest.album.isEmpty { info[MPMediaItemPropertyAlbumTitle] = latest.album }
        if let artwork = self.artwork { info[MPMediaItemPropertyArtwork] = artwork }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = latest.isPlaying ? .playing : .paused
    }

    private func loadArtwork(from url: URL?) {
        guard let url, url != artworkURL else { return }
        artworkURL = url
        artwork = nil

        let apply: (NSImage?) -> Void = { [weak self] image in
            guard let self, let image, self.artworkURL == url else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.publish()
        }

        if url.scheme == "data" {
            let encoded = url.absoluteString.components(separatedBy: "base64,").last ?? ""
            apply(Data(base64Encoded: encoded).flatMap { NSImage(data: $0) })
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { NSImage(data: $0) }
            DispatchQueue.main.async { apply(image) }
        }.resume()
    }
}
