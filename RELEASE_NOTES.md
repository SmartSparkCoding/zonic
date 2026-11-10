# Zonic

The What's New window actually shows what's new now.

### Fixed
- The window used to open blank. It was handing a zero sized text view to a scroll view, and a scroll view will not grow its document view, so there was nothing to draw. The notes were in the bundle the whole time.
- Long notes scroll and reflow when you resize the window.

### New
- The window now reads the release's own notes from GitHub for the exact version you are running, then lists the commits that went into that build, so two releases no longer show identical text. Cached per version, so it works offline afterwards and opens instantly the second time.
- A "View release" button that opens that version's page on GitHub.
- Bold in the notes renders as bold instead of raw asterisks.
