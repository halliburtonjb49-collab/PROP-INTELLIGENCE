(() => {
  let installPrompt = null;

  const isIos = /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
    (/macintosh/i.test(window.navigator.userAgent) && window.navigator.maxTouchPoints > 1);

  const isStandalone = window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true;

  const card = document.getElementById('pwa-install-card');
  const action = document.getElementById('pwa-install-action');
  const dismiss = document.getElementById('pwa-install-dismiss');
  const message = document.getElementById('pwa-install-message');

  const dismissedKey = 'prop-intelligence-pwa-install-dismissed';
  const wasDismissed = window.localStorage.getItem(dismissedKey) === 'true';

  const show = () => { if (card) card.style.display = 'flex'; };
  const hide = () => { if (card) card.style.display = 'none'; };

  window.addEventListener('beforeinstallprompt', (event) => {
    event.preventDefault();
    installPrompt = event;
    if (!isStandalone && !wasDismissed && card && action && message) {
      message.textContent = 'Install PROP INTELLIGENCE for fast, full-screen access.';
      action.textContent = 'INSTALL';
      show();
    }
  });

  if (isIos && !isStandalone && !wasDismissed && card && action && message) {
    message.textContent = 'Install on iPhone: tap Share, then Add to Home Screen.';
    action.textContent = 'HOW TO';
    window.setTimeout(show, 2500);
  }

  if (action) {
    action.addEventListener('click', async () => {
      if (installPrompt) {
        await window.triggerPwaInstall();
        return;
      }
      window.alert('In Safari, tap the Share button, then choose "Add to Home Screen."');
    });
  }

  if (dismiss) {
    dismiss.addEventListener('click', () => {
      window.localStorage.setItem(dismissedKey, 'true');
      hide();
    });
  }

  window.addEventListener('appinstalled', hide);

  // Bridge for the Flutter app: lets any in-app "install" button trigger the
  // same native prompt captured above, instead of only the floating card.
  window.isPwaInstallAvailable = () => installPrompt !== null;
  window.isIosPwaDevice = () => isIos && !isStandalone;
  window.triggerPwaInstall = async () => {
    if (!installPrompt) return 'unavailable';
    installPrompt.prompt();
    const choice = await installPrompt.userChoice;
    installPrompt = null;
    hide();
    return choice.outcome;
  };
})();
