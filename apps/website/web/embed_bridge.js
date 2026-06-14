// Bridges between the Jaspr page, mermaid.js (CDN) and the embedded
// Flutter build of mermaid dart.
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

// Network-first service worker so a returning visitor never runs a stale
// cached build (the bundles have stable filenames). Registered relative to
// this module, so it scopes correctly under a project-pages subpath too.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register(new URL('sw.js', import.meta.url))
    .catch((e) => console.warn('service worker registration failed:', e));
}

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

// The Flutter view itself is mounted by jaspr_flutter_embed (FlutterEmbedView).
// We only feed it source: __mermaidDartInitialSource is read by the embed at
// boot, and render() (published by the embed once booted) pushes live edits.
window.__mermaidDartInitialSource = '';

window.updateMermaidDart = (source) => {
  window.__mermaidDartInitialSource = source;
  window.mermaidDartEmbed?.render(source);
};
