import Foundation

struct LyricLine {
    let time: TimeInterval
    let text: String
}

struct Lyrics {
    let lines: [LyricLine]
    let plain: String

    var isSynced: Bool { !lines.isEmpty }

    init?(json: [String: Any]) {
        let synced = (json["syncedLyrics"] as? String) ?? ""
        let plainText = (json["plainLyrics"] as? String) ?? ""

        if !synced.isEmpty {
            let parsed = Lyrics.parse(synced)
            if parsed.isEmpty {
                guard !plainText.isEmpty else { return nil }
                lines = []
                plain = plainText
            } else {
                lines = parsed
                plain = plainText
            }
        } else if !plainText.isEmpty {
            lines = []
            plain = plainText
        } else {
            return nil
        }
    }

    /// Parses LRC into timed lines. Handles the multiple-timestamp-per-line form and
    /// ignores the metadata tags such as [ar:...].
    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for rawLine in lrc.components(separatedBy: .newlines) {
            var rest = rawLine.trimmingCharacters(in: .whitespaces)
            var stamps: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let inside = String(rest[rest.index(after: rest.startIndex)..<close])
                rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                let parts = inside.split(separator: ":")
                guard parts.count == 2,
                      let minutes = Double(String(parts[0])),
                      let seconds = Double(String(parts[1])) else { continue }
                stamps.append(minutes * 60 + seconds)
            }
            guard !stamps.isEmpty else { continue }
            for stamp in stamps {
                out.append(LyricLine(time: stamp, text: rest))
            }
        }
        return out.sorted { $0.time < $1.time }
    }
}

/// Looks lyrics up on LRCLIB, which is free and needs no key. Results are cached per
/// track, including the misses, so skipping back and forth does not re-ask.
final class LyricsService {
    static let shared = LyricsService()

    private let cacheLock = NSLock()
    private var cache: [String: Lyrics] = [:]
    private var misses: Set<String> = []
    private let session = URLSession(configuration: .default)

    private func key(for state: PlayerState) -> String {
        "\(state.artist)|\(state.title)|\(Int(state.duration.rounded()))".lowercased()
    }

    func lyrics(for state: PlayerState, completion: @escaping (Lyrics?) -> Void) {
        guard state.hasTrack else { completion(nil); return }
        let cacheKey = key(for: state)

        cacheLock.lock()
        let cached = cache[cacheKey]
        let missed = misses.contains(cacheKey)
        cacheLock.unlock()

        if let cached { completion(cached); return }
        if missed { completion(nil); return }

        request(state: state, cacheKey: cacheKey, completion: completion)
    }

    private func request(state: PlayerState, cacheKey: String, completion: @escaping (Lyrics?) -> Void) {
        var items = [
            URLQueryItem(name: "artist_name", value: state.artist),
            URLQueryItem(name: "track_name", value: state.title)
        ]
        if !state.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: state.album))
        }
        if state.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(state.duration.rounded()))))
        }

        guard var components = URLComponents(string: "https://lrclib.net/api/get") else {
            completion(nil)
            return
        }
        components.queryItems = items
        guard let url = components.url else { completion(nil); return }

        var request = URLRequest(url: url)
        request.setValue("Zonic for macOS (https://github.com/SmartSparkCoding/zonic)",
                         forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data),
               let dict = object as? [String: Any],
               let lyrics = Lyrics(json: dict) {
                self.store(lyrics, for: cacheKey)
                DispatchQueue.main.async { completion(lyrics) }
                return
            }
            self.search(state: state, cacheKey: cacheKey, completion: completion)
        }.resume()
    }

    /// The exact-match endpoint 404s more often than not, so fall back to search.
    private func search(state: PlayerState, cacheKey: String, completion: @escaping (Lyrics?) -> Void) {
        var items = [
            URLQueryItem(name: "track_name", value: state.title),
            URLQueryItem(name: "artist_name", value: state.artist)
        ]
        if !state.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: state.album))
        }
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else {
            completion(nil)
            return
        }
        components.queryItems = items
        guard let url = components.url else { completion(nil); return }

        var request = URLRequest(url: url)
        request.setValue("Zonic for macOS (https://github.com/SmartSparkCoding/zonic)",
                         forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            var found: Lyrics?
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data),
               let results = object as? [[String: Any]] {
                for result in results {
                    if let lyrics = Lyrics(json: result), lyrics.isSynced {
                        found = lyrics
                        break
                    }
                }
                if found == nil {
                    for result in results {
                        if let lyrics = Lyrics(json: result) {
                            found = lyrics
                            break
                        }
                    }
                }
            }

            if let found {
                self.store(found, for: cacheKey)
                DispatchQueue.main.async { completion(found) }
            } else {
                self.storeMiss(for: cacheKey)
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }

    private func store(_ lyrics: Lyrics, for key: String) {
        cacheLock.lock()
        cache[key] = lyrics
        cacheLock.unlock()
    }

    private func storeMiss(for key: String) {
        cacheLock.lock()
        misses.insert(key)
        cacheLock.unlock()
    }
}
