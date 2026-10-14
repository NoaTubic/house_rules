import 'dart:convert';

import 'package:house_rules/src/finding.dart';

/// Renders a self-contained HTML report.
///
/// The file is written to disk and opened from the filesystem, often with no
/// network, so everything ships inline: no web fonts, no CDN, no external
/// icons. Type falls back through the stack a Flutter developer's machine
/// already has.
String renderHtml(
  List<Finding> fresh,
  List<Finding> known, {
  required int filesScanned,
  required int suppressed,
  required Duration elapsed,
  required String projectName,
}) {
  final payload = jsonEncode({
    'project': projectName,
    'generated': DateTime.now().toIso8601String(),
    'filesScanned': filesScanned,
    'suppressed': suppressed,
    'elapsedMs': elapsed.inMilliseconds,
    'findings': [
      for (final f in fresh) _encode(f, isNew: true),
      for (final f in known) _encode(f, isNew: false),
    ],
  });

  return '$_docOpen$_head'
      '<script id="data" type="application/json">$payload</script>'
      '$_body</body></html>\n';
}

Map<String, Object?> _encode(Finding f, {required bool isNew}) => {
  'file': f.file,
  'line': f.line,
  'column': f.column,
  'rule': f.rule,
  'severity': f.severity.name,
  'message': f.message,
  'found': f.found,
  'why': f.why,
  'candidates': f.candidates,
  'isNew': isNew,
};

/// A complete document, not a fragment: this file is opened straight from
/// the filesystem, so it carries its own doctype, charset and viewport.
/// Without the charset the browser guesses, and non-ASCII punctuation in the
/// report renders as mojibake.
const _docOpen =
    '<!doctype html>\n<html lang="en">\n<head>\n'
    '<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n';

