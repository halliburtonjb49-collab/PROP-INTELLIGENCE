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
    if (!modal || !button || localStorage.getItem("onesignalVerified")) return;
    modal.hidden = false;
    button.addEventListener("click", async () => {
      modal.hidden = true;
      localStorage.setItem("onesignalVerified", "true");
      await OneSignal.Notifications.requestPermission();
    }, { once: true });
  }

  window.OneSignalDeferred = window.OneSignalDeferred || [];
  window.OneSignalDeferred.push(initialize);
  return Object.freeze({ appId });
})();
