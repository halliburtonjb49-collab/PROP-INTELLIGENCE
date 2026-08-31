(() => {
  if (!('PerformanceObserver' in window)) return;
  const release = '__PI_BUILD_VERSION__';
  const device = matchMedia('(max-width: 700px)').matches ? 'mobile' : 'desktop';
  const samples = new Map();
  let cls = 0;

  const token = () => {
    try {
      const raw = localStorage.getItem('sb-doncoxjilytojmnpukxi-auth-token');
      return raw ? JSON.parse(raw).access_token || '' : '';
    } catch (_) { return ''; }
  };
  const report = (metric, value) => {
    if (!Number.isFinite(value) || value < 0) return;
    samples.set(metric, value);
  };
  const flush = () => {
    const accessToken = token();
    if (!accessToken || samples.size === 0) return;
    const events = [...samples].map(([metric, value]) => ({
      prop_id: '__OBSERVABILITY__', action: 'WEB_VITAL',
      duration_ms: metric === 'CLS' ? Math.round(value * 1000) : Math.round(value),
      metadata: {metric, release, device, path: location.pathname},
    }));
    samples.clear();
    fetch('/api/intelligence/engagement', {
      method: 'POST', keepalive: true,
      headers: {'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}`},
      body: JSON.stringify({events}),
    }).catch(() => {});
  };

  try {
    new PerformanceObserver((list) => {
      const entries = list.getEntries();
      if (entries.length) report('LCP', entries[entries.length - 1].startTime);
    }).observe({type: 'largest-contentful-paint', buffered: true});
    new PerformanceObserver((list) => {
      list.getEntries().forEach((entry) => { if (!entry.hadRecentInput) cls += entry.value; });
      report('CLS', cls);
    }).observe({type: 'layout-shift', buffered: true});
    new PerformanceObserver((list) => {
      list.getEntries().forEach((entry) => report('INP', Math.max(samples.get('INP') || 0, entry.duration)));
    }).observe({type: 'event', buffered: true, durationThreshold: 40});
  } catch (_) {}
  addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') flush(); });
  addEventListener('pagehide', flush);
  setTimeout(flush, 15000);
})();
