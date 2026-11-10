# Zonic for Windows

The same idea as the Mac app, built the way Windows wants it: a WPF window with a
WebView2 control pointed at `music.amazon.com`, a 34 point bar of its own above it, and
the same injected script driving playback.

Not a port of the Swift code. Windows has no AppKit, so the window, the theme system, the
media keys, the updater and the Last.fm client are all written again in C#. What is shared
is the part that took the longest to get right: `Bridge.js`, the script that finds Amazon's
own controls and drives them, is the same file the Mac build injects.

## What works

- Amazon Music in a WebView2 window, signed in, with the profile kept on disk so you stay
  signed in between launches
- A 34 point title bar: back, forward, reload, what is playing, a scrubber, lyrics, theme,
  and a menu
- Media keys (play/pause, next, previous) caught with a low level hook, because WebView2
  does not register with the Windows media flyout
- Space to play or pause, Ctrl+Shift+L for lyrics, Ctrl+, for settings, Ctrl+= / Ctrl+- /
  Ctrl+0 for zoom, F5 to reload, Alt+Left and Alt+Right to navigate
- The same twelve themes as the Mac build, and the same three page skin modes: off, tint,
  invert
- Seeking through Amazon's own progress slider, plus the skip fallback that ends a track
  when a skip is refused
- Crossfade, as a fade out then a fade in, because two DRM streams cannot play at once
- Lyrics from LRCLIB, timed, with the current line in the accent colour, click a line to
  seek, cached on disk
- Last.fm: now playing, scrobbles, love, a test scrobble that shows Last.fm's exact answer,
  and the last eight API responses in the diagnostics
- Updates: checks GitHub, downloads the Windows zip, and swaps the app folder from a batch
  file that waits for the process to exit
- A What's New window, once per version

## What is different from the Mac build

- **Size.** The Mac app is about 1 MB because it is a thin Swift binary using the system
  WebKit. A self-contained WPF build carries the .NET runtime, so it is about 66 MB. A
  framework-dependent build is about 2 MB but needs the .NET 8 Desktop Runtime installed.
  The release ships the self-contained one so it just runs.
- **Media keys** are a global hook rather than a system media session, so Zonic takes them
  while it is running and the Windows media flyout will not show the track.
- **No notarisation equivalent.** Windows SmartScreen will warn on first run because the
  exe is unsigned. More info, then Run anyway.

## Build it

```powershell
# from the repo root
dotnet publish windows/Zonic.Windows/Zonic.Windows.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:EnableCompressionInSingleFile=true -p:DebugType=none `
  -o dist-windows
```

Or `./windows/build.ps1`, which does the same and zips the result.

The project also builds on Linux and macOS with `EnableWindowsTargeting`, which is how CI
and the maintainer check that it compiles without a Windows machine. It cannot be *run*
anywhere but Windows.

## Requirements

- Windows 10 1809 or later, Windows 11 recommended
- The WebView2 runtime. Windows 11 has it. On Windows 10 you may need the Evergreen
  runtime from Microsoft, which is a small download.
