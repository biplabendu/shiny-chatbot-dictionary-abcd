/* ============================================================
   ABCD Dictionary Search — app.js

   All client-side behavior for the app. Kept in a separate file
   (served from www/, like app.css) rather than inlined in app.R:
   embedding JS inside an R string means every \n, \t and \" is an
   R escape, so a stray backslash silently corrupts the whole
   <script> block. Plain .js has none of that fragility.

   The two data-driven values (which columns to hide on desktop vs.
   mobile) are injected from R as `window.ABCD_HIDDEN` via a tiny
   inline <script> in app.R, and read here.
   ============================================================ */

// Submit the search when Enter is pressed in the query box (Shift+Enter still
// inserts a newline). Clicking #run_search is what actually triggers the
// Shiny search observer.
$(document).on('keydown', '#search_query', function(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    $('#run_search').click();
  }
});

// Cap the search query at 250 characters: truncate live input and keep a
// running character count in the helper text below the textarea.
var QUERY_CHAR_LIMIT = 250;
$(document).on('input', '#search_query', function() {
  if (this.value.length > QUERY_CHAR_LIMIT) {
    this.value = this.value.slice(0, QUERY_CHAR_LIMIT);
    $(this).trigger('change');
  }
  $('#search_query_count').text(this.value.length + ' / ' + QUERY_CHAR_LIMIT + ' characters');
});

// On small screens, collapse both sidebars the moment a search starts so the
// results table fills the screen immediately. The server also calls
// toggle_sidebar(), but those messages only flush AFTER the observer's blocking
// work (Sys.sleep + the synchronous Python search) completes, so the collapse
// felt slow. Doing it client-side gives instant feedback, independent of the R
// round-trip; the server call remains an idempotent fallback. This fires for
// the Enter-key path too, which clicks #run_search. Uses the semantic
// aria-controls attribute bslib puts on each sidebar's collapse toggle, and
// only collapses a sidebar that is currently open.
$(document).on('click', '#run_search', function() {
  if (!window.matchMedia('(max-width: 768px)').matches) return;
  ['left_sidebar', 'right_sidebar'].forEach(function(id) {
    var btn = document.querySelector('.collapse-toggle[aria-controls="' + id + '"]');
    if (btn && btn.getAttribute('aria-expanded') === 'true') btn.click();
  });
  // Then expand the results card to bslib full-screen so the table gets the
  // whole viewport (matches the manual expand button). Guard on data-full-screen
  // so a repeat search doesn't toggle back out of it.
  var card = document.getElementById('results_card');
  if (card && card.getAttribute('data-full-screen') !== 'true') {
    var expand = card.querySelector('.bslib-full-screen-enter');
    if (expand) expand.click();
  }
});

// Report viewport width to Shiny so the server can branch on mobile.
function _reportWidth() {
  if (window.Shiny && Shiny.setInputValue) {
    Shiny.setInputValue('window_width', window.innerWidth, {priority: 'event'});
  }
}
$(document).on('shiny:connected', _reportWidth);
$(window).on('resize', _reportWidth);

// Guided tour (cicerone): report whether this browser has already seen the tour
// so the server auto-starts it only on a user's first visit. Persisted in
// localStorage so it survives across sessions/reloads (cicerone's run_once is
// per-session only and would re-fire every visit). Disabled on small screens
// (<=768px, the app's mobile breakpoint): the sidebars collapse there, so tour
// highlights would frame hidden controls. Not sending 'tour_seen' means the
// auto-start observer never fires, and the 'Take a tour' button is hidden via
// CSS at this width — so the tour is fully unavailable on mobile.
$(document).on('shiny:connected', function() {
  if (window.matchMedia('(max-width: 768px)').matches) return;
  Shiny.setInputValue(
    'tour_seen',
    localStorage.getItem('abcd_tour_seen') === '1',
    {priority: 'event'}
  );
});
Shiny.addCustomMessageHandler('mark_tour_seen', function(x) {
  localStorage.setItem('abcd_tour_seen', '1');
});

// After the results table renders, apply the viewport-appropriate hidden-columns
// set so the table state is explicit (the CSV-download button reads
// state.hiddenColumns).
//   Desktop: hide everything except the curated 8 columns.
//   Mobile:  hide everything except `name` and `label`.
$(document).on('shiny:value', function(event) {
  if (event.name !== 'results_table') return;
  var cfg = window.ABCD_HIDDEN || { desktop: [], mobile: [] };
  setTimeout(function() {
    try {
      var hidden = window.matchMedia('(max-width: 768px)').matches
                 ? cfg.mobile
                 : cfg.desktop;
      Reactable.setHiddenColumns('results_table', hidden);
    } catch (e) { /* table not ready yet */ }
  }, 150);
});

// Copy the variable names of the current results to the clipboard, one per
// line. Uses reactable's sortedData so it respects the table's search and
// column filters and spans ALL pages (not just the visible one).
function _legacyCopy(text) {
  try {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.focus(); ta.select();
    var ok = document.execCommand('copy');
    document.body.removeChild(ta);
    return ok;
  } catch (e) { return false; }
}
function copyVariableNames(btn) {
  var state = (window.Reactable && Reactable.getState('results_table')) || {};
  var rows = state.sortedData || state.data || [];
  var names = rows
    .map(function(r) { return r.name; })
    .filter(function(n) { return n != null && String(n).length; });

  // Briefly swap the button label to give feedback, then restore it.
  function flash(msg) {
    if (!btn) return;
    if (!btn.dataset.orig) btn.dataset.orig = btn.innerHTML;
    btn.textContent = msg;
    clearTimeout(btn._flashT);
    btn._flashT = setTimeout(function() {
      btn.innerHTML = btn.dataset.orig;
    }, 1500);
  }

  if (!names.length) { flash('Nothing to copy'); return; }

  var text = names.join('\n');
  var ok   = function() { flash('Copied ' + names.length + ' names'); };
  var fail = function() { flash('Copy failed'); };

  // navigator.clipboard needs a secure context (https/localhost); fall back to
  // execCommand otherwise or if it rejects.
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(ok, function() {
      if (_legacyCopy(text)) ok(); else fail();
    });
  } else {
    if (_legacyCopy(text)) ok(); else fail();
  }
}
