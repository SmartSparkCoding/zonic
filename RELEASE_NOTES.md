This build fixes the duplicate entry in Control Center.

- Control Center now lists Zonic once. The WebKit page's own media session is the
  single owner of Now Playing, so the app no longer registers a second one.

Everything from 0.1.0 still applies:

- Native WebKit window pointed at the Amazon Music web player, with the session
  persisted so you sign in once.
- Custom titlebar: back, forward, reload, current track, appearance and a small
  overflow menu.
- Now playing metadata and artwork shown by the system, and the hardware media
  keys drive the page.
- Space to play or pause when you are not typing.
- Light, dark and system appearance, plus interface zoom.
- Universal build for Apple silicon and Intel, macOS 12 and up.

The app is ad-hoc signed, not notarised. On first launch, right click Zonic and
choose Open, or run:

    xattr -dr com.apple.quarantine /Applications/Zonic.app
