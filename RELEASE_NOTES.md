# Zonic 0.26

The page finally follows the theme.

### Page skinning done properly
The old skin flattened the page with universal selectors, which Amazon's generated class names out-specified, so almost nothing changed. There are now two engines, chosen in Settings under "Amazon Music page":

- Invert (default for custom palettes): flips the whole page and flips artwork back. It cannot miss, because it never looks at Amazon's markup.
- Tint: repaints the page from the palette with selectors that out-specify Amazon's classes. Closer to the palette, more likely to need a nudge after a redesign.

### Copy Page Markup
New item in the overflow menu. Copies a fingerprint of what the page is actually painted with, so the skin can be written against real class names instead of guesses.

### Also
- The skin now applies to every palette, including Match System.
- color-scheme is set, so scrollbars, form controls and menus match.
- Album art, video and canvases are excluded from every rule.
