#!/usr/bin/env bash
#
# woz_review.sh — build a human-review HTML for WOZ boot test results
#
# Reads:
#   woz_report/results.csv     (owned by test_woz_batch.sh — never modified here)
#   woz_report/triage.csv      (human-owned; optional; used to seed UI state)
#   woz_report/shots/*.png     (owned by test_woz_batch.sh — never modified here)
#
# Writes:
#   woz_report/review.html     (atomic: .tmp → mv)
#   woz_report/retest-<label>.txt   (only when --export-retest is used)
#
# Safe to rerun anytime, even while a batch is still writing results.csv.
#
# Triage labels (the vocabulary the review UI lets you tag each disk with):
#   ok          Confirmed working. Hidden by default.
#   more_frames Probably just needs more time; queue for retest.
#   13_sector   Genuine pre-DOS-3.3 13-sector disk. IIgs can't boot this
#               without MUFFIN/similar conversion. Not a sim bug.
#   broken      Real sim bug. Keep visible for debugging.
#   boot_fail   Won't boot even with more frames; likely a dead/bad image.
#   (unset)     Unreviewed. Default filter shows only these.
#
# Usage:
#   ./woz_review.sh                          Rebuild woz_report/review.html.
#   ./woz_review.sh --out DIR                Same, explicit output directory.
#   ./woz_review.sh --export-retest LABEL    Dump paths triaged with LABEL
#                                            into DIR/retest-LABEL.txt.
#
# Typical flow:
#   1) Open woz_report/review.html in a browser.
#   2) Click triage buttons; state lives in browser localStorage.
#   3) Click "Save triage.csv" → drop the download into woz_report/.
#   4) To rerun the "more_frames" bucket at higher frame count:
#         ./woz_review.sh --export-retest more_frames
#         ./test_woz_batch.sh --retest woz_report/retest-more_frames.txt --frames 2000
#   5) Rerun ./woz_review.sh any time to refresh review.html from the
#      latest results.csv; your triage state persists.

set -uo pipefail

OUT="woz_report"
EXPORT_RETEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)            OUT="$2"; shift 2 ;;
    --export-retest)  EXPORT_RETEST="$2"; shift 2 ;;
    --help|-h)
      sed -n '3,40p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

CSV="$OUT/results.csv"
TRIAGE="$OUT/triage.csv"
HTML="$OUT/review.html"
TMP="$HTML.tmp"

if [[ ! -f "$CSV" ]]; then
  echo "ERROR: $CSV not found. Run test_woz_batch.sh first." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# --export-retest mode: extract paths tagged with a given label.
# Triage CSV schema (written by the review UI's Save button):
#   woz_path,label,note,timestamp
# Where:
#   woz_path   always quoted (may contain commas / spaces)
#   label      unquoted enum
#   note       always quoted (may be empty)
#   timestamp  unquoted ISO-8601
# ---------------------------------------------------------------------------
if [[ -n "$EXPORT_RETEST" ]]; then
  if [[ ! -f "$TRIAGE" ]]; then
    echo "ERROR: $TRIAGE not found. Save triage.csv from the review UI first." >&2
    exit 1
  fi
  out_file="$OUT/retest-$EXPORT_RETEST.txt"
  awk -v target="$EXPORT_RETEST" '
    NR == 1 { next }  # skip header
    {
      # woz_path is quoted; find its matching close-quote (handles "" escape)
      if (substr($0, 1, 1) != "\"") next
      i = 2; path = ""
      while (i <= length($0)) {
        c = substr($0, i, 1)
        if (c == "\"" && substr($0, i+1, 1) == "\"") {
          path = path "\""; i += 2
        } else if (c == "\"") {
          i++; break
        } else {
          path = path c; i++
        }
      }
      # Expect comma next, then label
      if (substr($0, i, 1) != ",") next
      i++
      label = ""
      while (i <= length($0) && substr($0, i, 1) != ",") {
        label = label substr($0, i, 1); i++
      }
      if (label == target) print path
    }
  ' "$TRIAGE" > "$out_file"
  n=$(wc -l < "$out_file" | tr -d ' ')
  echo "Wrote $n paths to $out_file"
  if (( n > 0 )); then
    echo ""
    echo "Run them with higher frame count:"
    echo "  ./test_woz_batch.sh --retest $out_file --frames 2000"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Regular mode: build review.html
