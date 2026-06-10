{{flutter_js}}
{{flutter_build_config}}

// Custom bootstrap: instead of auto-running into <body>, expose a loader the
// host page calls with the element the Flutter view should live in.
window.loadMermaidDartApp = (host) => {
  _flutter.loader.load({
    config: {
      assetBase: 'flutter_embed/',
      entrypointBaseUrl: 'flutter_embed/',
    },
    onEntrypointLoaded: async (engineInitializer) => {
      const appRunner = await engineInitializer.initializeEngine({
        hostElement: host,
        assetBase: 'flutter_embed/',
      });
      await appRunner.runApp();
    },
  });
};
