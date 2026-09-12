{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  // PI's combined OneSignal/app-shell worker owns /workspace/. Registering
  // Flutter's generated worker at that same scope makes the two workers
  // replace each other and can strand customers on the update screen.
  config: {
    // Let Flutter select SkWasm only where WasmGC is genuinely supported and
    // fall back to the bundled dart2js/CanvasKit build on iOS WebKit. Forcing
    // SkWasm made both Safari and Chrome on iPhone reject every build candidate
    // and left the HTML launch screen visible forever.
    forceSingleThreadedSkwasm: true,
  },
}).catch((error) => {
  console.error('Flutter workspace failed to start:', error);
  const status = document.getElementById('pi-launch-status');
  if (status) status.textContent = 'Startup failed. Retrying automatically...';
});
