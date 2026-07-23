// Bridges to the native "Add to Home Screen" / PWA install prompt on web.
// Native platforms (iOS/Android app builds) never see the web
// implementation — dart:js_interop isn't available there, so the
// conditional export below swaps in a no-op stub.
export 'pwa_install_bridge_stub.dart'
    if (dart.library.js_interop) 'pwa_install_bridge_web.dart';
