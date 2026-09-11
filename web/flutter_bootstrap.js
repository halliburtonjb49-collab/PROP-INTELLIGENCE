{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  // PI's combined OneSignal/app-shell worker owns /workspace/. Registering
  // Flutter's generated worker at that same scope makes the two workers
  // replace each other and can strand customers on the update screen.
  // CanvasKit keeps PI's compact typography, thin borders, and sports imagery
  // consistently sharp across browser zoom levels and high-DPI displays.
  config: {
    // CanvasKit keeps a large WASM heap and duplicate raster surfaces alive.
    // On iOS Safari that pushed long, image-heavy boards into the browser's
    // "A problem repeatedly occurred" reload. SkWasm is Flutter's current
    // web renderer and is materially lighter for this scrolling application.
    renderer: 'skwasm',
    forceSingleThreadedSkwasm: true,
  },
});
