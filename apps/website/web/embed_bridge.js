// Bridges between the Jaspr page, mermaid.js (CDN) and the embedded
// Flutter build of mermaid dart.
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

mermaid.initialize({ startOnLoad: false, theme: 'default' });

// Register the ELK layout loader so mermaid.js honours `layout: elk` (it ships
// dagre only by default). Best-effort: a failed import must not break the page.
try {
  const elk = await import(
    'https://cdn.jsdelivr.net/npm/@mermaid-js/layout-elk@0/dist/mermaid-layout-elk.esm.min.mjs'
  );
  mermaid.registerLayoutLoaders(elk.default ?? elk);
} catch (e) {
  console.warn('mermaid.js ELK layout loader unavailable:', e);
}

let seq = 0;

window.renderMermaidJs = async (el, source) => {
  try {
    const { svg } = await mermaid.render(`mmdjs${++seq}`, source);
    el.innerHTML = svg;
  } catch (e) {
    el.innerHTML = `<pre style="color:#b00020;white-space:pre-wrap">${String(e)}</pre>`;
    // mermaid.render leaves a dangling error element behind on failure.
    document.getElementById(`dmmdjs${seq}`)?.remove();
  }
};

// Latest requested source; the Flutter app reads it at startup and the
// page falls back to it while the engine is still booting.
window.__mermaidDartInitialSource = '';

window.updateMermaidDart = (source) => {
  window.__mermaidDartInitialSource = source;
  window.mermaidDartEmbed?.render(source);
};

window.loadMermaidDart = (host, initialSource) => {
  window.__mermaidDartInitialSource = initialSource;
  host.replaceChildren();
  // flutter_bootstrap.js is generated from our custom template; it defines
  // window.loadMermaidDartApp (it must carry the build config, plain
  // flutter.js no longer works on its own since Flutter 3.22).
  const script = document.createElement('script');
  script.src = 'flutter_embed/flutter_bootstrap.js';
  script.onload = () => window.loadMermaidDartApp(host);
  document.body.append(script);
};
