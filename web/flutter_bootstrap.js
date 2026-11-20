{{flutter_js}}
{{flutter_build_config}}

(function () {
  var ua = navigator.userAgent || '';
  var isIOS = /iPad|iPhone|iPod/.test(ua) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

  var config = {};

  if (window._flutter && _flutter.buildConfig && _flutter.buildConfig.useLocalCanvasKit) {
    config.canvasKitBaseUrl = 'canvaskit/';
  }

  // iOS WebKit (Safari / WKWebView / iOS Chrome) suffers from WebGL multi-surface
  // GPU context loss and ANGLE Metal black/blank canvas issues; force reliable 2D software CanvasKit.
  if (isIOS) {
    config.canvasKitForceCpuOnly = true;
    config.canvasKitVariant = 'full';
  }

  function reportBootError(err) {
    console.error('RemedyTrack boot error:', err);
    if (typeof window.__rtShowBootError === 'function') {
      var msg = (err && err.message) ? err.message : String(err || 'Unable to start application.');
      window.__rtShowBootError(msg);
    }
  }

  try {
    var loadPromise = _flutter.loader.load({
      config: config,
      onEntrypointLoaded: function (engineInitializer) {
        if (typeof window.__rtSetBootStatus === 'function') {
          window.__rtSetBootStatus('Starting RemedyTrack...');
        }
        engineInitializer.initializeEngine(config).then(function (appRunner) {
          return appRunner.runApp();
        }).catch(reportBootError);
      }
    });
    if (loadPromise && typeof loadPromise.catch === 'function') {
      loadPromise.catch(reportBootError);
    }
  } catch (err) {
    reportBootError(err);
  }
})();
