import Foundation

/// JavaScript injected into the Amazon Music page. It reports playback state to the
/// native side and exposes `window.__zonic.command(...)` so the media keys, menu bar
/// and window chrome can drive the page.
enum Bridge {
    static let injectedScript = #"""
    (function () {
      if (window.__zonic) { return; }

      var post = function (body) {
        try { window.webkit.messageHandlers.zonicState.postMessage(body); } catch (e) {}
      };

      var isEditable = function () {
        var el = document.activeElement;
        if (!el) { return false; }
        var tag = (el.tagName || '').toLowerCase();
        if (tag === 'input' || tag === 'textarea' || tag === 'select') { return true; }
        if (el.isContentEditable) { return true; }
        return false;
      };

      var readMedia = function () {
        try {
          var session = navigator.mediaSession;
          var meta = session && session.metadata;
          if (!meta) { return null; }
          var art = null;
          if (meta.artwork && meta.artwork.length) {
            art = meta.artwork[meta.artwork.length - 1].src || null;
          }
          return {
            title: meta.title || '',
            artist: meta.artist || '',
            album: meta.album || '',
            artwork: art
          };
        } catch (e) { return null; }
      };

      var readPlaying = function () {
        try {
          var session = navigator.mediaSession;
          if (session && (session.playbackState === 'playing' || session.playbackState === 'paused')) {
            return session.playbackState === 'playing';
          }
        } catch (e) {}
        var media = document.querySelector('audio, video');
        if (media) { return !media.paused && !media.ended; }
        return false;
      };

      var EXACT = {
        play: /^(play|resume|play song|play music|start playing)$/,
        pause: /^(pause|pause song|pause music)$/,
        next: /^(next|next track|next song|skip forward|skip to next|skip next)$/,
        previous: /^(previous|previous track|previous song|skip back|skip backward|skip to previous|prev)$/
      };

      var labelOf = function (node) {
        return [
          node.getAttribute('aria-label'),
          node.getAttribute('title'),
          node.getAttribute('data-testid'),
          node.getAttribute('name')
        ].filter(Boolean).join(' ').toLowerCase().replace(/\s+/g, ' ').trim();
      };

      var candidates = function () {
        return Array.prototype.slice.call(
          document.querySelectorAll('button, [role="button"], [data-testid]')
        );
      };

      var isDisabled = function (node) {
        return node.disabled === true || node.getAttribute('aria-disabled') === 'true';
      };

      var findControl = function (name) {
        var exact = EXACT[name];
        if (!exact) { return null; }
        var nodes = candidates();
        var i;
        for (i = 0; i < nodes.length; i++) {
          if (isDisabled(nodes[i])) { continue; }
          if (exact.test(labelOf(nodes[i]))) { return nodes[i]; }
        }
        for (i = 0; i < nodes.length; i++) {
          if (isDisabled(nodes[i])) { continue; }
          var label = labelOf(nodes[i]);
          if (label.indexOf('playlist') !== -1) { continue; }
          if (label.indexOf(name) !== -1) { return nodes[i]; }
        }
        return null;
      };

      window.__zonic = {
        command: function (action) {
          var target = action === 'toggle' ? (readPlaying() ? 'pause' : 'play') : action;
          var node = findControl(target);
          if (!node) { return 'missing'; }
          node.click();
          return 'clicked';
        }
      };

      var tick = function () {
        var media = readMedia();
        post({
          title: (media && media.title) || document.title || '',
          artist: (media && media.artist) || '',
          album: (media && media.album) || '',
          artwork: (media && media.artwork) || null,
          playing: readPlaying(),
          editing: isEditable()
        });
      };

      tick();
      setInterval(tick, 1000);
      document.addEventListener('visibilitychange', tick);
      window.addEventListener('focus', tick);
    })();
    """#
}
