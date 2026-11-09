# Zonic

A smaller, tidier build. Nothing new to learn, it just weighs less.

### Lighter
- The binary is now compiled for size and stripped of local symbols, so the download is smaller than the last release with no features taken out.
- Dead code from earlier versions is gone: an unused polling constant, a leftover compatibility shim, and a duplicated scroll view class.

### Also
- The lyrics screen and the settings window now share one flipped view instead of two copies of the same class.
- Release notes are no longer tied to a version number, since every build gets its own.
