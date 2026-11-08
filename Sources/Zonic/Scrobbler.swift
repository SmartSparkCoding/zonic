import AppKit
import CryptoKit
import Foundation

/// Last.fm scrobbling for whatever the page is playing.
///
/// Auth uses Last.fm's token flow, which is the only one that works without a callback
/// URL: ask for a token, send the user to the auth page in their browser, then exchange
/// the approved token for a session key. No web server, no deep link.
///
/// Everything here is driven by the state the WebKit bridge already reports, so a track
/// is scrobbled from the page's own position rather than a wall clock.
final class Scrobbler {
    static let shared = Scrobbler()

    private let defaults = UserDefaults.standard
    private let keyKey = "zonic.lastfm.apiKey"
    private let secretKey = "zonic.lastfm.apiSecret"
    private let sessionKey = "zonic.lastfm.session"
    private let userKey = "zonic.lastfm.user"
    private let enabledKey = "zonic.lastfm.enabled"

    private let endpoint = "https://ws.audioscrobbler.com/2.0/"
    private let authPage = "https://www.last.fm/api/auth/"

    private var pendingToken: String?
    private var current: PlayerState = .empty
    private var startedAt: Date?
    private var scrobbled: Set<String> = []
    private var nowPlayingKey: String?

    /// Pause aware wall clock. The page's own position is trusted when it reports one;
    /// this covers the case where it sits at zero and scrobbles would never fire.
    private var played: TimeInterval = 0
    private var lastTick: Date?

    /// Last few API answers, so a failure can be read back instead of guessed at.
    private(set) var recentAnswers: [String] = []

    // MARK: - Credentials

    var apiKey: String {
        get { defaults.string(forKey: keyKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: keyKey) }
    }

    var apiSecret: String {
        get { defaults.string(forKey: secretKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: secretKey) }
    }

    var username: String? { defaults.string(forKey: userKey) }
    var sessionToken: String? { defaults.string(forKey: sessionKey) }
    var isConnected: Bool { sessionToken != nil && username != nil }

    /// Scaffolding and now-playing pings still happen when this is false; only scrobbles stop.
    var isEnabled: Bool {
        get {
            if defaults.object(forKey: enabledKey) == nil { return true }
            return defaults.bool(forKey: enabledKey)
        }
        set {
            defaults.set(newValue, forKey: enabledKey)
            notify()
        }
    }

    var statusLine: String {
        if isConnected, let username { return "Scrobbling to Last.fm as \(username)" }
        if !apiKey.isEmpty { return "Authorise Zonic in your browser to finish connecting" }
        return "Add your Last.fm API key and secret to start scrobbling"
    }

