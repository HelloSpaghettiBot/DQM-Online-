"use strict";
const safe = (tag, text, className) => {
  const el = document.createElement(tag);
  if (text !== undefined) el.textContent = text;
  if (className) el.className = className;
  return el;
};
async function loadStatus() {
  try {
    const response = await fetch('/DQM/api/status', {cache: 'no-store'});
    if (!response.ok) throw new Error('Status unavailable');
    const status = await response.json();
    document.querySelectorAll('[data-server-status]').forEach(el => el.textContent = status.online ? 'Alpha server online' : 'Server temporarily offline');
    document.querySelectorAll('[data-player-count]').forEach(el => el.textContent = String(status.players));
    document.querySelectorAll('.status-strip').forEach(el => el.classList.toggle('online', status.online));
    const downloads = document.getElementById('downloads');
    if (downloads) {
      downloads.replaceChildren();
      for (const platform of ['Windows', 'Linux', 'Android']) {
        const release = (status.downloads || []).find(item => item.platform === platform);
        const row = safe('div', undefined, 'download-row');
        row.append(safe('span', platform, 'download-title'));
        row.append(safe('span', release ? release.description : 'Build in preparation', 'download-meta'));
        if (release && /^\/DQM\/downloads\/[A-Za-z0-9_.-]+$/.test(release.url)) {
          const link = safe('a', 'Download ↓', 'button');
          link.href = release.url;
          link.setAttribute('download', '');
          link.setAttribute('aria-label', `Download ${platform} client`);
          row.append(link);
        } else row.append(safe('span', 'Coming soon', 'unavailable'));
        downloads.append(row);
      }
    }
  } catch (_) {
    document.querySelectorAll('[data-server-status]').forEach(el => el.textContent = 'Status unavailable');
    const downloads = document.getElementById('downloads');
    if (downloads && !downloads.querySelector('.download-row')) downloads.textContent = 'Downloads are temporarily unavailable. Please try again shortly.';
  }
}
loadStatus();
setInterval(loadStatus, 30000);
const form = document.getElementById('account-form');
if (form) {
  let mode = 'register';
  const tabs = document.querySelectorAll('[data-mode]');
  const confirmField = document.getElementById('confirm-field');
  const confirmInput = document.getElementById('confirm');
  const password = document.getElementById('password');
  const message = document.getElementById('form-message');
  const submit = form.querySelector('button[type=submit]');
  tabs.forEach(tab => tab.addEventListener('click', () => {
    mode = tab.dataset.mode;
    tabs.forEach(item => item.setAttribute('aria-selected', String(item === tab)));
    confirmField.hidden = mode !== 'register';
    confirmInput.required = mode === 'register';
    password.autocomplete = mode === 'register' ? 'new-password' : 'current-password';
    submit.textContent = mode === 'register' ? 'Create my account ↗' : 'Sign in ↗';
    message.textContent = '';
  }));
  form.addEventListener('submit', async event => {
    event.preventDefault();
    message.classList.remove('error');
    if (mode === 'register' && password.value !== confirmInput.value) {
      message.textContent = 'The passwords do not match.';
      message.classList.add('error');
      return;
    }
    submit.disabled = true;
    message.textContent = mode === 'register' ? 'Creating your account…' : 'Signing in…';
    try {
      const response = await fetch(`/DQM/api/${mode}`, {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({username: form.elements.username.value, password: password.value})});
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Please try again.');
      message.textContent = mode === 'register' ? result.message : `Signed in as ${result.username}. Open the game client and use the same account and password to play.`;
      password.value = '';
      confirmInput.value = '';
      // The one-use game ticket stays in memory and is never persisted by the website.
    } catch (error) {
      message.textContent = error.message || 'Unable to connect. Please try again.';
      message.classList.add('error');
    } finally { submit.disabled = false; }
  });
}