const _head = r'''<title>house_rules Report</title>
<style>
  :root {
    --brand: #0175C2;
    --brand-dark: #02569B;
    --brand-light: #13B9FD;
    --ink: #202124;
    --muted: #5F6368;
    --faint: #80868B;
    --line: #DADCE0;
    --line-soft: #E8EAED;
    --surface: #FFFFFF;
    --ground: #F8F9FA;
    --raised: #FFFFFF;
    --error: #C5221F;
    --error-bg: #FCE8E6;
    --warn: #B06000;
    --warn-bg: #FEF7E0;
    --info: #1967D2;
    --info-bg: #E8F0FE;
    --ok: #137333;
    --code-bg: #F1F3F4;
    --shadow: 0 1px 2px rgba(60,64,67,.3), 0 1px 3px 1px rgba(60,64,67,.15);
    --sans: "Google Sans", "Product Sans", Roboto, -apple-system,
      BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    --mono: "Roboto Mono", ui-monospace, SFMono-Regular, "SF Mono", Menlo,
      Consolas, monospace;
  }

  :root:not([data-theme="light"]) {
    color-scheme: light;
  }

  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      color-scheme: dark;
      --brand: #6BB9F0;
      --brand-dark: #8AC9F5;
      --brand-light: #13B9FD;
      --ink: #E8EAED;
      --muted: #9AA0A6;
      --faint: #80868B;
      --line: #313A43;
      --line-soft: #28313A;
      --surface: #1B2027;
      --ground: #12161B;
      --raised: #222930;
      --error: #F28B82;
      --error-bg: #3B2321;
      --warn: #FDD663;
      --warn-bg: #3A2F14;
      --info: #8AB4F8;
      --info-bg: #1E2A3D;
      --ok: #81C995;
      --code-bg: #171C22;
      --shadow: 0 1px 2px rgba(0,0,0,.5), 0 1px 3px 1px rgba(0,0,0,.3);
    }
  }

  :root[data-theme="dark"] {
    color-scheme: dark;
    --brand: #6BB9F0;
    --brand-dark: #8AC9F5;
    --brand-light: #13B9FD;
    --ink: #E8EAED;
    --muted: #9AA0A6;
    --faint: #80868B;
    --line: #313A43;
    --line-soft: #28313A;
    --surface: #1B2027;
    --ground: #12161B;
    --raised: #222930;
    --error: #F28B82;
    --error-bg: #3B2321;
    --warn: #FDD663;
    --warn-bg: #3A2F14;
    --info: #8AB4F8;
    --info-bg: #1E2A3D;
    --ok: #81C995;
    --code-bg: #171C22;
    --shadow: 0 1px 2px rgba(0,0,0,.5), 0 1px 3px 1px rgba(0,0,0,.3);
  }

  * { box-sizing: border-box; }

  body {
    margin: 0;
    background: var(--ground);
    color: var(--ink);
    font-family: var(--sans);
    font-size: 14px;
    line-height: 1.5;
    -webkit-font-smoothing: antialiased;
  }

  svg.icon {
    width: 18px;
    height: 18px;
    fill: currentColor;
    flex: none;
    vertical-align: -4px;
  }

  /* ---------- app bar ---------- */
  .appbar {
    position: sticky;
    top: env(safe-area-inset-top, 0px);
    z-index: 20;
    display: flex;
    align-items: center;
    gap: 16px;
    flex-wrap: wrap;
    padding: 12px 24px;
    background: var(--surface);
    border-bottom: 1px solid var(--line);
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
    font-weight: 500;
    font-size: 16px;
    letter-spacing: -0.1px;
  }

  .mark { width: 26px; height: 26px; flex: none; }

  .brand small {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--faint);
    font-weight: 400;
    padding-left: 2px;
  }

  .appbar-meta {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: 18px;
    font-size: 12px;
    color: var(--muted);
    font-family: var(--mono);
  }

  .verdict {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    border-radius: 999px;
    font-family: var(--sans);
    font-weight: 500;
    font-size: 12px;
    letter-spacing: .2px;
  }
  .iconbtn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    border: 1px solid var(--line);
    background: var(--surface);
    color: var(--muted);
    cursor: pointer;
    padding: 0;
  }
  .iconbtn:hover { background: var(--line-soft); color: var(--ink); }
  .iconbtn:focus-visible { outline: 2px solid var(--brand); }

  .verdict.fail { background: var(--error-bg); color: var(--error); }
  .verdict.pass { background: var(--info-bg); color: var(--ok); }

  /* ---------- shell ---------- */
  .shell {
    display: grid;
    grid-template-columns: 268px minmax(0, 1fr);
    gap: 32px;
    max-width: 1320px;
    margin: 0 auto;
    padding: 28px 24px 72px;
  }

  /* ---------- rail ---------- */
  .rail { position: sticky; top: 96px; align-self: start; }

  .rail h2 {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: .9px;
    color: var(--faint);
    font-weight: 500;
    margin: 0 0 10px 12px;
  }

  .rail + .rail { margin-top: 28px; }

  .tiles { display: grid; gap: 10px; margin-bottom: 28px; }

  .tile {
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 12px;
    padding: 14px 16px;
  }
  .tile .n {
    font-size: 26px;
    font-weight: 500;
    line-height: 1.1;
    font-variant-numeric: tabular-nums;
    letter-spacing: -.5px;
  }
  .tile .k {
    font-size: 11px;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: .7px;
    margin-top: 2px;
  }
  .tile.blocking { border-color: var(--error); }
  .tile.blocking .n { color: var(--error); }

  .rules { list-style: none; margin: 0; padding: 0; }

  .rules button {
    display: flex;
    align-items: center;
    gap: 9px;
    width: 100%;
    text-align: left;
    background: none;
    border: 0;
    border-left: 3px solid transparent;
    border-radius: 0 999px 999px 0;
    padding: 7px 14px 7px 11px;
    font: inherit;
    font-size: 13px;
    color: var(--muted);
    cursor: pointer;
  }
  .rules button:hover { background: var(--line-soft); color: var(--ink); }
  .rules button[aria-pressed="true"] {
    background: var(--info-bg);
    border-left-color: var(--brand);
    color: var(--brand-dark);
    font-weight: 500;
  }
  .rules .nm {
    font-family: var(--mono);
    font-size: 11.5px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .rules .ct {
    margin-left: auto;
    font-variant-numeric: tabular-nums;
    font-size: 11px;
    color: var(--faint);
  }
  .rules button[aria-pressed="true"] .ct { color: var(--brand-dark); }

  /* ---------- controls ---------- */
  .controls {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
    align-items: center;
    margin-bottom: 22px;
  }

  .search {
    flex: 1 1 260px;
    display: flex;
    align-items: center;
    gap: 9px;
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 999px;
    padding: 0 16px;
    height: 42px;
    color: var(--muted);
  }
  .search:focus-within {
    border-color: var(--brand);
    box-shadow: 0 0 0 1px var(--brand);
  }
  .search input {
    flex: 1;
    border: 0;
    background: none;
    font: inherit;
    color: var(--ink);
    outline: none;
    min-width: 0;
  }

  .seg {
    display: flex;
    border: 1px solid var(--line);
    border-radius: 999px;
    overflow: hidden;
    background: var(--surface);
    height: 42px;
  }
  .seg button {
    border: 0;
    background: none;
    font: inherit;
    font-size: 13px;
    padding: 0 18px;
    color: var(--muted);
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 7px;
  }
  .seg button + button { border-left: 1px solid var(--line); }
  .seg button[aria-pressed="true"] {
    background: var(--info-bg);
    color: var(--brand-dark);
    font-weight: 500;
  }

  /* ---------- findings ---------- */
  .filegroup {
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: 12px;
    margin-bottom: 14px;
    overflow: hidden;
  }

  .filehead {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 13px 18px;
    border-bottom: 1px solid var(--line-soft);
    color: var(--muted);
    background: var(--ground);
  }
  .filehead .path {
    font-family: var(--mono);
    font-size: 12.5px;
    color: var(--ink);
    overflow-wrap: anywhere;
  }
  .filehead .path b { font-weight: 500; color: var(--brand-dark); }
  .filehead .n {
    margin-left: auto;
    font-size: 11px;
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }

  .finding {
    display: grid;
    grid-template-columns: 4px 1fr;
    border-top: 1px solid var(--line-soft);
  }
  .filegroup .finding:first-of-type { border-top: 0; }
  .stripe { background: var(--line); }
  .finding.error .stripe { background: var(--error); }
  .finding.warning .stripe { background: var(--warn); }
  .finding.info .stripe { background: var(--info); }

  .fbody { padding: 14px 18px; min-width: 0; }

  .frow {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
    margin-bottom: 7px;
  }

  .loc {
    font-family: var(--mono);
    font-size: 12px;
    color: var(--faint);
    font-variant-numeric: tabular-nums;
  }

  .chip {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    border-radius: 6px;
    padding: 2px 8px;
    font-size: 11px;
    font-weight: 500;
    letter-spacing: .3px;
    text-transform: uppercase;
  }
  .chip.error { background: var(--error-bg); color: var(--error); }
  .chip.warning { background: var(--warn-bg); color: var(--warn); }
  .chip.info { background: var(--info-bg); color: var(--info); }

  .rulename {
    font-family: var(--mono);
    font-size: 11.5px;
    color: var(--muted);
  }

  .tag {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: .6px;
    padding: 2px 7px;
    border-radius: 999px;
    border: 1px solid var(--line);
    color: var(--faint);
  }
  .tag.fresh { border-color: var(--error); color: var(--error); }

  .msg { font-size: 14px; margin-bottom: 6px; overflow-wrap: anywhere; }
  .msg code {
    font-family: var(--mono);
    font-size: 12.5px;
    background: var(--code-bg);
    padding: 1px 5px;
    border-radius: 4px;
  }

  .why {
    font-size: 12.5px;
    color: var(--muted);
    max-width: 68ch;
    margin-bottom: 8px;
  }

  .cands {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    align-items: center;
    font-size: 12px;
    color: var(--muted);
  }
  .cands .lbl {
    text-transform: uppercase;
    font-size: 10px;
    letter-spacing: .6px;
    color: var(--faint);
  }
  .cands code {
    font-family: var(--mono);
    font-size: 12px;
    background: var(--code-bg);
    border: 1px solid var(--line-soft);
    padding: 2px 8px;
    border-radius: 6px;
    color: var(--brand-dark);
  }

  .empty {
    text-align: center;
    padding: 72px 24px;
    color: var(--muted);
  }
  .empty svg { width: 40px; height: 40px; color: var(--ok); }

  .more {
    display: block;
    width: 100%;
    margin-top: 10px;
    padding: 13px;
    border: 1px dashed var(--line);
    border-radius: 12px;
    background: none;
    font: inherit;
    font-size: 13px;
    color: var(--brand);
    cursor: pointer;
  }
  .more:hover { background: var(--surface); }

  footer {
    max-width: 1320px;
    margin: 0 auto;
    padding: 0 24px 40px;
    color: var(--faint);
    font-size: 12px;
  }
  footer code {
    font-family: var(--mono);
    background: var(--code-bg);
    padding: 1px 5px;
    border-radius: 4px;
  }

  @media (max-width: 900px) {
    .shell { grid-template-columns: 1fr; gap: 20px; padding: 20px 16px 56px; }
    .rail { position: static; }
    .tiles { grid-template-columns: repeat(2, 1fr); }
    .appbar { padding: 12px 16px; }
    footer { padding: 0 16px 32px; }
  }
</style>
</head>
<body>
''';

