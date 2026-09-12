// Centralized OneSignal Website SDK integration.
window.PropIntelligenceOneSignal = (() => {
  const appId = "b7d55e15-969b-40c2-b7d4-62e6c201e7d9";
  const developmentHosts = new Set(["localhost", "127.0.0.1", "::1"]);
  const supportsWebPush = "Notification" in window
    && "serviceWorker" in navigator
    && "PushManager" in window;
  const legacySafariPermission = window.safari?.pushNotification?.permission;
  const hasBrokenLegacySafariApi = legacySafariPermission !== undefined
    && typeof legacySafariPermission !== "function";
  const enabled = !developmentHosts.has(window.location.hostname)
    && supportsWebPush
    && !hasBrokenLegacySafariApi;

  const unsupportedResult = () => Promise.resolve({
    supported: false,
    reason: developmentHosts.has(window.location.hostname)
      ? "development-host"
      : "unsupported-browser"
  });

  function loadSdk() {
    const script = document.createElement("script");
    script.src = "https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js";
    script.defer = true;
    script.dataset.piOneSignal = "true";
    script.addEventListener("error", () => {
      console.warn("OneSignal SDK could not be loaded in this browser.");
    }, { once: true });
    document.head.appendChild(script);
  }

  async function initialize(OneSignal) {
    await OneSignal.init({
      appId,
      serviceWorkerPath: "/workspace/OneSignalSDKWorker.js",
      serviceWorkerParam: { scope: "/workspace/" },
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
    if (!enabled) return unsupportedResult();
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

  if (enabled) {
    window.OneSignalDeferred = window.OneSignalDeferred || [];
    window.OneSignalDeferred.push(initialize);
    loadSdk();
  }
  return Object.freeze({
    appId,
    enabled,
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
