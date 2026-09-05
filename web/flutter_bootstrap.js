{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  // PI's combined OneSignal/app-shell worker owns /workspace/. Registering
  // Flutter's generated worker at that same scope makes the two workers
  // replace each other and can strand customers on the update screen.
  // CanvasKit keeps PI's compact typography, thin borders, and sports imagery
  // consistently sharp across browser zoom levels and high-DPI displays.
  config: {
    renderer: 'canvaskit',
  },
});
