/* Detect a newer game without touching Godot's IndexedDB saves. */
(() => {
  'use strict';
  const current = document.querySelector('meta[name="game-build"]')?.content;
  if (!current) return;
  const base = new URL('./', location.href);
  let banner;
  let checking = false;

  async function updateWorker() {
    if (!('serviceWorker' in navigator)) return;
    const registration = await navigator.serviceWorker.getRegistration(base.href);
    if (!registration) return;
    await registration.update();
    const worker = registration.installing || registration.waiting;
    if (!worker || worker.state === 'activated') return;
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Обновление ещё загружается. Попробуйте снова.')), 30000);
      const done = () => {
        if (worker.state === 'activated') { clearTimeout(timer); resolve(); }
        else if (worker.state === 'redundant') { clearTimeout(timer); reject(new Error('Не удалось загрузить обновление.')); }
      };
      worker.addEventListener('statechange', done);
      worker.postMessage('claim');
      done();
    });
  }

  async function check() {
    if (checking || document.hidden || banner) return;
    checking = true;
    try {
      const response = await fetch(new URL('version.json', base), { cache: 'no-store' });
      if (!response.ok) return;
      const latest = await response.json();
      if (!/^[0-9a-f]{7,40}$/.test(latest.commit) || latest.commit === current) return;
      banner = document.createElement('button');
      banner.type = 'button';
      banner.textContent = 'Доступна новая версия · Обновить';
      Object.assign(banner.style, {
        position: 'fixed', top: 'max(8px, env(safe-area-inset-top))', left: '50%', transform: 'translateX(-50%)',
        zIndex: '100', padding: '12px 18px', minHeight: '44px', maxWidth: '90vw', border: '2px solid #ffb630',
        borderRadius: '10px', background: '#2c3346', color: '#f3f5fa', font: 'bold 16px sans-serif', cursor: 'pointer',
      });
      banner.onclick = async () => {
        banner.disabled = true;
        banner.textContent = 'Загружаем обновление…';
        try {
          await updateWorker();
          const next = new URL(location.href);
          next.searchParams.set('v', latest.commit.slice(0, 12));
          location.assign(next.href);
        } catch (error) {
          banner.disabled = false;
          banner.textContent = error.message + ' Нажмите повторно.';
        }
      };
      document.body.appendChild(banner);
    } catch (_) {
      // Offline play remains available; check again when the connection returns.
    } finally { checking = false; }
  }
  check();
  setInterval(check, 60000);
  window.addEventListener('online', check);
  document.addEventListener('visibilitychange', check);
})();