    /// Last thing that happened, shown under the settings section.
    private(set) var lastMessage: String = ""

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .lastfmStatusDidChange, object: nil)
        }
    }

    private func report(_ message: String) {
        lastMessage = message
        notify()
    }

    // MARK: - AUTH

    /// Step one: get a token and open Last.fm's approval page in the browser.
    func beginAuth() {
        guard !apiKey.isEmpty else { report("Add an API key first"); return }

        call(method: "auth.getToken", extra: [:], needsSession: false) { [weak self] json in
            guard let self else { return }
            guard let token = json["token"] as? String else {
                self.report("Last.fm would not issue a token")
                return
            }
            self.pendingToken = token
            self.stash(token)
            var components = URLComponents(string: self.authPage)
            components?.queryItems = [
                URLQueryItem(name: "api_key", value: self.apiKey),
                URLQueryItem(name: "token", value: token)
            ]
            if let url = components?.url {
                NSWorkspace.shared.open(url)
                self.report("Approve Zonic in your browser, then press Connect again")
            }
        }
    }

    /// Step two: exchange the approved token for a session key.
    func finishAuth() {
        guard let token = pendingToken ?? pendingStoredToken() else {
            beginAuth()
            return
        }
        pendingToken = token

        call(method: "auth.getSession", extra: ["token": token], needsSession: false) { [weak self] json in
            guard let self else { return }
            guard let session = json["session"] as? [String: Any],
                  let key = session["key"] as? String,
                  let name = session["name"] as? String else {
                let reason = json["message"] as? String ?? "that token is not approved"
                // An unapproved token is useless forever, and so is one approved by a
                // different Last.fm account. Drop it and open a fresh approval page,
                // otherwise Connect becomes a dead end that keeps reusing the bad token.
                self.defaults.removeObject(forKey: self.storedTokenKey)
                self.pendingToken = nil
                self.report("Last.fm said: \(reason). Opening a fresh approval page…")
                self.beginAuth()
                return
            }
            self.defaults.set(key, forKey: self.sessionKey)
            self.defaults.set(name, forKey: self.userKey)
            self.defaults.removeObject(forKey: self.storedTokenKey)
            self.pendingToken = nil
            self.report("Connected as \(name)")
        }
    }

    /// True while a token is waiting for approval, so the button can say which step it is on.
    var hasPendingToken: Bool {
        pendingToken != nil || pendingStoredToken() != nil
    }

    /// The token is stashed because the app is often quit between approving and connecting.
    private var storedTokenKey: String { "zonic.lastfm.pendingToken" }

    private func pendingStoredToken() -> String? {
        if let token = defaults.string(forKey: storedTokenKey) { return token }
        return nil
    }

    private func stash(_ token: String) {
        defaults.set(token, forKey: storedTokenKey)
    }

    func signOut() {
        defaults.removeObject(forKey: sessionKey)
        defaults.removeObject(forKey: userKey)
        defaults.removeObject(forKey: storedTokenKey)
        pendingToken = nil
        report("Disconnected from Last.fm")
    }

    // MARK: - Playback

    func observe(_ state: PlayerState) {
        let previous = current
        current = state
        advanceClock(playing: state.isPlaying)

        guard state.hasTrack else { return }
        let key = trackKey(state)
        let previousKey = trackKey(previous)

        if key != previousKey {
            startedAt = Date()
            played = 0
            lastTick = Date()
            nowPlayingKey = nil
            if isConnected { sendNowPlaying(state) }
            return
        }

        guard isConnected, isEnabled else { return }
        let identity = scrobbleKey(state)
        guard !scrobbled.contains(identity) else { return }
        guard listened(state) >= scrobbleThreshold(for: state.duration) else { return }
        scrobble(state, identity: identity)
    }

    /// Adds real time to the clock, but only while something is playing and only for
    /// believable gaps, so a paused or sleeping app does not bank listening time.
    private func advanceClock(playing: Bool) {
        defer { lastTick = Date() }
        guard playing, let lastTick else { return }
        let delta = Date().timeIntervalSince(lastTick)
        if delta > 0, delta < 30 { played += delta }
    }

    /// What the track has actually played: the page's number when it has one, else the clock.
    private func listened(_ state: PlayerState) -> Double {
        state.position > 0 ? state.position : played
    }

    /// Keyed on the start time as well, so the same song later in the session scrobbles again.
    private func scrobbleKey(_ state: PlayerState) -> String {
        let started = Int((startedAt ?? Date()).timeIntervalSince1970)
        return "\(state.artist.lowercased())|\(state.title.lowercased())|\(started)"
    }

    /// Last.fm's rule: half the track or four minutes, whichever comes first, and never
    /// for anything shorter than thirty seconds.
    private func scrobbleThreshold(for duration: Double) -> Double {
        guard duration > 30 else { return .greatestFiniteMagnitude }
        return min(240, duration / 2)
    }

    private func trackKey(_ state: PlayerState) -> String {
        "\(state.artist.lowercased())|\(state.title.lowercased())"
    }

    private func sendNowPlaying(_ state: PlayerState) {
        let key = trackKey(state)
        guard nowPlayingKey != key else { return }
        nowPlayingKey = key

        var extra: [String: String] = [
            "artist": state.artist,
            "track": state.title
        ]
        if !state.album.isEmpty { extra["album"] = state.album }
        if state.duration > 0 { extra["duration"] = String(Int(state.duration.rounded())) }

        call(method: "track.updateNowPlaying", extra: extra) { _ in }
    }

    private func scrobble(_ state: PlayerState, identity: String) {
        scrobbled.insert(identity)

        var extra: [String: String] = [
            "artist": state.artist,
            "track": state.title,
            "timestamp": String(Int((startedAt ?? Date()).timeIntervalSince1970))
        ]
        if !state.album.isEmpty { extra["album"] = state.album }
        if state.duration > 0 { extra["duration"] = String(Int(state.duration.rounded())) }

        call(method: "track.scrobble", extra: extra) { [weak self] json in
            guard let self else { return }
            if json["error"] != nil {
                self.scrobbled.remove(identity)
                self.report("Scrobble refused: \(json["message"] as? String ?? "unknown error")")
            } else {
                self.report("Scrobbled \(state.title)")
            }
        }
    }

    /// The heart in the chrome bar. Last.fm calls it a "love".
    func love() {
        guard isConnected else { report("Connect Last.fm first"); return }
        let state = current
        guard state.hasTrack else { return }

        call(method: "track.love", extra: ["artist": state.artist, "track": state.title]) { [weak self] json in
            guard let self else { return }
            if let message = json["message"] as? String {
                self.report("Last.fm: \(message)")
            } else {
                self.report("Loved \(state.title)")
            }
        }
    }

    // MARK: - Diagnostics

    private func record(_ line: String) {
        DispatchQueue.main.async {
            self.recentAnswers.append(line)
            if self.recentAnswers.count > 8 { self.recentAnswers.removeFirst() }
        }
    }

    var logText: String {
        recentAnswers.isEmpty ? "no Last.fm calls yet" : recentAnswers.joined(separator: "\n")
    }

    /// Sends a scrobble for whatever is playing right now, ignoring the listening rules, so
    /// a broken setup reports Last.fm's own error instead of silence.
    func testScrobble() {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else { report("Add the API key and secret first"); return }
        guard isConnected else { report("Connect Last.fm first"); return }
        let state = current
        guard state.hasTrack else { report("Nothing is playing, start a song first"); return }

        var extra: [String: String] = [
            "artist": state.artist,
            "track": state.title,
            "timestamp": String(Int(Date().timeIntervalSince1970))
        ]
        if !state.album.isEmpty { extra["album"] = state.album }
        if state.duration > 0 { extra["duration"] = String(Int(state.duration.rounded())) }

        report("Sending a test scrobble for \(state.title)…")
        call(method: "track.scrobble", extra: extra) { [weak self] json in
            guard let self else { return }
            if let error = json["error"] {
                self.report("Last.fm refused it: \(error) \(json["message"] as? String ?? "")")
            } else {
                self.report("Last.fm accepted the test scrobble")
            }
        }
    }

    // MARK: - Transport

    /// Signs and sends one API call. Callbacks land on the main queue.
    private func call(
        method: String,
        extra: [String: String],
        needsSession: Bool = true,
        completion: @escaping ([String: Any]) -> Void
    ) {
        guard !apiKey.isEmpty, !apiSecret.isEmpty else {
            report("Last.fm API key missing")
            return
        }

        var params = extra
        params["method"] = method
        params["api_key"] = apiKey
        if needsSession {
            guard let token = sessionToken else {
                report("Not connected to Last.fm")
                return
            }
            params["sk"] = token
        }

        params["api_sig"] = signature(for: params)
        params["format"] = "json"

        var body = URLComponents()
        body.queryItems = params
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let encoded = body.percentEncodedQuery,
              let url = URL(string: endpoint),
              let data = encoded.data(using: .utf8) else {
            report("Could not build the Last.fm request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Zonic for macOS", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            let finish: ([String: Any]) -> Void = { json in
                DispatchQueue.main.async { completion(json) }
            }

            if let error {
                self.report("Last.fm request failed: \(error.localizedDescription)")
                return
            }
            guard let data else {
                self.report("Last.fm sent nothing back")
                return
            }
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let json = object as? [String: Any] else {
                let raw = String(data: data, encoding: .utf8) ?? "<not text>"
                self.record("\(method) -> unreadable: \(raw.prefix(200))")
                self.report("Last.fm sent something unreadable")
                return
            }
            let summary = (json["error"] != nil)
                ? "\(method) -> error \(json["error"] ?? "?"): \(json["message"] as? String ?? "")"
                : "\(method) -> \(json["lfm"] != nil ? "ok" : "no lfm node")"
            self.record(summary)
            finish(json)
        }.resume()
    }

    /// md5 of the parameters in key order with the secret appended, as Last.fm specifies.
    private func signature(for params: [String: String]) -> String {
        let joined = params
            .filter { $0.key != "format" && $0.key != "api_sig" }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)\($0.value)" }
            .joined()
        let digest = Insecure.MD5.hash(data: Data((joined + apiSecret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension Notification.Name {
    static let lastfmStatusDidChange = Notification.Name("zonic.lastfmStatusDidChange")
}