const _body = r'''
<header class="appbar">
  <div class="brand">
    <svg class="mark" viewBox="0 0 48 48" aria-hidden="true">
      <path d="M26 4 6 24l6 6L38 4z" fill="#42A5F5"/>
      <path d="M26 26 14 38l6 6 6-6 12-12z" fill="#42A5F5"/>
      <path d="m20 44 6-6h12l-6 6z" fill="#0D47A1"/>
      <path d="m14 38 12-12 6 6-6 6z" fill="#02569B"/>
    </svg>
    <span>house_rules <small id="proj"></small></span>
  </div>
  <div class="appbar-meta">
    <span id="scanmeta"></span>
    <button class="iconbtn" id="theme" type="button"
      title="Switch theme" aria-label="Switch theme"></button>
    <span class="verdict" id="verdict"></span>
  </div>
</header>

<div class="shell">
  <div>
    <div class="tiles" id="tiles"></div>
    <nav class="rail">
      <h2>Rules</h2>
      <ul class="rules" id="rules"></ul>
    </nav>
  </div>

  <main>
    <div class="controls">
      <label class="search">
        <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/></svg>
        <input id="q" type="search" placeholder="Filter by file, token or message" autocomplete="off">
      </label>
      <div class="seg" role="group" aria-label="Baseline filter">
        <button type="button" id="f-new" aria-pressed="true">
          <svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 21h-1l1-7H7.5c-.58 0-.57-.32-.38-.66.19-.34.05-.08.07-.12C8.48 10.94 10.42 7.54 13 3h1l-1 7h3.5c.49 0 .56.33.47.51l-.07.15C12.96 17.55 11 21 11 21z"/></svg>
          Blocking
        </button>
        <button type="button" id="f-all" aria-pressed="false">All findings</button>
      </div>
    </div>
    <div id="out"></div>
  </main>
</div>

<footer>
  Generated by <code>house_rules --format html</code>. Rules are configured in
  <code>house_rules.yaml</code>; findings already recorded in
  <code>house_rules_baseline.json</code> are marked <em>baselined</em> and do
  not fail a build.
</footer>

<script>
(function () {
  var DATA = JSON.parse(document.getElementById('data').textContent);
  var ICONS = {
    error: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z',
    warning: 'M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z',
    info: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z',
    file: 'M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z',
    ok: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z',
    light: 'M12 7c-2.76 0-5 2.24-5 5s2.24 5 5 5 5-2.24 5-5-2.24-5-5-5zM2 13h2c.55 0 1-.45 1-1s-.45-1-1-1H2c-.55 0-1 .45-1 1s.45 1 1 1zm18 0h2c.55 0 1-.45 1-1s-.45-1-1-1h-2c-.55 0-1 .45-1 1s.45 1 1 1zM11 2v2c0 .55.45 1 1 1s1-.45 1-1V2c0-.55-.45-1-1-1s-1 .45-1 1zm0 18v2c0 .55.45 1 1 1s1-.45 1-1v-2c0-.55-.45-1-1-1s-1 .45-1 1zM5.99 4.58a.996.996 0 0 0-1.41 0 .996.996 0 0 0 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0s.39-1.03 0-1.41L5.99 4.58zm12.37 12.37a.996.996 0 0 0-1.41 0 .996.996 0 0 0 0 1.41l1.06 1.06c.39.39 1.03.39 1.41 0a.996.996 0 0 0 0-1.41l-1.06-1.06zm1.06-10.96a.996.996 0 0 0 0-1.41.996.996 0 0 0-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06zM7.05 18.36a.996.996 0 0 0 0-1.41.996.996 0 0 0-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06z',
    dark: 'M12 3a9 9 0 1 0 9 9c0-.46-.04-.92-.1-1.36a5.389 5.389 0 0 1-4.4 2.26 5.403 5.403 0 0 1-3.14-9.8c-.44-.06-.9-.1-1.36-.1z',
    auto: 'M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18V4a8 8 0 0 1 0 16z'
  };
  var PAGE = 40;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }
  function icon(name, cls) {
    return '<svg class="icon ' + (cls || '') + '" viewBox="0 0 24 24" ' +
      'aria-hidden="true"><path d="' + ICONS[name] + '"/></svg>';
  }
  // Renders `backticked` spans as inline code.
  function mark(s) {
    return esc(s).replace(/`([^`]+)`/g, '<code>$1</code>');
  }

  var state = { rule: null, query: '', onlyNew: true, shown: PAGE };

  // Three states, matching the docs sites a Flutter developer already uses:
  // follow the OS, or pin light or dark. The choice is a per-viewer
  // convenience, so a storage failure must not break the page.
  var MODES = ['auto', 'light', 'dark'];
  var mode = 'auto';
  try {
    var saved = localStorage.getItem('house_rules.theme');
    if (MODES.indexOf(saved) !== -1) mode = saved;
  } catch (e) { /* private window or blocked storage */ }

  var themeBtn = document.getElementById('theme');
  function applyTheme() {
    if (mode === 'auto') {
      document.documentElement.removeAttribute('data-theme');
    } else {
      document.documentElement.setAttribute('data-theme', mode);
    }
    themeBtn.innerHTML = icon(mode);
    themeBtn.title = 'Theme: ' + mode;
  }
  themeBtn.onclick = function () {
    mode = MODES[(MODES.indexOf(mode) + 1) % MODES.length];
    try {
      localStorage.setItem('house_rules.theme', mode);
    } catch (e) { /* ignore */ }
    applyTheme();
  };
  applyTheme();

  document.getElementById('proj').textContent = DATA.project;
  document.getElementById('scanmeta').textContent =
    DATA.filesScanned.toLocaleString() + ' files · ' +
    DATA.elapsedMs + 'ms' +
    (DATA.suppressed ? ' · ' + DATA.suppressed + ' suppressed' : '');

  var all = DATA.findings;
  var blocking = all.filter(function (f) {
    return f.isNew && f.severity !== 'info';
  });

  var v = document.getElementById('verdict');
  if (blocking.length) {
    v.className = 'verdict fail';
    v.innerHTML = icon('error') + blocking.length + ' blocking';
  } else {
    v.className = 'verdict pass';
    v.innerHTML = icon('ok') + 'Clean';
  }

  var baselined = all.filter(function (f) { return !f.isNew; }).length;
  var tiles = [
    { n: blocking.length, k: 'Blocking', cls: 'blocking' },
    { n: baselined, k: 'Baselined', cls: '' },
    { n: all.filter(function (f) { return f.severity === 'info'; }).length,
      k: 'Informational', cls: '' },
    { n: new Set(all.map(function (f) { return f.file; })).size,
      k: 'Files affected', cls: '' }
  ];
  document.getElementById('tiles').innerHTML = tiles.map(function (t) {
    return '<div class="tile ' + t.cls + '"><div class="n">' +
      t.n.toLocaleString() + '</div><div class="k">' + t.k + '</div></div>';
  }).join('');

  function pool() {
    return state.onlyNew
      ? all.filter(function (f) { return f.isNew; })
      : all;
  }

  function buildRules() {
    var counts = {};
    pool().forEach(function (f) {
      counts[f.rule] = (counts[f.rule] || 0) + 1;
    });
    var names = Object.keys(counts).sort(function (a, b) {
      return counts[b] - counts[a];
    });
    var total = pool().length;
    var html = '<li><button type="button" data-rule="" aria-pressed="' +
      (state.rule === null) + '"><span class="nm">all rules</span>' +
      '<span class="ct">' + total.toLocaleString() + '</span></button></li>';
    html += names.map(function (n) {
      return '<li><button type="button" data-rule="' + esc(n) +
        '" aria-pressed="' + (state.rule === n) + '">' +
        '<span class="nm">' + esc(n) + '</span><span class="ct">' +
        counts[n] + '</span></button></li>';
    }).join('');
    document.getElementById('rules').innerHTML = html;
  }

  function matches(f) {
    if (state.rule && f.rule !== state.rule) return false;
    if (!state.query) return true;
    var q = state.query.toLowerCase();
    return (f.file + ' ' + f.message + ' ' + (f.found || ''))
      .toLowerCase().indexOf(q) !== -1;
  }

  function render() {
    var rows = pool().filter(matches);
    var out = document.getElementById('out');

    if (!rows.length) {
      out.innerHTML = '<div class="empty">' + icon('ok') +
        '<p>No findings match this filter.</p></div>';
      return;
    }

    var groups = [];
    var index = {};
    rows.slice(0, state.shown).forEach(function (f) {
      if (!(f.file in index)) {
        index[f.file] = groups.length;
        groups.push({ file: f.file, items: [] });
      }
      groups[index[f.file]].items.push(f);
    });

    out.innerHTML = groups.map(function (g) {
      var cut = g.file.lastIndexOf('/');
      var dir = cut < 0 ? '' : g.file.slice(0, cut + 1);
      var base = cut < 0 ? g.file : g.file.slice(cut + 1);
      return '<section class="filegroup"><div class="filehead">' +
        icon('file') + '<span class="path">' + esc(dir) + '<b>' +
        esc(base) + '</b></span><span class="n">' + g.items.length +
        '</span></div>' + g.items.map(function (f) {
          var cands = (f.candidates || []).length
            ? '<div class="cands"><span class="lbl">did you mean</span>' +
              f.candidates.map(function (c) {
                return '<code>' + esc(c) + '</code>';
              }).join('') + '</div>'
            : '';
          return '<article class="finding ' + f.severity + '">' +
            '<div class="stripe"></div><div class="fbody"><div class="frow">' +
            '<span class="loc">' + f.line + ':' + f.column + '</span>' +
            '<span class="chip ' + f.severity + '">' + icon(f.severity) +
            f.severity + '</span>' +
            '<span class="rulename">' + esc(f.rule) + '</span>' +
            (f.isNew
              ? '<span class="tag fresh">new</span>'
              : '<span class="tag">baselined</span>') +
            '</div><div class="msg">' + mark(f.message) + '</div>' +
            (f.why ? '<div class="why">' + esc(f.why) + '</div>' : '') +
            cands + '</div></article>';
        }).join('') + '</section>';
    }).join('');

    if (rows.length > state.shown) {
      var b = document.createElement('button');
      b.className = 'more';
      b.type = 'button';
      b.textContent = 'Show ' +
        Math.min(PAGE, rows.length - state.shown) + ' more of ' +
        rows.length.toLocaleString();
      b.onclick = function () { state.shown += PAGE; render(); };
      out.appendChild(b);
    }
  }

  document.getElementById('rules').addEventListener('click', function (e) {
    var btn = e.target.closest('button[data-rule]');
    if (!btn) return;
    state.rule = btn.dataset.rule || null;
    state.shown = PAGE;
    buildRules();
    render();
  });

  document.getElementById('q').addEventListener('input', function (e) {
    state.query = e.target.value;
    state.shown = PAGE;
    render();
  });

  function setScope(onlyNew) {
    state.onlyNew = onlyNew;
    state.rule = null;
    state.shown = PAGE;
    document.getElementById('f-new').setAttribute('aria-pressed', onlyNew);
    document.getElementById('f-all').setAttribute('aria-pressed', !onlyNew);
    buildRules();
    render();
  }
  document.getElementById('f-new').onclick = function () { setScope(true); };
  document.getElementById('f-all').onclick = function () { setScope(false); };

  buildRules();
  render();
})();
</script>
''';
