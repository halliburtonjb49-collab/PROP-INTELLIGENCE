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
  const layoutMode = document.getElementById('pwa-layout-mode');
  const updateCard = document.getElementById('pwa-update-card');
  const updateAction = document.getElementById('pwa-update-action');

  const dismissedKey = 'prop-intelligence-pwa-install-dismissed';
  const wasDismissed = window.localStorage.getItem(dismissedKey) === 'true';
  const layoutKey = 'prop-intelligence-layout-mode';
  const detectedLayout = window.innerWidth >= 600 && window.innerWidth < 1000
    ? 'tablet'
    : 'mobile';
  if (layoutMode) {
    layoutMode.value = window.localStorage.getItem(layoutKey) || 'auto';
    layoutMode.addEventListener('change', () => {
      window.localStorage.setItem(layoutKey, layoutMode.value);
    });
  }

  const show = () => { if (card) card.style.display = 'flex'; };
  const hide = () => { if (card) card.style.display = 'none'; };
  const showUpdate = () => { if (updateCard) updateCard.style.display = 'flex'; };
  const hideUpdate = () => { if (updateCard) updateCard.style.display = 'none'; };
  let workspaceRegistration = null;

  const getWorkspaceRegistration = async () => {
    if (workspaceRegistration) return workspaceRegistration;
    const registration = await navigator.serviceWorker.getRegistration('/workspace/');
    if (registration) workspaceRegistration = registration;
    return registration;
  };

  const reloadCurrentRelease = () => {
    const url = new URL(window.location.href);
    url.searchParams.set('release', '__PI_BUILD_VERSION__');
    window.location.replace(url.toString());
  };

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
      hideUpdate();
      reloadCurrentRelease();
    });
    window.addEventListener('load', async () => {
      try {
        const registration = await navigator.serviceWorker.register(
          '/workspace/OneSignalSDKWorker.js',
          {scope: '/workspace/', updateViaCache: 'none'},
        );
        workspaceRegistration = registration;
        if (registration.waiting) showUpdate();
        registration.addEventListener('updatefound', () => {
          const worker = registration.installing;
          if (!worker) return;
          worker.addEventListener('statechange', () => {
            if (worker.state === 'installed' && navigator.serviceWorker.controller) showUpdate();
          });
        });
        await registration.update();
      } catch (error) {
        console.warn('PWA service worker registration failed.', error);
      }
    });
  }

  if (updateAction) {
    updateAction.addEventListener('click', async () => {
      updateAction.disabled = true;
      updateAction.textContent = 'UPDATING';
      try {
        const registration = await getWorkspaceRegistration();
        if (!registration) {
          reloadCurrentRelease();
          return;
        }
        if (!registration.waiting) {
          await registration.update();
        }
        if (registration.waiting) {
          registration.waiting.postMessage({type: 'PI_ACTIVATE_UPDATE'});
          // A damaged older worker may not understand the activation message.
          // Reload rather than leaving the button permanently disabled.
          window.setTimeout(reloadCurrentRelease, 4000);
          return;
        }
        hideUpdate();
        reloadCurrentRelease();
      } catch (error) {
        console.warn('PWA update activation failed.', error);
        updateAction.disabled = false;
        updateAction.textContent = 'RETRY UPDATE';
      }
    });
  }

  // Bridge for the Flutter app: lets any in-app "install" button trigger the
  // same native prompt captured above, instead of only the floating card.
  window.isPwaInstallAvailable = () => installPrompt !== null;
  window.isIosPwaDevice = () => isIos && !isStandalone;
  window.triggerPwaInstall = async () => {
    if (layoutMode) window.localStorage.setItem(layoutKey, layoutMode.value);
    if (!installPrompt) return 'unavailable';
    installPrompt.prompt();
    const choice = await installPrompt.userChoice;
    installPrompt = null;
    hide();
    return choice.outcome;
  };
  window.piPreferredLayout = () =>
    window.localStorage.getItem(layoutKey) || 'auto';
})();
