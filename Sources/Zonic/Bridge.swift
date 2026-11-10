import Foundation

/// JavaScript injected into the Amazon Music page. It reports playback state to the
/// native side and exposes `window.__zonic` so the media keys, menu bar and window
/// chrome can drive the page.
///
/// The bridge is deliberately chatty (250ms) and keeps the last matched control node
/// around: commands then land in the same frame as the click, instead of a second later.
///
/// Seeking goes through the site's own progress slider rather than
/// `audio.currentTime`. Amazon plays through MSE under DRM, where a jump outside the
/// buffered range is clamped or stalls, and the slider is the path their player expects.
enum Bridge {
    static let injectedScript = #"""
    (function () {
      if (window.__zonic) { return; }

      // Native settings, refreshed whenever the user changes them.
      window.__zonicOptions = window.__zonicOptions || { finishTrack: true };

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

      var duration = function () {
        var media = mediaElement();
        if (media && isFinite(media.duration) && media.duration > 0) { return media.duration; }
        var slider = seekSlider();
        if (slider) {
          var max = parseFloat(slider.getAttribute('aria-valuemax') || slider.max || '0');
          if (isFinite(max) && max > 0) { return max; }
        }
        return 0;
      };

      var readPosition = function () {
        var media = mediaElement();
        if (media && isFinite(media.duration) && media.duration > 0) {
          return {
            position: isFinite(media.currentTime) ? media.currentTime : 0,
            duration: media.duration,
            canSeek: true
          };
        }
        var slider = seekSlider();
        if (slider) {
          var now = parseFloat(slider.getAttribute('aria-valuenow') || slider.value || '0');
          var max = parseFloat(slider.getAttribute('aria-valuemax') || slider.max || '0');
          if (isFinite(now) && isFinite(max) && max > 0) {
            return { position: now, duration: max, canSeek: true };
          }
        }
        return { position: 0, duration: 0, canSeek: false };
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

      // MARK: seeking

      /// Every element on the page that could be the progress bar, filtered to those with a
      /// sane size. Volume and zoom sliders are dropped: they are short and sit elsewhere.
      var sliderCandidates = function () {
        var nodes = document.querySelectorAll([
          'input[type="range"]',
          '[role="slider"]',
          '[data-testid*="progress" i]',
          '[data-testid*="seek" i]',
          '[aria-label*="progress" i]',
          '[aria-label*="seek" i]',
          '[aria-label*="position" i]',
          '[class*="progress" i]',
          '[class*="scrub" i]'
        ].join(', '));

        var out = [];
        for (var i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          var rect = el.getBoundingClientRect();
          if (rect.width < 80 || rect.height <= 0 || rect.height > 48) { continue; }
          var label = labelOf(el);
          if (label.indexOf('volume') !== -1) { continue; }
          out.push(el);
        }
        return out;
      };

      /// The transport bar's progress slider, which is the widest candidate in the bottom
      /// part of the window.
      var seekSlider = function () {
        var list = sliderCandidates();
        if (!list.length) { return null; }
        var bottom = window.innerHeight * 0.55;
        var best = null;
        var bestScore = -1;
        for (var i = 0; i < list.length; i++) {
          var rect = list[i].getBoundingClientRect();
          var score = rect.width + (rect.top >= bottom ? 500 : 0);
          if (score > bestScore) { bestScore = score; best = list[i]; }
        }
        return best;
      };

      var valueSlider = function () {
        var list = sliderCandidates();
        for (var i = 0; i < list.length; i++) {
          var tag = (list[i].tagName || '').toLowerCase();
          if (tag === 'input' && (list[i].type || '').toLowerCase() === 'range') { return list[i]; }
        }
        return null;
      };

      /// Sets a real range input, which fires the events React listens for.
      var setRangeValue = function (slider, fraction) {
        try {
          var min = parseFloat(slider.min || '0');
          var max = parseFloat(slider.max || '0');
          if (!isFinite(min)) { min = 0; }
          if (!isFinite(max) || max <= min) { return false; }
          var value = min + (max - min) * fraction;
          slider.focus();
          slider.value = String(value);
          slider.dispatchEvent(new Event('input', { bubbles: true }));
          slider.dispatchEvent(new Event('change', { bubbles: true }));
          return true;
        } catch (e) { return false; }
      };

      /// Drags a custom (div based) slider by sending the pointer sequence it listens for.
      var dragSlider = function (slider, fraction) {
        try {
          var rect = slider.getBoundingClientRect();
          var x = rect.left + Math.max(1, Math.min(rect.width - 1, rect.width * fraction));
          var y = rect.top + rect.height / 2;
          var base = {
            bubbles: true, cancelable: true, clientX: x, clientY: y,
            view: window, button: 0, buttons: 1, pointerId: 1,
            pointerType: 'mouse', isPrimary: true
          };
          var up = {
            bubbles: true, cancelable: true, clientX: x, clientY: y,
            view: window, button: 0, buttons: 0, pointerId: 1,
            pointerType: 'mouse', isPrimary: true
          };
          var send = function (type, opts) {
            var event;
            if (type.indexOf('pointer') === 0 && typeof PointerEvent === 'function') {
              event = new PointerEvent(type, opts);
            } else {
              event = new MouseEvent(type, opts);
            }
            slider.dispatchEvent(event);
          };
          send('pointerover', base);
          send('pointerdown', base);
          send('mousedown', base);
          send('pointermove', base);
          send('mousemove', base);
          send('pointerup', up);
          send('mouseup', up);
          send('click', up);
          return true;
        } catch (e) { return false; }
      };

      var seekTo = function (seconds) {
        var total = duration();
        if (!(total > 0)) { return 'unknown-duration'; }
        var target = Math.max(0, Math.min(total - 0.4, seconds));
        var fraction = total > 0 ? target / total : 0;

        var range = valueSlider();
        if (range && setRangeValue(range, fraction)) {
          verifySeek(target);
          return 'range';
        }

        var slider = seekSlider();
        if (slider && dragSlider(slider, fraction)) {
          verifySeek(target);
          return 'slider';
        }

        var media = mediaElement();
        if (media && isFinite(media.duration) && media.duration > 0) {
          try {
            media.currentTime = target;
            verifySeek(target);
            return 'media';
          } catch (e) {}
        }
        return 'missing';
      };

      /// Reports whether the playhead actually moved, so the native side can say so
      /// instead of pretending the scrub worked.
      var verifySeek = function (target) {
        window.__zonic.lastSeek = { target: target, at: Date.now(), ok: null };
        setTimeout(function () {
          var now = readPosition();
          var entry = window.__zonic.lastSeek;
          if (!entry || entry.target !== target) { return; }
          entry.ok = Math.abs((now.position || 0) - target) < 12;
          entry.position = now.position;
          tick();
        }, 900);
      };

      var trackKey = function () {
        var media = readMedia();
        if (!media) { return ''; }
        return (media.artist || '') + '|' + (media.title || '');
      };

      /// Runs the current track to its very end so playback advances on its own. Amazon
      /// counts skip presses against the hourly cap, not tracks that finish.
      var finishTrack = function () {
        var total = duration();
        if (!(total > 0)) { return false; }
        seekTo(total - 0.4);
        return true;
      };

      var press = function (action) {
        var node = findControl(action, false);
        if (!node) { cache = {}; node = findControl(action, true); }
        if (!node) { return null; }
        node.click();
        return node;
      };

      var skip = function (action) {
        var before = trackKey();
        if (!press(action)) { return 'missing'; }
        tick();

        // If the track has not changed a moment later, the skip was refused. Roll the
        // track to its end instead when the user allows it.
        setTimeout(function () {
          if (trackKey() !== before) { return; }
          if (!window.__zonicOptions || !window.__zonicOptions.finishTrack) { return; }
          finishTrack();
        }, 1400);

        return 'clicked';
      };

      // ---- Volume ramps ----
      // A true overlapping crossfade needs two decoders, which a DRM stream in a web view
      // cannot give us. This fades the tail of the outgoing track and the head of the
      // incoming one instead, with the length capped by what is actually left.
      var fadeBase = null;
      var fadeRun = null;
      // The volume we last wrote, so a change made in Amazon's own slider can be told
      // apart from our own ramp and adopted as the new base.
      var lastSetVolume = null;
      var fadingOut = false;

      var rampTo = function (target, seconds) {
        var node = mediaElement();
        if (!node) { return false; }
        if (fadeRun) { cancelAnimationFrame(fadeRun); fadeRun = null; }
        if (fadeBase === null) { fadeBase = node.volume; }
        var from = node.volume;
        var started = performance.now();
        var span = Math.max(80, (seconds || 0) * 1000);
        var step = function (now) {
          var t = Math.min(1, (now - started) / span);
          var value = from + (target - from) * t;
          var clamped = Math.max(0, Math.min(1, value));
          try { node.volume = clamped; } catch (e) {}
          lastSetVolume = clamped;
          fadeRun = t < 1 ? requestAnimationFrame(step) : null;
        };
        fadeRun = requestAnimationFrame(step);
        return true;
      };

      var crossfadeSeconds = function () {
        var options = window.__zonicOptions || {};
        var value = Number(options.crossfade || 0);
        return isFinite(value) && value > 0 ? Math.min(15, value) : 0;
      };

      var lastFadeKey = '';
      var applyFade = function (progress) {
        var seconds = crossfadeSeconds();
        var node = mediaElement();
        if (!node) { return; }
        // If nothing is ramping and the volume is not where we left it, the user moved
        // Amazon's own slider. Adopt that as the base instead of restoring a stale one.
        if (fadeRun === null && lastSetVolume !== null && Math.abs(node.volume - lastSetVolume) > 0.01) {
          fadeBase = node.volume;
          lastSetVolume = node.volume;
        }

        var key = trackKey();
        if (key !== lastFadeKey) {
          var changed = lastFadeKey !== '';
          lastFadeKey = key;
          fadingOut = false;
          if (changed && seconds > 0 && fadeBase !== null) {
            rampTo(fadeBase, Math.min(seconds, 3));
          }
          return;
        }
        if (!seconds || !(progress.duration > 0)) { fadingOut = false; return; }
        var remaining = progress.duration - progress.position;
        if (remaining > 0.2 && remaining <= seconds) {
          // tick() runs four times a second, so only arm the fade once. Re-arming it every
          // tick restarted the ramp from wherever it had got to and made it stutter.
          if (!fadingOut) {
            fadingOut = true;
            rampTo(0, remaining);
          }
        } else {
          fadingOut = false;
        }
      };

      var tick = function () {
        var media = readMedia();
        var progress = readPosition();
        applyFade(progress);
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
          if (action === 'toggle') { action = readPlaying() ? 'pause' : 'play'; }
          if (action === 'next' || action === 'previous') { return skip(action); }
          if (!press(action)) { return 'missing'; }
          tick();
          return 'clicked';
        },
        seekTo: seekTo,
        seekBy: function (delta) {
          var now = readPosition();
          var total = now.duration > 0 ? now.duration : duration();
          return seekTo((now.position || 0) + delta);
        },
        seekFraction: function (fraction) {
          var total = duration();
          if (!(total > 0)) { return 'unknown-duration'; }
          return seekTo(total * Math.max(0, Math.min(1, fraction)));
        },
        finishTrack: finishTrack,
        options: function (options) {
          window.__zonicOptions = window.__zonicOptions || {};
          for (var key in options) {
            if (!Object.prototype.hasOwnProperty.call(options, key)) { continue; }
            window.__zonicOptions[key] = options[key];
          }
          return window.__zonicOptions;
        },
        debug: function () {
          return {
            hasMedia: !!mediaElement(),
            duration: duration(),
            position: readPosition(),
            slider: (function () {
              var s = seekSlider();
              if (!s) { return null; }
              return {
                tag: s.tagName,
                role: s.getAttribute('role'),
                label: labelOf(s),
                rect: (function (r) {
                  return { w: Math.round(r.width), top: Math.round(r.top) };
                })(s.getBoundingClientRect())
              };
            })(),
            lastSeek: window.__zonic.lastSeek || null
          };
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
