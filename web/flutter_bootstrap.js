{{flutter_js}}
{{flutter_build_config}}

// Keep Flutter's versioned app-shell cache enabled. It makes repeat launches
// immediate while the generated worker safely replaces stale release assets.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  // CanvasKit keeps PI's compact typography, thin borders, and sports imagery
  // consistently sharp across browser zoom levels and high-DPI displays.
  config: {
    renderer: 'canvaskit',
  },
});
