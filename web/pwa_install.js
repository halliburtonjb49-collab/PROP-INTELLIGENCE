(() => {
  let installPrompt = null;

  const isIos = /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
    (/macintosh/i.test(window.navigator.userAgent) && window.navigator.maxTouchPoints > 1);

  const isStandalone = window.matchMedia('(display-mode: standalone)').matches ||
    window.navigator.standalone === true;
  const isDevelopmentHost = ['localhost', '127.0.0.1', '::1']
    .includes(window.location.hostname);

  const card = document.getElementById('pwa-install-card');
  const action = document.getElementById('pwa-install-action');
  const dismiss = document.getElementById('pwa-install-dismiss');
  const message = document.getElementById('pwa-install-message');
  const updateCard = document.getElementById('pwa-update-card');
  const updateAction = document.getElementById('pwa-update-action');

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

  if ('serviceWorker' in navigator && !isDevelopmentHost) {
    let refreshingForNewWorker = false;
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (refreshingForNewWorker) return;
      refreshingForNewWorker = true;
      const url = new URL(window.location.href);
      url.searchParams.set('release', '__PI_BUILD_VERSION__');
      window.location.replace(url.toString());
    });
    window.addEventListener('load', async () => {
      try {
        const registration = await navigator.serviceWorker.register(
          '/OneSignalSDKWorker.js',
          {scope: '/'},
        );
        await registration.update();
      } catch (error) {
        console.warn('PWA service worker registration failed.', error);
      }
    });
    navigator.serviceWorker.addEventListener('message', (event) => {
      if (event.data && event.data.type === 'PI_UPDATE_READY' && updateCard) {
        updateCard.style.display = 'flex';
      }
    });
  }

  if (updateAction) {
    updateAction.addEventListener('click', () => {
      const url = new URL(window.location.href);
      url.searchParams.set('release', '__PI_BUILD_VERSION__');
      window.location.replace(url.toString());
    });
  }

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
