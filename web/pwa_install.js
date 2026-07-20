(() => {
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true;
  if (isStandalone) return;

  const card = document.getElementById('pwa-install-card');
  const action = document.getElementById('pwa-install-action');
  const dismiss = document.getElementById('pwa-install-dismiss');
  const message = document.getElementById('pwa-install-message');
  if (!card || !action || !dismiss || !message) return;

  const dismissedKey = 'prop-intelligence-pwa-install-dismissed';
  const wasDismissed = window.localStorage.getItem(dismissedKey) === 'true';
  if (wasDismissed) return;

  let installPrompt = null;
  const show = () => { card.style.display = 'flex'; };
  const hide = () => { card.style.display = 'none'; };

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    installPrompt = event;
    message.textContent = 'Install PROP INTELLIGENCE for fast, full-screen access.';
    action.textContent = 'INSTALL';
    show();
  });

  const isIos = /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
    (/macintosh/i.test(window.navigator.userAgent) && window.navigator.maxTouchPoints > 1);
  if (isIos) {
    message.textContent = 'Install on iPhone: tap Share, then Add to Home Screen.';
    action.textContent = 'HOW TO';
    window.setTimeout(show, 2500);
  }

  action.addEventListener('click', async () => {
    if (installPrompt) {
      installPrompt.prompt();
      await installPrompt.userChoice;
      installPrompt = null;
      hide();
      return;
    }
    window.alert('In Safari, tap the Share button, then choose "Add to Home Screen."');
  });

  dismiss.addEventListener('click', () => {
    window.localStorage.setItem(dismissedKey, 'true');
    hide();
  });

  window.addEventListener('appinstalled', hide);
})();
