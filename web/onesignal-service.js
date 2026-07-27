// Centralized OneSignal Website SDK integration.
window.PropIntelligenceOneSignal = (() => {
  const appId = "917b088b-4a9f-472d-8b52-3ab0d06ab98e";

  async function initialize(OneSignal) {
    await OneSignal.init({
      appId,
      serviceWorkerPath: "OneSignalSDKWorker.js",
      serviceWorkerParam: { scope: "/" },
      notifyButton: { enable: false },
      allowLocalhostAsSecureOrigin: true
    });

    const modal = document.getElementById("onesignal-verification");
    const button = document.getElementById("onesignal-verification-button");
    if (!modal || !button || Notification.permission !== "default") return;
    modal.hidden = false;
    button.addEventListener("click", async () => {
      modal.hidden = true;
      await OneSignal.Notifications.requestPermission();
    }, { once: true });
  }

  function withOneSignal(action) {
    return new Promise((resolve, reject) => {
      window.OneSignalDeferred = window.OneSignalDeferred || [];
      window.OneSignalDeferred.push(async (OneSignal) => {
        try {
          resolve(await action(OneSignal));
        } catch (error) {
          reject(error);
        }
      });
    });
  }

  window.OneSignalDeferred = window.OneSignalDeferred || [];
  window.OneSignalDeferred.push(initialize);
  return Object.freeze({
    appId,
    requestPermission: () => withOneSignal(
      (OneSignal) => OneSignal.Notifications.requestPermission()
    ),
    login: (externalId) => withOneSignal(
      (OneSignal) => OneSignal.login(externalId)
    ),
    logout: () => withOneSignal((OneSignal) => OneSignal.logout()),
    setEmail: (email) => withOneSignal(
      (OneSignal) => OneSignal.User.addEmail(email)
    ),
    setTag: (key, value) => withOneSignal(
      (OneSignal) => OneSignal.User.addTag(key, value)
    )
  });
})();
