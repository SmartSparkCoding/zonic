Skipping works properly now, every theme repaints the page, and Zonic scrobbles to Last.fm.

- **Skipping inside a track.** The scrubber and the 10 second skip items now drive
  Amazon's own progress bar instead of poking the audio element. Amazon plays through
  MSE under DRM, where moving `currentTime` outside the buffered range gets clamped or
  stalls, which is why seeking felt dead before. The page reports which route worked,
  and the scrubber only moves when the playhead actually moved.
- **Getting to the next song when Amazon says no.** Amazon counts skip presses per hour
  against your account on their side, so no client can raise that number. What a client
  can do is end the track: when a skip is refused, Zonic runs the current song to its
  last half second, playback finishes naturally and the queue rolls on. On by default,
  toggle in Settings.
- **Every theme paints the page.** The skin no longer depends on Amazon's hashed class
  names. It flattens the site's fills, then repaints backgrounds, text, borders,
  controls, menus, dialogs, sliders and scrollbars from the palette. Album art and
  images are untouched. On by default now, still togglable.
- **Last.fm scrobbling.** Paste an API key and secret from last.fm/api/account/create,
  press Connect, approve Zonic in the browser, press Connect again. Now-playing pings on
  every track change, scrobbles at half the track or four minutes, and Playback > Love on
  Last.fm (cmd L) loves the current song.
- **Seeking on by default.** The scrubber and skip menu items no longer need to be
  switched on first.
- Settings grew a scrolling layout for the new sections.

The app is ad-hoc signed, not notarised. On first launch, right click Zonic and
choose Open, or run:

    xattr -dr com.apple.quarantine /Applications/Zonic.app