# ---------------------------------------------------------------------------

mkdir -p "$OUT"

TOTAL=$(awk 'NR > 1' "$CSV" | wc -l | tr -d ' ')
UPDATED=$(date '+%Y-%m-%d %H:%M:%S')
TRIAGE_LINE_COUNT=0
if [[ -f "$TRIAGE" ]]; then
  TRIAGE_LINE_COUNT=$(awk 'NR > 1' "$TRIAGE" | wc -l | tr -d ' ')
fi

# -------- HTML head + styles --------
cat > "$TMP" <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>WOZ Review</title>
<style>
  body { font-family: -apple-system, sans-serif; margin: 15px; background: #f4f4f4; }
  h1 { margin: 0 0 4px 0; }
  .meta { color: #666; margin-bottom: 10px; font-size: 13px; }
  .toolbar { position: sticky; top: 0; background: #f4f4f4; padding: 8px 0;
             border-bottom: 1px solid #ccc; z-index: 10; margin-bottom: 12px; }
  .toolbar > div { margin: 4px 0; }
  .filter-row { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
  .filter-row label { font-weight: bold; font-size: 12px; color: #444; min-width: 60px; }
  .filter-row button { padding: 4px 10px; border: 1px solid #888;
                       background: #fff; cursor: pointer; border-radius: 4px;
                       font-size: 12px; }
  .filter-row button.active { background: #2a6; color: #fff; border-color: #2a6; }
  .toolbar .actions { display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
  .toolbar .actions button, .toolbar .actions select, .toolbar .actions label.file {
    padding: 5px 10px; border: 1px solid #888; background: #fff;
    border-radius: 4px; cursor: pointer; font-size: 12px;
  }
  .toolbar .actions button:hover, .toolbar .actions label.file:hover { background: #eef; }
  .summary { display: inline-flex; gap: 12px; flex-wrap: wrap; font-size: 13px; }
  .summary span.count { padding: 2px 8px; border-radius: 3px; color: #fff;
                        font-weight: bold; font-size: 12px; }
  .count.BOOTED    { background: #2a6; }
  .count.TEXT_ONLY { background: #ca3; }
  .count.BLANK     { background: #888; }
  .count.TIMEOUT   { background: #c33; }
  .count.CRASH     { background: #808; }
  .count.ok           { background: #080; }
  .count.more_frames  { background: #068; }
  .count.a13_sector   { background: #607; }
  .count.broken       { background: #c33; }
  .count.boot_fail    { background: #555; }
  .count.unreviewed   { background: #999; }

  .row { display: flex; background: #fff; border: 1px solid #ccc;
         border-radius: 5px; padding: 8px; margin-bottom: 8px;
         gap: 12px; align-items: flex-start; }
  .row.hidden { display: none; }
  .row img.thumb { width: 220px; height: auto; image-rendering: pixelated;
                   border: 1px solid #888; cursor: zoom-in; flex-shrink: 0; }
  .row img.thumb:hover { box-shadow: 0 3px 8px rgba(0,0,0,0.3); }
  .row-info { flex: 1; min-width: 300px; }
  .row-info .filename { font-weight: bold; font-family: monospace; font-size: 13px; }
  .row-info .path { color: #888; font-family: monospace; font-size: 11px;
                    margin-top: 2px; word-break: break-all; }
  .row-info .badges { margin-top: 6px; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 3px;
           font-weight: bold; font-size: 11px; color: #fff; margin-right: 6px; }
  .badge.BOOTED    { background: #2a6; }
  .badge.TEXT_ONLY { background: #ca3; }
  .badge.BLANK     { background: #888; }
  .badge.TIMEOUT   { background: #c33; }
  .badge.CRASH     { background: #808; }
  .triage-badge { display: inline-block; padding: 2px 8px; border-radius: 3px;
                  font-weight: bold; font-size: 11px; color: #fff; margin-right: 6px; }
  .triage-badge.ok          { background: #080; }
  .triage-badge.more_frames { background: #068; }
  .triage-badge.a13_sector  { background: #607; }
  .triage-badge.broken      { background: #c33; }
  .triage-badge.boot_fail   { background: #555; }
  .triage-badge.unreviewed  { background: #999; }

  .triage-buttons { display: flex; flex-wrap: wrap; gap: 4px;
                    margin-top: 8px; align-items: center; }
  .triage-buttons button {
    padding: 3px 10px; border: 1px solid #888; background: #fff;
    cursor: pointer; border-radius: 3px; font-size: 11px;
  }
  .triage-buttons button.active.ok          { background: #080; color: #fff; border-color: #080; }
  .triage-buttons button.active.more_frames { background: #068; color: #fff; border-color: #068; }
  .triage-buttons button.active.a13_sector  { background: #607; color: #fff; border-color: #607; }
  .triage-buttons button.active.broken      { background: #c33; color: #fff; border-color: #c33; }
  .triage-buttons button.active.boot_fail   { background: #555; color: #fff; border-color: #555; }
  .triage-buttons .note-input {
    flex: 1; min-width: 160px; padding: 3px 6px; font-size: 11px;
    border: 1px solid #aaa; border-radius: 3px;
  }
  .cmd { color: #666; font-family: monospace; font-size: 10px;
         margin-top: 4px; user-select: all; }

  /* Lightbox overlay for full-size screenshot view */
  #lightbox {
    display: none;
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.9);
    z-index: 1000;
    align-items: center; justify-content: center;
    cursor: zoom-out;
  }
  #lightbox.open { display: flex; }
  #lightbox img {
    max-width: 95vw; max-height: 95vh;
    image-rendering: pixelated;
    border: 1px solid #444;
  }
</style>
</head>
<body>
<h1>WOZ Review</h1>
<div class="meta">
  results.csv: $TOTAL rows &nbsp;•&nbsp;
  triage.csv: $TRIAGE_LINE_COUNT entries &nbsp;•&nbsp;
  Generated: $UPDATED &nbsp;•&nbsp;
  <span id="localstorageNote" style="color:#080"></span>
</div>

<div class="toolbar">
  <div class="filter-row">
    <label>Status:</label>
    <button class="status-filter active" data-filter="all">All</button>
    <button class="status-filter" data-filter="BOOTED">BOOTED</button>
    <button class="status-filter" data-filter="TEXT_ONLY">TEXT_ONLY</button>
    <button class="status-filter" data-filter="BLANK">BLANK</button>
    <button class="status-filter" data-filter="TIMEOUT">TIMEOUT</button>
    <button class="status-filter" data-filter="CRASH">CRASH</button>
    <span class="summary" id="statusSummary"></span>
  </div>
  <div class="filter-row">
    <label>Triage:</label>
    <button class="triage-filter active" data-filter="unreviewed">Unreviewed</button>
    <button class="triage-filter" data-filter="all">All</button>
    <button class="triage-filter" data-filter="ok">OK</button>
    <button class="triage-filter" data-filter="more_frames">More frames</button>
    <button class="triage-filter" data-filter="13_sector">13-sector</button>
    <button class="triage-filter" data-filter="broken">Broken</button>
    <button class="triage-filter" data-filter="boot_fail">Boot fail</button>
    <span class="summary" id="triageSummary"></span>
  </div>
  <div class="actions">
    <button id="exportBtn" title="Download triage.csv from your local state">⬇ Export triage.csv</button>
    <label class="file" title="Load a previously saved triage.csv">
      ⬆ Import triage.csv
      <input type="file" id="importFile" accept=".csv" style="display:none">
    </label>
    <select id="exportRetestLabel">
      <option value="">— Export retest for label —</option>
      <option value="more_frames">more_frames</option>
      <option value="broken">broken</option>
      <option value="boot_fail">boot_fail</option>
    </select>
    <button id="exportRetestBtn" title="Download paths for the chosen label">⬇ Export retest list</button>
    <button id="clearNoteBtn" title="Clear note on the currently-viewed row" style="display:none">Clear note</button>
  </div>
</div>

<div id="lightbox"><img src="" alt=""></div>
<div id="rows">
HTML_HEAD

# -------- Per-disk rows --------
# Sort order: status bucket then path.
# Status priority: BOOTED < TEXT_ONLY < BLANK < TIMEOUT < CRASH
awk -F',' '
  function html_escape(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    gsub(/"/, "\\&quot;", s)
    return s
  }
  NR > 1 {
    status = $1
    size   = $2
    hash   = $3
    # rc = $5
    # woz_path is field 6 and always quoted in our CSV
    path = $6
    gsub(/^"/, "", path); gsub(/"$/, "", path)

    # extract basename for display
    n = split(path, parts, "/")
    fname = parts[n]

    ord["BOOTED"]=0; ord["TEXT_ONLY"]=1; ord["BLANK"]=2
    ord["TIMEOUT"]=3; ord["CRASH"]=4
    sort_key = sprintf("%d|%s", ord[status], path)
    rows[++nrows] = sort_key SUBSEP status SUBSEP size SUBSEP hash SUBSEP path SUBSEP fname
  }
  END {
    # sort by sort_key
    # bubble sort is fine here, n is small (~few thousand) and this is
    # only run when regenerating review.html
    for (i = 1; i <= nrows; i++) {
      for (j = i+1; j <= nrows; j++) {
        if (rows[i] > rows[j]) { t = rows[i]; rows[i] = rows[j]; rows[j] = t }
      }
    }
    for (i = 1; i <= nrows; i++) {
      split(rows[i], fields, SUBSEP)
      # fields[1] is sort_key, rest are the real columns
      status = fields[2]; size = fields[3]; hash = fields[4]
      path   = fields[5]; fname  = fields[6]
      pattr  = html_escape(path)
      fattr  = html_escape(fname)
      printf "<div class=\"row\" data-path=\"%s\" data-status=\"%s\" data-hash=\"%s\">\n", pattr, status, hash
      if (hash != "") {
        printf "  <img class=\"thumb\" src=\"shots/%s.png\" loading=\"lazy\" alt=\"\">\n", hash
      } else {
        printf "  <div class=\"thumb\" style=\"width:220px;height:80px;background:#333;color:#fff;display:flex;align-items:center;justify-content:center;font-family:monospace;\">no screenshot</div>\n"
      }
      printf "  <div class=\"row-info\">\n"
      printf "    <div class=\"filename\">%s</div>\n", fattr
      printf "    <div class=\"path\">%s</div>\n", pattr
      printf "    <div class=\"badges\">\n"
      printf "      <span class=\"badge %s\">%s</span>\n", status, status
      printf "      <span class=\"badge\" style=\"background:#999;font-weight:normal\">%d bytes</span>\n", size
      printf "      <span class=\"triage-badge unreviewed\">unreviewed</span>\n"
      printf "    </div>\n"
      printf "    <div class=\"triage-buttons\">\n"
      printf "      <button data-label=\"ok\">OK</button>\n"
      printf "      <button data-label=\"more_frames\">More frames</button>\n"
      printf "      <button data-label=\"13_sector\">13-sector</button>\n"
      printf "      <button data-label=\"broken\">Broken</button>\n"
      printf "      <button data-label=\"boot_fail\">Boot fail</button>\n"
      printf "      <input type=\"text\" class=\"note-input\" placeholder=\"note…\">\n"
      printf "    </div>\n"
      printf "    <div class=\"cmd\">./obj_dir/Vemu --woz \"%s\"</div>\n", pattr
      printf "  </div>\n"
      printf "</div>\n"
    }
  }
' "$CSV" >> "$TMP"

cat >> "$TMP" <<'HTML_SCRIPTS'
</div>

<!-- Seed the UI with triage.csv contents (embedded verbatim; parsed client-side) -->
<script id="initialTriageCsv" type="text/plain">
HTML_SCRIPTS

# Embed triage.csv contents (HTML-escape < and & for safety; paths shouldn't
# have them, but defend anyway). Body only (no code_fence).
if [[ -f "$TRIAGE" ]]; then
  awk '{ gsub(/&/, "\\&amp;"); gsub(/</, "\\&lt;"); print }' "$TRIAGE" >> "$TMP"
fi

cat >> "$TMP" <<'HTML_FOOT'
</script>

<script>
(function() {
  'use strict';

  const STORAGE_KEY = 'woz_review_triage_v1';
  const VALID_LABELS = new Set(['ok', 'more_frames', '13_sector', 'broken', 'boot_fail']);

  // --------------- CSV parsing (single line, standard quote rules) ----------
  function parseCsvLine(line) {
    const out = [];
    let cur = '', q = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (q) {
        if (c === '"' && line[i+1] === '"') { cur += '"'; i++; }
        else if (c === '"') { q = false; }
        else { cur += c; }
      } else {
        if (c === ',') { out.push(cur); cur = ''; }
        else if (c === '"') { q = true; }
        else { cur += c; }
      }
    }
    out.push(cur);
    return out;
  }

  function csvEscape(s) {
    s = String(s == null ? '' : s);
    if (s.includes(',') || s.includes('"') || s.includes('\n')) {
      s = '"' + s.replace(/"/g, '""') + '"';
    }
    return s;
  }

  // --------------- Triage store ---------------
  // map: path -> {label, note, ts}
  function loadLocal() {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}'); }
    catch (e) { return {}; }
  }
  function saveLocal(map) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(map));
  }

  // Seed from embedded triage.csv unless localStorage already has entries.
  function seedFromEmbedded() {
    const local = loadLocal();
    if (Object.keys(local).length > 0) return local;  // don't clobber
    const csv = document.getElementById('initialTriageCsv').textContent.trim();
    if (!csv) return local;
    const lines = csv.split('\n');
    const map = {};
    for (let i = 1; i < lines.length; i++) {  // skip header
      const line = lines[i];
      if (!line.trim()) continue;
      const fields = parseCsvLine(line);
      if (fields.length < 2) continue;
      const [path, label, note, ts] = fields;
      if (!path) continue;
      map[path] = {
        label: label || '',
        note: note || '',
        ts: ts || '',
      };
    }
    saveLocal(map);
    return map;
  }

  // --------------- UI wiring ---------------
  function applyMapToUI(map) {
    document.querySelectorAll('.row').forEach(row => {
      const path = row.dataset.path;
      const entry = map[path];
      const triageBadge = row.querySelector('.triage-badge');
      const label = (entry && entry.label) || '';
      // Normalize badge/button class (13_sector -> a13_sector because CSS class
      // can't start with a digit).
      const cls = label ? (/^\d/.test(label) ? 'a' + label : label) : 'unreviewed';
      triageBadge.className = 'triage-badge ' + cls;
      triageBadge.textContent = label || 'unreviewed';
      row.dataset.triage = label || 'unreviewed';

      row.querySelectorAll('.triage-buttons button').forEach(b => {
        const bl = b.dataset.label;
        const bcls = /^\d/.test(bl) ? 'a' + bl : bl;
        b.classList.toggle('active', bl === label);
        // Ensure the CSS-class-safe variant is present for coloring
        b.classList.remove('ok','more_frames','a13_sector','broken','boot_fail');
        if (bl === label) b.classList.add(bcls);
      });

      const noteInput = row.querySelector('.note-input');
      if (noteInput && document.activeElement !== noteInput) {
        noteInput.value = (entry && entry.note) || '';
      }
    });
    updateSummary(map);
    applyFilters();
  }

  function onTriageButton(e) {
    const row = e.target.closest('.row');
    const label = e.target.dataset.label;
    if (!row || !label) return;
    const path = row.dataset.path;
    const map = loadLocal();
    const entry = map[path];
    const note = row.querySelector('.note-input').value.trim();
    if (entry && entry.label === label) {
      // Toggle off — remove label but keep note if any
      if (note) {
        map[path] = { label: '', note: note, ts: new Date().toISOString() };
      } else {
        delete map[path];
      }
    } else {
      map[path] = { label: label, note: note, ts: new Date().toISOString() };
    }
    saveLocal(map);
    applyMapToUI(map);
  }

  function onNoteChange(e) {
    const row = e.target.closest('.row');
    if (!row) return;
    const path = row.dataset.path;
    const map = loadLocal();
    const note = e.target.value;
    if (!map[path]) {
      map[path] = { label: '', note: note, ts: new Date().toISOString() };
    } else {
      map[path].note = note;
      map[path].ts = new Date().toISOString();
    }
    // Don't persist empty-label + empty-note entries
    if (!map[path].label && !map[path].note) delete map[path];
    saveLocal(map);
  }

  // --------------- Filters ---------------
  function currentStatusFilter() {
    const b = document.querySelector('.status-filter.active');
    return b ? b.dataset.filter : 'all';
  }
  function currentTriageFilter() {
    const b = document.querySelector('.triage-filter.active');
    return b ? b.dataset.filter : 'unreviewed';
  }
  function applyFilters() {
    const sf = currentStatusFilter();
    const tf = currentTriageFilter();
    let shown = 0;
    document.querySelectorAll('.row').forEach(row => {
      const s = row.dataset.status;
      const t = row.dataset.triage || 'unreviewed';
      const sOk = sf === 'all' || s === sf;
      const tOk = tf === 'all' ||
                  (tf === 'unreviewed' && t === 'unreviewed') ||
                  t === tf;
      const show = sOk && tOk;
      row.classList.toggle('hidden', !show);
      if (show) shown++;
    });
    document.getElementById('localstorageNote').textContent =
      `Showing ${shown} of ${document.querySelectorAll('.row').length}`;
  }

  function updateSummary(map) {
    const rows = document.querySelectorAll('.row');
    const statusCounts = {};
    const triageCounts = { unreviewed: 0 };
    rows.forEach(row => {
      const s = row.dataset.status;
      statusCounts[s] = (statusCounts[s] || 0) + 1;
      const entry = map[row.dataset.path];
      if (entry && entry.label && VALID_LABELS.has(entry.label)) {
        triageCounts[entry.label] = (triageCounts[entry.label] || 0) + 1;
      } else {
        triageCounts.unreviewed++;
      }
    });
    function paint(containerId, counts, order) {
      const el = document.getElementById(containerId);
      el.innerHTML = '';
      order.forEach(k => {
        if (!counts[k]) return;
        const cls = /^\d/.test(k) ? 'a' + k : k;
        const span = document.createElement('span');
        span.className = 'count ' + cls;
        span.textContent = k + ': ' + counts[k];
        el.appendChild(span);
      });
    }
    paint('statusSummary', statusCounts, ['BOOTED','TEXT_ONLY','BLANK','TIMEOUT','CRASH']);
    paint('triageSummary', triageCounts,
          ['unreviewed','ok','more_frames','13_sector','broken','boot_fail']);
  }

  // --------------- Import/Export ---------------
  function exportTriageCsv() {
    const map = loadLocal();
    const lines = ['woz_path,label,note,timestamp'];
    Object.keys(map).sort().forEach(path => {
      const e = map[path];
      lines.push([path, e.label || '', e.note || '', e.ts || ''].map(csvEscape).join(','));
    });
    const blob = new Blob([lines.join('\n') + '\n'], {type: 'text/csv'});
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'triage.csv';
    a.click();
  }

  function importTriageFile(file) {
    const reader = new FileReader();
    reader.onload = (e) => {
      const text = e.target.result;
      const lines = text.split('\n');
      const map = loadLocal();
      for (let i = 1; i < lines.length; i++) {  // skip header
        const line = lines[i];
        if (!line.trim()) continue;
        const fields = parseCsvLine(line);
        if (fields.length < 2) continue;
        const [path, label, note, ts] = fields;
        if (!path) continue;
        map[path] = { label: label || '', note: note || '', ts: ts || '' };
      }
      saveLocal(map);
      applyMapToUI(map);
      alert('Imported ' + (lines.length - 1) + ' rows');
    };
    reader.readAsText(file);
  }

  function exportRetestList() {
    const label = document.getElementById('exportRetestLabel').value;
    if (!label) { alert('Pick a label first'); return; }
    const map = loadLocal();
    const paths = [];
    Object.keys(map).forEach(p => {
      if (map[p].label === label) paths.push(p);
    });
    if (paths.length === 0) { alert('Nothing tagged "' + label + '"'); return; }
    const blob = new Blob([paths.join('\n') + '\n'], {type: 'text/plain'});
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'retest-' + label + '.txt';
    a.click();
  }

  // --------------- Lightbox ---------------
  const lightbox = document.getElementById('lightbox');
  const lightboxImg = lightbox.querySelector('img');
  document.addEventListener('click', (e) => {
    if (e.target.matches('.row img.thumb')) {
      lightboxImg.src = e.target.src;
      lightbox.classList.add('open');
    }
  });
  lightbox.addEventListener('click', () => lightbox.classList.remove('open'));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') lightbox.classList.remove('open');
  });

  // --------------- Wire up listeners ---------------
  document.addEventListener('click', (e) => {
    if (e.target.matches('.triage-buttons button')) onTriageButton(e);
  });
  document.addEventListener('change', (e) => {
    if (e.target.matches('.note-input')) onNoteChange(e);
  });
  document.addEventListener('input', (e) => {
    if (e.target.matches('.note-input')) onNoteChange(e);
  });
  document.querySelectorAll('.status-filter').forEach(b => {
    b.addEventListener('click', () => {
      document.querySelectorAll('.status-filter').forEach(x => x.classList.remove('active'));
      b.classList.add('active');
      applyFilters();
    });
  });
  document.querySelectorAll('.triage-filter').forEach(b => {
    b.addEventListener('click', () => {
      document.querySelectorAll('.triage-filter').forEach(x => x.classList.remove('active'));
      b.classList.add('active');
      applyFilters();
    });
  });
  document.getElementById('exportBtn').addEventListener('click', exportTriageCsv);
  document.getElementById('importFile').addEventListener('change', (e) => {
    if (e.target.files[0]) importTriageFile(e.target.files[0]);
  });
  document.getElementById('exportRetestBtn').addEventListener('click', exportRetestList);

  // --------------- Init ---------------
  const map = seedFromEmbedded();
  applyMapToUI(map);
})();
</script>
</body>
</html>
HTML_FOOT

# Atomic rename so a browser reading the file never sees a partial write
mv "$TMP" "$HTML"

echo "Wrote $HTML"
echo "  results rows: $TOTAL"
echo "  triage rows:  $TRIAGE_LINE_COUNT"
echo ""
echo "Open it:  open $HTML"
