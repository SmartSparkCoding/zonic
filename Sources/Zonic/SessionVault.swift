import Foundation
import WebKit

/// Keeps a copy of the Amazon login cookies outside WebKit's own store.
///
/// The webview is configured with the persistent data store, which should hold on to a
/// login by itself. In practice it does not always: Amazon hands out session scoped auth
/// cookies unless "Keep me signed in" is ticked, and cookie writes can be lost when the
/// process is torn down straight after the update swap. This writes the cookies to a small
/// file as they change and puts them back into the store before the first page load, so a
/// relaunch opens signed in either way.
final class SessionVault: NSObject, WKHTTPCookieStoreObserver {
    static let shared = SessionVault()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.smartsparkcoding.zonic.sessionvault")
    private var store: WKWebsiteDataStore?
    private var isRestoring = false
    private var pendingSave: DispatchWorkItem?

    private override init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let folder = base.appendingPathComponent("Zonic", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("cookies.json")
        super.init()
    }

    var vaultPath: String { fileURL.path }

    /// How many cookies are sitting on disk, used by the diagnostics dump.
    var storedCookieCount: Int {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return 0
        }
        return object.count
    }

    /// Registers for cookie changes and puts the stored login back into the store. Call
    /// before the first page load.
    func attach(to dataStore: WKWebsiteDataStore) {
        store = dataStore
        dataStore.httpCookieStore.add(self)
        restore()
    }

    private func restore() {
        guard let store else { return }
        guard let saved = readFile(), !saved.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        let cookies = saved.compactMap(SessionVault.cookie(from:)).filter { cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires.timeIntervalSince1970 > now
        }
        guard !cookies.isEmpty else { return }

        isRestoring = true
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.httpCookieStore.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isRestoring = false
            self.save(cookies: cookies)
        }
    }

    // MARK: - Saving

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !isRestoring else { return }
        saveSoon()
    }

    func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.capture() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Reads the store and writes anything Amazon related to disk.
    func capture() {
        guard let store else { return }
        store.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let relevant = cookies.filter(SessionVault.wanted)
            guard !relevant.isEmpty else { return }
            self.save(cookies: relevant)
        }
    }

    private func save(cookies: [HTTPCookie]) {
        let payload = cookies.map(SessionVault.dictionary(from:))
        queue.async { [fileURL] in
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
            let temporary = fileURL.appendingPathExtension("tmp")
            do {
                try data.write(to: temporary)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } catch {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func readFile() -> [[String: Any]]? {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return object
    }

    // MARK: - Codable-ish helpers

    private static func wanted(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased()
        return domain.contains("amazon") || domain.contains("amzn")
    }

    private static func dictionary(from cookie: HTTPCookie) -> [String: Any] {
        var payload: [String: Any] = [
            "name": cookie.name,
            "value": cookie.value,
            "domain": cookie.domain,
            "path": cookie.path,
            "secure": cookie.isSecure
        ]
        if let expires = cookie.expiresDate {
            payload["expires"] = expires.timeIntervalSince1970
        }
        return payload
    }

    private static func cookie(from payload: [String: Any]) -> HTTPCookie? {
        guard let name = payload["name"] as? String,
              let value = payload["value"] as? String,
              let domain = payload["domain"] as? String,
              let path = payload["path"] as? String else {
            return nil
        }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: (payload["secure"] as? Bool ?? false) ? "TRUE" : "FALSE"
        ]
        // No expiry means it was a session cookie. Leaving `.expires` out keeps that shape,
        // and the vault re-injects it on launch, which is the whole point.
        if let expires = payload["expires"] as? Double {
            properties[.expires] = Date(timeIntervalSince1970: expires)
        }
        return HTTPCookie(properties: properties)
    }
}
