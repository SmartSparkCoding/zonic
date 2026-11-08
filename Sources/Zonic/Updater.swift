import AppKit
import CryptoKit

/// Self updater that talks to the GitHub releases API. Downloads the release zip,
/// checks it against the published `SHA256SUMS.txt`, unpacks it and hands the swap to a
/// small shell script that waits for the app to quit and then relaunches it.
final class Updater: NSObject {
    static let shared = Updater()

    private let repo = "SmartSparkCoding/zonic"
    private var isChecking = false
    private var isInstalling = false
    private var panel: UpdatePanel?

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    // MARK: - Check

    /// Menu and button entry point.
    @objc func checkNow(_ sender: Any?) {
        checkForUpdates(userInitiated: true)
    }

    func checkForUpdates(userInitiated: Bool) {
        guard !isChecking, !isInstalling else { return }
        isChecking = true

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false

                if let error {
                    if userInitiated {
                        self.warn("Could not reach GitHub", error.localizedDescription)
                    }
                    return
                }

                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    if userInitiated {
                        self.warn("Could not check for updates", "GitHub answered with an unexpected response.")
                    }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    if userInitiated {
                        self.warn("Could not read the latest release", "The release details were not in the expected shape.")
                    }
                    return
                }

                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard Updater.isNewer(latest, than: self.currentVersion) else {
                    if userInitiated {
                        self.inform("Zonic is up to date", "You are running \(self.currentVersion), the latest release.")
                    }
                    return
                }

                let notes = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let assets = (json["assets"] as? [[String: Any]]) ?? []
                if let page = json["html_url"] as? String {
                    self.releasePage = URL(string: page)
                }
                self.offer(version: latest, notes: notes, assets: assets)
            }
        }.resume()
    }

    private func offer(version: String, notes: String, assets: [[String: Any]]) {
        guard let zip = Updater.asset(named: assets, matching: { $0.hasSuffix(".zip") }) else {
            warn("Release is missing its download", "The latest release has no zip asset to install.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Zonic \(version) is available"
        alert.alertStyle = .informational

        var body = "You are on \(currentVersion). Updating replaces the copy you have now and reopens it."
        if !notes.isEmpty {
            body += "\n\n" + String(notes.prefix(700))
        }
        alert.informativeText = body
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Later")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        install(version: version, zipPath: zip["browser_download_url"] as? String, assets: assets)
    }

    // MARK: - Install

    private func install(version: String, zipPath: String?, assets: [[String: Any]]) {
        guard let zipPath, let zipURL = URL(string: zipPath) else { return }
        isInstalling = true

        let panel = UpdatePanel(message: "Downloading Zonic \(version)…")
        self.panel = panel
        panel.show()

        let sumsURL = Updater.asset(named: assets, matching: { $0 == "SHA256SUMS.txt" })
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))

        fetch(sumsURL) { [weak self] sumsData in
            guard let self else { return }
            self.fetch(zipURL) { zipData in
                guard let zipData else {
                    self.fail("The download did not finish", "GitHub did not return the release archive.")
                    return
                }

                if let sumsData, let sums = String(data: sumsData, encoding: .utf8) {
                    let name = zipURL.lastPathComponent
                    guard let expected = Updater.expectedHash(for: name, in: sums) else {
                        self.fail("Could not verify the download", "\(name) is not listed in SHA256SUMS.txt.")
                        return
                    }
                    let actual = Updater.sha256(zipData)
                    guard actual == expected else {
                        self.fail("The download was damaged", "Checksum mismatch, so the update was discarded.")
                        return
                    }
                }

                self.panel?.setMessage("Installing Zonic \(version)…")
                self.unpackAndSwap(zipData: zipData, version: version)
            }
        }
    }

    private func unpackAndSwap(zipData: Data, version: String) {
        let fileManager = FileManager.default
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("zonic-update-\(UUID().uuidString)", isDirectory: true)
        let zipFile = work.appendingPathComponent("release.zip")
        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)

        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
            try zipData.write(to: zipFile)
        } catch {
            fail("Could not prepare the update", error.localizedDescription)
            return
        }

        guard Updater.unzip(zipFile, into: unpacked) else {
            fail("Could not unpack the update", "The archive did not expand.")
            return
        }

        guard let newApp = (try? fileManager.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" }) else {
            fail("Could not unpack the update", "The archive did not contain an app.")
            return
        }

        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()

        guard fileManager.isWritableFile(atPath: parent.path) else {
            panel?.close()
            panel = nil
            isInstalling = false
            NSWorkspace.shared.activateFileViewerSelecting([newApp])
            warn(
                "This copy of Zonic cannot update itself",
                "\(target.deletingLastPathComponent().path) is not writable by this account. The new version is in the Finder window that just opened; drag it over the old Zonic in Applications."
            )
            return
        }

        let script = work.appendingPathComponent("install.sh")
        let contents = """
        #!/bin/sh
        set -u
        APP="$1"
        SRC="$2"
        PID="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$APP.old"
        if mv "$APP" "$APP.old" 2>/dev/null; then
          if ditto "$SRC" "$APP"; then
            rm -rf "$APP.old"
          else
            rm -rf "$APP"
            mv "$APP.old" "$APP"
          fi
        else
          ditto "$SRC" "$APP"
        fi
        xattr -dr com.apple.quarantine "$APP" >/dev/null 2>&1
        open "$APP"
        """

        do {
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        } catch {
            fail("Could not stage the update", error.localizedDescription)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            target.path,
            newApp.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]

        do {
            try process.run()
        } catch {
            fail("Could not start the update", error.localizedDescription)
            return
        }

        panel?.setMessage("Restarting Zonic \(version)…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Helpers

    private func fetch(_ url: URL?, completion: @escaping (Data?) -> Void) {
        guard let url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async { completion(data) }
        }.resume()
    }

    private static func asset(named assets: [[String: Any]], matching test: (String) -> Bool) -> [String: Any]? {
        assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return test(name)
        }
    }

    static func expectedHash(for name: String, in sums: String) -> String? {
        for line in sums.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let file = String(parts[1]).replacingOccurrences(of: "./", with: "")
            if file == name { return String(parts[0]).lowercased() }
        }
        return nil
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { chunk in
                Int(chunk.prefix(while: { $0.isNumber })) ?? 0
            }
        }
        let left = parts(candidate)
        let right = parts(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func unzip(_ zip: URL, into directory: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, directory.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func fail(_ title: String, _ detail: String) {
        panel?.close()
        panel = nil
        isInstalling = false
        warn(title, detail)
    }

    private func warn(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func inform(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// Small floating panel so the download does not look like the app hung.
final class UpdatePanel: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(message: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 92),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        title = "Updating Zonic"
        level = .floating
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        guard let content = contentView else { return }

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        label.stringValue = message
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(spinner)
        content.addSubview(label)

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            spinner.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 20),
            spinner.heightAnchor.constraint(equalToConstant: 20),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setMessage(_ message: String) {
        label.stringValue = message
    }

    func show() {
        center()
        orderFrontRegardless()
    }
}
