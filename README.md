# Zonic

A small macOS desktop client for Amazon Music. It wraps the real Amazon Music web
player in a native WebKit window and adds the things the browser tab is missing: a
proper app you can keep in the dock, working media keys, Control Center / now-playing
integration, its own titlebar controls, and light, dark or system appearance.

Named the way Slick is named after Slack. Zonic, from Amazon and sonic. Roughly 1 MB
of binary, no Electron, no background daemons.

## Install

1. Download `Zonic-0.1.0.dmg` from the [latest release](../../releases/latest).
2. Open it and drag Zonic into Applications.
3. The build is signed ad-hoc rather than with an Apple Developer certificate, so
   Gatekeeper will complain the first time. Right click the app, choose **Open**, then
   **Open** again. Or run:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Zonic.app
   ```

4. Sign in with your Amazon account once. The session is stored in the app's own
   WebKit store, so you stay logged in.

Requires macOS 12 or newer, on Apple silicon or Intel.

## What it does

- **Native window, no browser chrome.** Custom titlebar with back, forward, reload,
  and the current track shown in the middle.
- **Media keys work.** Play, pause, next and previous from the keyboard, plus the
  buttons in Control Center.
- **Now playing.** Track, artist, album and artwork are published to the system so
  they show up in Control Center and the menu bar.
- **Space to play or pause**, unless you are typing in a search box.
- **Themes.** Match System, Light or Dark, from the titlebar button or View > Appearance.
- **Zoom** the interface with cmd + and cmd -, reset with cmd 0.
- External links open in your browser instead of inside the app.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Play / pause | space, or cmd P |
| Next track | cmd right arrow |
| Previous track | cmd left arrow |
| Reload | cmd R |
| Back / forward | cmd [ / cmd ] |
| Zoom in / out / reset | cmd = / cmd - / cmd 0 |
| Full screen | ctrl cmd F |

## Build from source

Needs Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/SmartSparkCoding/zonic
cd zonic
./scripts/build-app.sh          # produces dist/Zonic.app, .dmg and .zip
VERSION=0.2.0 ./scripts/build-app.sh
```

The workflow in `.github/workflows/build.yml` builds the universal binary on a macOS
runner and publishes a release on every push to `main`.

## How it works

- `Sources/Zonic/WebController.swift` owns the `WKWebView` pointed at
  `music.amazon.com`, with a persistent cookie store and a Safari user agent.
- `Sources/Zonic/Bridge.swift` is the injected JavaScript. It reads
  `navigator.mediaSession.metadata` and the audio element for state, and exposes
  `window.__zonic.command('play' | 'pause' | 'next' | 'previous')` for the native side.
- `Sources/Zonic/NowPlaying.swift` wires `MPRemoteCommandCenter` and
  `MPNowPlayingInfoCenter`.
- `Sources/Zonic/ChromeBar.swift` and `MainWindowController.swift` are the window.

## Known limitations

- Amazon can change its DOM at any time. Next and previous are found by matching
  `aria-label`, `title` and `data-testid`, with a looser substring fallback. If they
  ever stop responding, that matching in `Bridge.swift` is the thing to fix.
- Playback uses whatever media stack WebKit exposes. If Amazon ever insists on a DRM
  module WebKit does not ship, audio would need an Electron plus Widevine build
  instead.
- The app is not notarised, so the first launch needs the right click dance above.
- No offline downloads. Amazon does not expose them to the web player.

MIT licensed. Not affiliated with, endorsed by, or supported by Amazon.
