import Foundation

/// JavaScript injected into the Amazon Music page. It reports playback state to the
/// native side and exposes `window.__zonic` so the media keys, menu bar and window
/// chrome can drive the page.
///
/// The bridge is deliberately chatty (250ms) and keeps the last matched control node
/// around: commands then land in the same frame as the click, instead of a second later.
enum Bridge {
    /// How often the page reports back. Fast enough that the title and scrubber feel live.
    static let pollMilliseconds = 250

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
        var media = mediaElement();
        if (media) { return !media.paused && !media.ended; }
        return false;
      };

      var mediaElement = function () {
        var list = document.querySelectorAll('audio, video');
        var i;
        for (i = 0; i < list.length; i++) {
          if (isFinite(list[i].duration) && list[i].duration > 0) { return list[i]; }
        }
        return list.length ? list[0] : null;
      };

      var readPosition = function () {
        var media = mediaElement();
        if (!media) { return { position: 0, duration: 0, canSeek: false }; }
        var duration = isFinite(media.duration) ? media.duration : 0;
        var position = isFinite(media.currentTime) ? media.currentTime : 0;
        return {
          position: position,
          duration: duration,
          canSeek: duration > 0 && media.seekable !== undefined && media.seekable.length > 0
        };
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

      var isDisabled = function (node) {
        return node.disabled === true || node.getAttribute('aria-disabled') === 'true';
      };

      // Last known node per action. Amazon re-renders the transport bar on track change,
      // so the cache is checked for liveness before it is trusted.
      var cache = {};

      var findControl = function (name, ignoreCache) {
        var exact = EXACT[name];
        if (!exact) { return null; }

        var cached = cache[name];
        if (!ignoreCache && cached && cached.isConnected && !isDisabled(cached) && exact.test(labelOf(cached))) {
          return cached;
        }

        var nodes = Array.prototype.slice.call(
          document.querySelectorAll('button, [role="button"], [data-testid]')
        );
        var i;
        for (i = 0; i < nodes.length; i++) {
          if (isDisabled(nodes[i])) { continue; }
          if (exact.test(labelOf(nodes[i]))) { cache[name] = nodes[i]; return nodes[i]; }
        }
        for (i = 0; i < nodes.length; i++) {
          if (isDisabled(nodes[i])) { continue; }
          var label = labelOf(nodes[i]);
          if (label.indexOf('playlist') !== -1) { continue; }
          if (label.indexOf(name) !== -1) { cache[name] = nodes[i]; return nodes[i]; }
        }
        return null;
      };

      var tick = function () {
        var media = readMedia();
        var progress = readPosition();
        post({
          title: (media && media.title) || document.title || '',
          artist: (media && media.artist) || '',
          album: (media && media.album) || '',
          artwork: (media && media.artwork) || null,
          playing: readPlaying(),
          editing: isEditable(),
          position: progress.position,
          duration: progress.duration,
          canSeek: progress.canSeek
        });
      };

      window.__zonic = {
        command: function (action) {
          var target = action === 'toggle' ? (readPlaying() ? 'pause' : 'play') : action;
          var node = findControl(target, false);
          if (!node) { cache = {}; node = findControl(target, true); }
          if (!node) { return 'missing'; }
          node.click();
          // Report back immediately so the UI moves with the click, not with the next poll.
          tick();
          return 'clicked';
        },
        seekTo: function (seconds) {
          var media = mediaElement();
          if (!media || !isFinite(media.duration) || media.duration <= 0) { return false; }
          media.currentTime = Math.max(0, Math.min(media.duration - 0.5, seconds));
          tick();
          return true;
        },
        seekBy: function (delta) {
          var media = mediaElement();
          if (!media || !isFinite(media.duration) || media.duration <= 0) { return false; }
          return window.__zonic.seekTo((media.currentTime || 0) + delta);
        },
        tick: tick
      };

      tick();
      setInterval(tick, 250);
      document.addEventListener('visibilitychange', tick);
      window.addEventListener('focus', tick);
    })();
    """#
}
