This build adds themes, a built-in updater, a thinner top bar and optional seeking.

- **Updates in the app.** Zonic checks the release feed after launch, or on demand from
  Zonic > Check for Updates. It verifies the download against `SHA256SUMS.txt`, swaps
  the app bundle and reopens, so there is no dmg to manage.
- **Twelve themes.** Match System, Light, Dark, Gruvbox Dark, Nord, Catppuccin Mocha,
  Tokyo Night, Dracula, One Dark, Solarized Dark, AMOLED Black and Rose Pine. The
  titlebar and menus follow the palette, and Settings can tint the page to match, best
  effort, since Amazon owns that markup.
- **A 30pt titlebar.** Down from 44. Smaller controls, tighter spacing, less window
  taken up by chrome.
- **Faster transport.** The page now reports state four times a second instead of once,
  commands reuse the last matched button and repaint the UI on the click rather than on
  the next poll.
- **Settings window (cmd comma).** Theme picker with colour swatches, page skin toggle,
  automatic update check, and the scrubber toggle.
- **Optional scrubber and 10 second skips.** Off by default, in Settings. Amazon's own
  hourly skip limit is enforced on their servers per account, so nothing here can lift
  it; seeking is offered because Amazon allows it on some tracks and refuses it on
  others.
- Control Center still lists Zonic exactly once.

The app is ad-hoc signed, not notarised. On first launch, right click Zonic and
choose Open, or run:

    xattr -dr com.apple.quarantine /Applications/Zonic.app
