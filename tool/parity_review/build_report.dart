/// Builds a self-contained HTML parity report from the captured image corpus.
///
/// Run from the workspace root after parity_review_test.dart and the
/// Mermaid.js reference capture have completed:
///
///   fvm dart run tool/parity_review/build_report.dart
library;

import 'dart:convert';
import 'dart:io';

void main() {
  final root = _workspaceRoot();
  final reviewDir = Directory('${root.path}/build/parity_review');
  final manifestFile = File('${reviewDir.path}/manifest.json');
  if (!manifestFile.existsSync()) {
    stderr.writeln(
      'Missing ${manifestFile.path}. Run parity_review_test.dart first.',
    );
    exitCode = 1;
    return;
  }

  final manifest = (jsonDecode(manifestFile.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  final families = <String>{
    for (final entry in manifest) entry['family'] as String,
  }.toList()..sort();

  final cards = StringBuffer();
  final liveReferences = <String, String>{};
  for (var index = 0; index < manifest.length; index++) {
    final entry = manifest[index];
    final id = entry['id'] as String;
    final family = entry['family'] as String;
    final title = entry['title'] as String;
    final origin = entry['origin'] as String;
    final source = entry['source'] as String;
    liveReferences[id] = source;
    final search = '$id $family $title $origin'.toLowerCase();
    cards.write('''
<article class="case" id="case-${_attr(id)}" data-family="${_attr(family)}"
  data-search="${_attr(search)}" data-review-id="${_attr(id)}"
  data-lavish-question="Compare Mermaid.js and Flutter for ${_attr(id)}">
  <header class="case-head">
    <span class="case-number">${(index + 1).toString().padLeft(2, '0')}</span>
    <div class="case-title">
      <h2>${_text(title)}</h2>
      <p><code>${_text(id)}</code> <span aria-hidden="true">·</span> ${_text(origin)}</p>
    </div>
    <span class="family">${_text(family)}</span>
  </header>
  <div class="comparison">
    ${_panel('Mermaid.js', 'Reference', _mermaidReference(reviewDir, entry))}
    ${_panel('Flutter', 'Review target', _assetOrError(reviewDir, entry, 'flutterPath', 'flutterError', null), primary: true)}
    <div class="core-slot">
      ${_panel('mermaid_core SVG', 'Diagnostic', _assetOrError(reviewDir, entry, 'corePath', 'coreError', null))}
    </div>
  </div>
  <details class="source">
    <summary>Mermaid source <span>${source.split('\n').length} lines</span></summary>
    <pre><code>${_text(source)}</code></pre>
  </details>
  <form class="triage" data-case-id="${_attr(id)}" data-case-title="${_attr(title)}"
    data-origin="${_attr(origin)}" data-lavish-question="triage-${_attr(id)}">
    <fieldset>
      <legend>Mark a discrepancy</legend>
      <label><input type="checkbox" name="problem" value="layout"> Layout</label>
      <label><input type="checkbox" name="problem" value="text"> Text</label>
      <label><input type="checkbox" name="problem" value="edges"> Edges</label>
      <label><input type="checkbox" name="problem" value="shapes"> Shapes</label>
      <label><input type="checkbox" name="problem" value="missing content"> Missing</label>
      <label><input type="checkbox" name="problem" value="render failure"> Error</label>
    </fieldset>
    <label class="note">What differs?
      <textarea name="note" rows="2" placeholder="Point to the region and describe the expected Mermaid.js behavior"></textarea>
    </label>
    <button type="submit">Queue this finding</button>
    <output class="queue-state" aria-live="polite"></output>
  </form>
</article>''');
  }

  final familyOptions = StringBuffer('<option value="">All families</option>');
  for (final family in families) {
    familyOptions.write(
      '<option value="${_attr(family)}">${_text(family)}</option>',
    );
  }

  final output = File('${reviewDir.path}/index.html');
  final liveReferenceJson = jsonEncode(
    liveReferences,
  ).replaceAll('</script', r'<\/script');
  output.writeAsStringSync('''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mermaid parity review · first batch</title>
<style>
:root {
  color-scheme: light dark;
  --ground: #eef1f2;
  --surface: #ffffff;
  --surface-soft: #f5f7f8;
  --ink: #172229;
  --muted: #5b6971;
  --rule: #d5dde1;
  --accent: #4a3a8a;
  --target: #126b4b;
  --danger: #b23a2d;
  --shadow: 0 12px 32px rgba(28, 42, 50, 0.08);
}
@media (prefers-color-scheme: dark) {
  :root {
    --ground: #11181c;
    --surface: #1a2328;
    --surface-soft: #202b31;
    --ink: #edf3f5;
    --muted: #a9b7be;
    --rule: #34434b;
    --accent: #b8a9ff;
    --target: #67d5ab;
    --danger: #ff9a8b;
    --shadow: 0 16px 38px rgba(0, 0, 0, 0.25);
  }
}
:root[data-theme="light"] {
  --ground: #eef1f2; --surface: #ffffff; --surface-soft: #f5f7f8;
  --ink: #172229; --muted: #5b6971; --rule: #d5dde1;
  --accent: #4a3a8a; --target: #126b4b; --danger: #b23a2d;
  --shadow: 0 12px 32px rgba(28, 42, 50, 0.08);
}
:root[data-theme="dark"] {
  --ground: #11181c; --surface: #1a2328; --surface-soft: #202b31;
  --ink: #edf3f5; --muted: #a9b7be; --rule: #34434b;
  --accent: #b8a9ff; --target: #67d5ab; --danger: #ff9a8b;
  --shadow: 0 16px 38px rgba(0, 0, 0, 0.25);
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  background: var(--ground);
  color: var(--ink);
  font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
button, input, select { font: inherit; }
button, input, select, summary { outline-offset: 3px; }
:focus-visible { outline: 2px solid var(--accent); }
.masthead {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 24px;
  align-items: end;
  max-width: 1660px;
  margin: 0 auto;
  padding: 34px 28px 24px;
}
.eyebrow {
  margin: 0 0 8px;
  color: var(--accent);
  font: 700 12px/1 ui-monospace, SFMono-Regular, Menlo, monospace;
  letter-spacing: .11em;
  text-transform: uppercase;
}
h1 { margin: 0; max-width: 20ch; font-size: clamp(28px, 4vw, 52px); line-height: 1.02; letter-spacing: -.035em; }
.lede { max-width: 66ch; margin: 14px 0 0; color: var(--muted); font-size: 17px; }
.batch {
  min-width: 150px;
  padding: 14px 16px;
  border-left: 3px solid var(--accent);
  background: var(--surface);
  box-shadow: var(--shadow);
}
.batch strong { display: block; font: 700 30px/1 ui-monospace, SFMono-Regular, Menlo, monospace; }
.batch span { color: var(--muted); }
.toolbar-wrap {
  position: sticky;
  top: 0;
  z-index: 20;
  border-block: 1px solid var(--rule);
  background: color-mix(in srgb, var(--ground) 90%, transparent);
  backdrop-filter: blur(14px);
}
.toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  max-width: 1660px;
  margin: 0 auto;
  padding: 12px 28px;
}
.toolbar label { color: var(--muted); font-size: 13px; }
.toolbar input[type="search"], .toolbar select {
  min-height: 40px;
  border: 1px solid var(--rule);
  background: var(--surface);
  color: var(--ink);
  padding: 8px 11px;
}
.toolbar input[type="search"] { width: min(360px, 34vw); }
.toolbar .check { display: flex; align-items: center; gap: 7px; color: var(--ink); white-space: nowrap; }
.toolbar button {
  min-height: 40px;
  border: 1px solid var(--rule);
  background: var(--surface);
  color: var(--ink);
  padding: 7px 12px;
  cursor: pointer;
}
.count { margin-left: auto; color: var(--muted); font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; white-space: nowrap; }
main { max-width: 1660px; margin: 0 auto; padding: 24px 28px 72px; }
.case {
  margin: 0 0 24px;
  border: 1px solid var(--rule);
  background: var(--surface);
  box-shadow: var(--shadow);
}
.case[hidden] { display: none; }
.case-head {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 15px;
  padding: 13px 16px;
  border-bottom: 1px solid var(--rule);
}
.case-number { color: var(--muted); font: 700 13px ui-monospace, SFMono-Regular, Menlo, monospace; }
.case-title h2 { margin: 0; font-size: 18px; line-height: 1.2; }
.case-title p { margin: 4px 0 0; color: var(--muted); font-size: 12px; overflow-wrap: anywhere; }
code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
.family { padding: 4px 8px; border: 1px solid var(--rule); color: var(--muted); font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; }
.comparison { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); }
.panel { min-width: 0; border-right: 1px solid var(--rule); }
.panel:last-child { border-right: 0; }
.panel-head { display: flex; justify-content: space-between; gap: 12px; padding: 8px 12px; background: var(--surface-soft); border-bottom: 1px solid var(--rule); }
.panel-head strong { font-size: 13px; }
.panel-head span { color: var(--muted); font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; text-transform: uppercase; letter-spacing: .06em; }
.panel.primary .panel-head { box-shadow: inset 0 3px var(--target); }
.visual {
  display: grid;
  place-items: center;
  min-height: 360px;
  max-height: 680px;
  padding: 16px;
  overflow: auto;
  background: #fff;
}
.visual img, .mermaid-live svg { display: block; max-width: 100%; max-height: 640px; width: auto; height: auto; }
.mermaid-live { display: grid; place-items: center; width: 100%; min-height: 160px; color: #5b6971; }
.render-error { align-self: stretch; width: 100%; margin: 0; padding: 16px; overflow: auto; color: var(--danger); background: #fff5f3; white-space: pre-wrap; }
.core-slot { display: none; grid-column: 1 / -1; border-top: 1px solid var(--rule); }
body.show-core .core-slot { display: block; }
.core-slot .panel { border-right: 0; }
.source { border-top: 1px solid var(--rule); }
.source summary { cursor: pointer; padding: 11px 16px; color: var(--muted); }
.source summary span { margin-left: 8px; font: 11px ui-monospace, SFMono-Regular, Menlo, monospace; }
.source pre { margin: 0; padding: 16px; overflow: auto; border-top: 1px solid var(--rule); background: var(--surface-soft); color: var(--ink); font-size: 12px; line-height: 1.55; }
.triage {
  display: grid;
  grid-template-columns: auto minmax(240px, 1fr) auto;
  gap: 12px;
  align-items: end;
  padding: 14px 16px;
  border-top: 1px solid var(--rule);
  background: var(--surface-soft);
}
.triage fieldset { display: flex; flex-wrap: wrap; gap: 7px 12px; margin: 0; padding: 0; border: 0; }
.triage legend { margin-bottom: 6px; color: var(--muted); font-size: 12px; font-weight: 700; }
.triage fieldset label { white-space: nowrap; font-size: 13px; }
.triage .note { display: grid; gap: 5px; color: var(--muted); font-size: 12px; }
.triage textarea { width: 100%; resize: vertical; border: 1px solid var(--rule); background: var(--surface); color: var(--ink); padding: 8px 10px; }
.triage button { min-height: 39px; border: 0; background: var(--accent); color: #fff; padding: 8px 13px; cursor: pointer; font-weight: 700; }
.queue-state { grid-column: 1 / -1; min-height: 18px; color: var(--target); font-size: 12px; }
.queue-state.error { color: var(--danger); }
.empty { display: none; padding: 72px 20px; text-align: center; color: var(--muted); }
body.no-results .empty { display: block; }
@media (max-width: 860px) {
  .masthead { grid-template-columns: 1fr; }
  .batch { width: max-content; }
  .toolbar { flex-wrap: wrap; }
  .toolbar input[type="search"] { width: 100%; }
  .count { margin-left: 0; }
  .comparison { grid-template-columns: 1fr; }
  .panel { border-right: 0; border-bottom: 1px solid var(--rule); }
  .case-head { grid-template-columns: auto minmax(0, 1fr); }
  .family { grid-column: 2; width: max-content; }
  .visual { min-height: 280px; }
  .triage { grid-template-columns: 1fr; }
  .queue-state { grid-column: 1; }
}
@media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
</style>
</head>
<body>
<header class="masthead">
  <div>
    <p class="eyebrow">Mermaid parity lab / batch 01</p>
    <h1>Find the rendering disagreement.</h1>
    <p class="lede">Mermaid.js is the reference. Flutter is the review target. Annotate the exact mismatch in Lavish; open the source only when the picture needs explanation.</p>
  </div>
  <div class="batch"><strong>${manifest.length}</strong><span>complex cases</span></div>
</header>
<div class="toolbar-wrap">
  <div class="toolbar" role="search">
    <input id="search" type="search" placeholder="Search title, fixture, or family" aria-label="Search cases">
    <select id="family" aria-label="Filter by diagram family">$familyOptions</select>
    <label class="check"><input id="core" type="checkbox"> Show core SVG</label>
    <button id="theme" type="button">Switch theme</button>
    <output id="count" class="count">${manifest.length} / ${manifest.length} visible</output>
  </div>
</div>
<main>
  $cards
  <p class="empty">No cases match the current filters.</p>
</main>
<script>
const root = document.documentElement;
const search = document.querySelector('#search');
const family = document.querySelector('#family');
const core = document.querySelector('#core');
const count = document.querySelector('#count');
const cards = [...document.querySelectorAll('.case')];
function applyFilters() {
  const term = search.value.trim().toLowerCase();
  const selectedFamily = family.value;
  let visible = 0;
  for (const card of cards) {
    const show = (!term || card.dataset.search.includes(term)) &&
      (!selectedFamily || card.dataset.family === selectedFamily);
    card.hidden = !show;
    if (show) visible++;
  }
  count.value = `\${visible} / \${cards.length} visible`;
  document.body.classList.toggle('no-results', visible === 0);
}
search.addEventListener('input', applyFilters);
family.addEventListener('change', applyFilters);
core.addEventListener('change', () => document.body.classList.toggle('show-core', core.checked));
document.querySelector('#theme').addEventListener('click', () => {
  const dark = root.dataset.theme === 'dark' ||
    (!root.dataset.theme && matchMedia('(prefers-color-scheme: dark)').matches);
  root.dataset.theme = dark ? 'light' : 'dark';
});
for (const form of document.querySelectorAll('.triage')) {
  form.addEventListener('submit', (event) => {
    event.preventDefault();
    const data = new FormData(form);
    const problems = data.getAll('problem');
    const note = String(data.get('note') || '').trim();
    const output = form.querySelector('.queue-state');
    output.classList.remove('error');
    if (!problems.length && !note) {
      output.textContent = 'Choose a discrepancy or add a note first.';
      output.classList.add('error');
      return;
    }
    const id = form.dataset.caseId;
    const title = form.dataset.caseTitle;
    const origin = form.dataset.origin;
    const categories = problems.length ? problems.join(', ') : 'other';
    const prompt = `Parity issue in \${id} (\${origin}). Categories: \${categories}.\${note ? ` Note: \${note}` : ''}`;
    if (!window.lavish?.queuePrompt) {
      output.textContent = 'Open this report in Lavish to queue the finding.';
      output.classList.add('error');
      return;
    }
    window.lavish.queuePrompt(prompt, {
      tag: 'parity',
      text: `\${title}: \${categories}`,
      element: form,
      queueKey: `parity-\${id}`,
      data: { caseId: id, origin, categories: problems, note },
    });
    output.textContent = 'Queued. Send your collected findings to the agent when ready.';
  });
}
</script>
<script type="module">
const liveReferences = $liveReferenceJson;
const targets = [...document.querySelectorAll('.mermaid-live')];
if (targets.length) {
  try {
    const module = await import('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs');
    const mermaid = module.default;
    mermaid.initialize({ startOnLoad: false, theme: 'default' });
    for (let index = 0; index < targets.length; index++) {
      const target = targets[index];
      const id = target.dataset.caseId;
      try {
        const rendered = await mermaid.render(`review-reference-\${index}`, liveReferences[id]);
        target.innerHTML = rendered.svg;
      } catch (error) {
        target.innerHTML = `<pre class="render-error">\${String(error)}</pre>`;
        document.getElementById(`dreview-reference-\${index}`)?.remove();
      }
    }
  } catch (error) {
    for (const target of targets) {
      target.innerHTML = `<pre class="render-error">Could not load Mermaid.js reference renderer.\n\${String(error)}</pre>`;
    }
  }
}
</script>
</body>
</html>''');
  stdout.writeln(output.path);
}

String _panel(
  String title,
  String role,
  String content, {
  bool primary = false,
}) =>
    '''<section class="panel${primary ? ' primary' : ''}">
  <header class="panel-head"><strong>${_text(title)}</strong><span>${_text(role)}</span></header>
  <div class="visual">$content</div>
</section>''';

String _mermaidReference(Directory reviewDir, Map<String, dynamic> entry) {
  final id = entry['id'] as String;
  final captured = File('${reviewDir.path}/assets/$id.mermaid.svg');
  if (captured.existsSync()) {
    final data = base64Encode(captured.readAsBytesSync());
    return '<img src="data:image/svg+xml;base64,$data" alt="${_attr(entry['title'] as String)} rendered by Mermaid.js">';
  }
  return '<div class="mermaid-live" data-case-id="${_attr(id)}"><span>Rendering Mermaid.js…</span></div>';
}

String _assetOrError(
  Directory reviewDir,
  Map<String, dynamic> entry,
  String pathKey,
  String errorKey,
  String? fallbackName,
) {
  final relative =
      (entry[pathKey] as String?) ??
      (fallbackName == null ? null : 'assets/$fallbackName');
  if (relative != null) {
    final file = File('${reviewDir.path}/$relative');
    if (file.existsSync()) {
      final mime = relative.endsWith('.png') ? 'image/png' : 'image/svg+xml';
      final data = base64Encode(file.readAsBytesSync());
      return '<img src="data:$mime;base64,$data" alt="${_attr(entry['title'] as String)} rendered by ${_attr(pathKey.replaceFirst('Path', ''))}">';
    }
  }
  final error = entry[errorKey]?.toString() ?? 'Reference output is missing.';
  return '<pre class="render-error">${_text(error)}</pre>';
}

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (Directory('${current.path}/packages/mermaid_core').existsSync() &&
        Directory('${current.path}/apps/demo').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('Could not locate the Mermaid workspace root.');
    }
    current = parent;
  }
}

const _html = HtmlEscape(HtmlEscapeMode.element);
const _attribute = HtmlEscape(HtmlEscapeMode.attribute);
String _text(String value) => _html.convert(value);
String _attr(String value) => _attribute.convert(value);
