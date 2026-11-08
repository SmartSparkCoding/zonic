Zonic stays signed in.

- **Login survives a restart.** The Amazon cookies are now copied to a small file in
  `~/Library/Application Support/Zonic/cookies.json` as they change, and put back into the
  webview before the first page load. WebKit's own store was losing the session between
  launches, usually because Amazon hands out session scoped auth cookies unless "Keep me
  signed in" is ticked, and cookie writes can be dropped when the app is killed during an
  update swap. Either way the login is restored now.
- Cookies are captured when a page finishes loading, when the app loses focus, and when it
  quits. The file is readable by your user only (`0600`) and never leaves the machine.
- **Copy Player Diagnostics** now also reports how many Amazon cookies are in the store
  and how many are in the vault, which is the quick way to tell whether a logout is the
  app's fault or Amazon's.
- **Last.fm fixes.** Scrobbling no longer depends on the page reporting a playhead: when
  it reports zero, a pause aware clock counts the listening instead, so a track still
  scrobbles at half way. The same song playing twice in one session scrobbles twice, which
  it did not before.
- **Send Test Scrobble** in Settings sends one scrobble immediately, ignoring the listening
  rules, and shows Last.fm's own answer. The last eight API answers are in the diagnostics
  dump too, so a refusal names its error code instead of failing quietly.

The app is ad-hoc signed, not notarised. On first launch, right click Zonic and
choose Open, or run:

    xattr -dr com.apple.quarantine /Applications/Zonic.app
