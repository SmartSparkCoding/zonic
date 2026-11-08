# Zonic

A small macOS desktop client for Amazon Music. It wraps the real Amazon Music web
player in a native WebKit window and adds the things the browser tab is missing: a
proper app you can keep in the dock, working media keys, Control Center / now-playing
integration, its own thin titlebar, themes, and updates that install themselves.

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

## Updating

Zonic checks the GitHub release feed a few seconds after launch and offers anything
newer. **Zonic > Check for Updates…** does it on demand. The update verifies the
download against the release `SHA256SUMS.txt`, then swaps the app bundle and reopens
it, so there is no dmg to drag around. Turn the automatic check off in
**Zonic > Settings…** (cmd comma).

To update by hand instead: quit Zonic, drag the new `Zonic.app` over the one in
Applications, reopen.

## What it does

- **Native window, no browser chrome.** A 30pt titlebar with back, forward, reload on
  the left and the current track in the middle.
- **Media keys work.** Play, pause, next and previous from the keyboard, plus the
  buttons in Control Center.
- **Now playing.** The page's own media session publishes the track, artist and
  artwork, so Control Center lists Zonic exactly once.
- **Space to play or pause**, unless you are typing in a search box.
- **Skip inside a track.** A scrubber in the titlebar and cmd shift left / right jump ten
  seconds. Seeking drives Amazon's own progress bar, because their DRM stream clamps
  currentTime jumps that fall outside the buffered range.
- **When Amazon refuses a skip** (they cap skips per account per hour on their side), Zonic
  finishes the current track so playback rolls on to the next song anyway. On by default.
- **Last.fm scrobbling.** Add an API key and secret, approve Zonic in the browser, and it
  pings now-playing and scrobbles at half the track. cmd L loves the current song.
- **Themes.** Match System, Light, Dark, Gruvbox Dark, Nord, Catppuccin Mocha, Tokyo
  Night, Dracula, One Dark, Solarized Dark, AMOLED Black and Rose Pine. The window
  chrome and menus follow the palette, and the page is repainted from it too: text,
  backgrounds, controls, menus, scrollbars. On by default, togglable in Settings.
- **Optional scrubber.** Settings adds a progress slider to the titlebar plus 10 second
  skips, for tracks Amazon lets you seek in.
- **Zoom** the interface with cmd + and cmd -, reset with cmd 0.
- External links open in your browser instead of inside the app.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Play / pause | space, or cmd P |
| Next track | cmd right arrow |
| Previous track | cmd left arrow |
| Skip forward / back 10s | shift cmd right / left |
| Reload | cmd R |
| Back / forward | cmd [ / cmd ] |
| Zoom in / out / reset | cmd = / cmd - / cmd 0 |
| Settings | cmd , |
| Full screen | ctrl cmd F |

## Build from source

Needs Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/SmartSparkCoding/zonic
cd zonic
./scripts/build-app.sh          # produces build/Zonic.app, dist/*.dmg and .zip
VERSION=0.2.0 ./scripts/build-app.sh
```

The workflow in `.github/workflows/build.yml` builds the universal binary on a macOS
runner and publishes a release on every push to `main`.

## How it works

- `Sources/Zonic/WebController.swift` owns the `WKWebView` pointed at
  `music.amazon.com`, with a persistent cookie store and a Safari user agent.
- `Sources/Zonic/Bridge.swift` is the injected JavaScript. It reads
  `navigator.mediaSession.metadata` and the audio element for state, reports back four
  times a second, and exposes `window.__zonic` with `command`, `seekTo`, `seekBy` and
  `tick`.
- `Sources/Zonic/Updater.swift` talks to the GitHub releases API, verifies the checksum
  and hands the bundle swap to a short shell script that waits for the app to quit.
- `Sources/Zonic/Theme.swift` holds the palettes and the optional page skin.
- `Sources/Zonic/ChromeBar.swift`, `MainWindowController.swift` and
  `SettingsWindowController.swift` are the window and its settings.

## Known limitations

- Amazon caps how many tracks you can skip per hour on its own servers, per account and
  plan. No client side change can lift that; Zonic only makes each skip register
  immediately. Seeking inside a track is offered as an option because Amazon refuses it
  on some content.
- Amazon can change its DOM at any time. Next and previous are found by matching
  `aria-label`, `title` and `data-testid`, with a looser substring fallback. If they
  ever stop responding, that matching in `Bridge.swift` is the thing to fix.
- The page skin is a best-effort tint over markup Amazon owns, so it can look patchy.
  It is off by default.
- Playback uses whatever media stack WebKit exposes. If Amazon ever insists on a DRM
  module WebKit does not ship, audio would need an Electron plus Widevine build
  instead.
- The app is not notarised, so the first launch needs the right click dance above.
- No offline downloads. Amazon does not expose them to the web player.

MIT licensed. Not affiliated with, endorsed by, or supported by Amazon.
