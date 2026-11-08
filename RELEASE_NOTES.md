First release of Zonic, a lightweight macOS client for Amazon Music.

- Native WebKit window pointed at the Amazon Music web player, with the session
  persisted so you sign in once.
- Custom titlebar: back, forward, reload, current track, appearance and a small
  overflow menu.
- Working media keys and Control Center controls via MPRemoteCommandCenter.
- Now playing metadata and artwork published to the system.
- Space to play or pause when you are not typing.
- Light, dark and system appearance, plus interface zoom.
- Universal build for Apple silicon and Intel, macOS 12 and up.

The app is ad-hoc signed, not notarised. On first launch, right click Zonic and
choose Open, or run:

    xattr -dr com.apple.quarantine /Applications/Zonic.app
