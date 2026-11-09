const themes = {
  gruvbox: {
    name: 'Gruvbox Dark',
    c: ['#282828', '#3c3836', '#ebdbb2', '#d5c4a1', '#8ec07c'],
    note: 'Warm charcoal with cream text and a green accent. The one the screenshots on this page use.'
  },
  nord: {
    name: 'Nord',
    c: ['#2e3440', '#3b4252', '#eceff4', '#d8dee9', '#88c0d0'],
    note: 'Cool slate blues with a frosty cyan accent. The quietest of the dark themes.'
  },
  catppuccin: {
    name: 'Catppuccin Mocha',
    c: ['#1e1e2e', '#313244', '#cdd6f4', '#bac2de', '#cba6f7'],
    note: 'Soft violet on deep indigo, with pastel text that stays readable at 11 point.'
  },
  tokyo: {
    name: 'Tokyo Night',
    c: ['#1a1b26', '#24283b', '#c0caf5', '#a9b1d6', '#7aa2f7'],
    note: 'Midnight blue with a bright ink accent. Good if you work late and hate white flashes.'
  },
  dracula: {
    name: 'Dracula',
    c: ['#282a36', '#44475a', '#f8f8f2', '#6272a4', '#bd93f9'],
    note: 'Purple on graphite. Loud in the accent, calm everywhere else.'
  },
  amoled: {
    name: 'AMOLED Black',
    c: ['#000000', '#121212', '#f2f2f2', '#a0a0a0', '#4dd4ac'],
    note: 'True black, for people who would rather the panel just stay off.'
  }
};

const chips = Array.from(document.querySelectorAll('.chip'));
const preview = document.getElementById('preview');
const nameEl = document.getElementById('preview-name');
const noteEl = document.getElementById('preview-note');

function show(key) {
  const theme = themes[key];
  if (!theme || !preview) return;

  preview.style.setProperty('--c1', theme.c[0]);
  preview.style.setProperty('--c2', theme.c[1]);
  preview.style.setProperty('--c3', theme.c[2]);
  preview.style.setProperty('--c4', theme.c[3]);
  preview.style.setProperty('--c5', theme.c[4]);

  if (nameEl) nameEl.textContent = theme.name;
  if (noteEl) noteEl.textContent = theme.note;

  chips.forEach((chip) => {
    chip.setAttribute('aria-pressed', String(chip.dataset.theme === key));
  });
}

chips.forEach((chip) => {
  chip.addEventListener('click', () => show(chip.dataset.theme));
});

// fade the sections in as they arrive, once each
const targets = document.querySelectorAll('.cell, .detail figure, .steps li, .theme-board');
targets.forEach((el) => el.classList.add('reveal'));

if ('IntersectionObserver' in window) {
  const watcher = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-in');
      watcher.unobserve(entry.target);
    });
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

  targets.forEach((el) => watcher.observe(el));
} else {
  targets.forEach((el) => el.classList.add('is-in'));
}
