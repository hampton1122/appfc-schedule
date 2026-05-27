(function () {
  'use strict';

  var APPFC_ID = '8105';
  var APPFC_CREST = 'https://d11602kq9f3hhz.cloudfront.net/academy/1459/461548/a814a484-b145-45ac-860b-c8185fe29a09/461548.png';
  var SE_BASE_URL = 'https://www.sportsengineplay.com';

  // Resolve matches.json relative to this script so the embed can live
  // anywhere (Square, GH Pages, etc.) without hardcoding the host.
  var DATA_URL = (function () {
    var scripts = document.getElementsByTagName('script');
    for (var i = scripts.length - 1; i >= 0; i--) {
      var src = scripts[i].src || '';
      if (src.indexOf('schedule.js') !== -1) {
        return src.replace(/schedule\.js(\?.*)?$/, 'matches.json');
      }
    }
    return 'matches.json';
  })();

  var MONTHS_SHORT = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
  var MONTHS_LONG  = ['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];
  var DAYS = ['SUN','MON','TUE','WED','THU','FRI','SAT'];

  var ICON_PIN = '<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>';
  var ICON_PLAY = '<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3" fill="currentColor" stroke="none"/></svg>';
  var ICON_DETAILS = '<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>';

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function formatTime(d) {
    var h = d.getHours(), m = d.getMinutes();
    var ap = h >= 12 ? 'PM' : 'AM';
    h = h % 12; if (h === 0) h = 12;
    return h + ':' + (m < 10 ? '0' + m : m) + ' ' + ap;
  }

  function renderTeam(team) {
    var crest = team.crest || (team.id === APPFC_ID ? APPFC_CREST : '');
    var crestStyle = crest ? 'style="background-image:url(\'' + escapeHtml(crest) + '\')"' : '';
    return '<span class="appfc-team">' +
             '<span class="appfc-crest" ' + crestStyle + ' aria-hidden="true"></span>' +
             '<span>' + escapeHtml(team.name) + '</span>' +
           '</span>';
  }

  function computeRecord(matches) {
    var w = 0, l = 0, d = 0, gf = 0, ga = 0;
    matches.forEach(function (m) {
      if (!m.score) return;
      var appHome = m.home.id === APPFC_ID;
      var appFor  = appHome ? m.score.home : m.score.away;
      var appAg   = appHome ? m.score.away : m.score.home;
      gf += appFor; ga += appAg;
      if (appFor > appAg) w++;
      else if (appFor < appAg) l++;
      else d++;
    });
    return { w: w, l: l, d: d, gf: gf, ga: ga, played: w + l + d };
  }

  function renderRecordBanner(matches) {
    var r = computeRecord(matches);
    if (!r.played) return '';
    var gd = r.gf - r.ga;
    var gdStr = (gd > 0 ? '+' : '') + gd;
    return '<div class="appfc-record">' +
             '<span class="appfc-record-label">2026 Season</span>' +
             '<span class="appfc-record-stat"><strong>' + r.w + '</strong>W</span>' +
             '<span class="appfc-record-stat"><strong>' + r.l + '</strong>L</span>' +
             '<span class="appfc-record-stat"><strong>' + r.d + '</strong>D</span>' +
             '<span class="appfc-record-sep"></span>' +
             '<span class="appfc-record-stat">GF <strong>' + r.gf + '</strong></span>' +
             '<span class="appfc-record-stat">GA <strong>' + r.ga + '</strong></span>' +
             '<span class="appfc-record-stat">GD <strong>' + gdStr + '</strong></span>' +
           '</div>';
  }

  function render(matches, streamPaths) {
    var container = document.getElementById('appfc-schedule-content');
    if (!container) return;

    matches.sort(function (a, b) { return a.date - b.date; });

    var html = renderRecordBanner(matches);
    var currentMonthKey = '';

    matches.forEach(function (m) {
      var isAppFcHome = m.home.id === APPFC_ID;
      var monthKey = m.date.getFullYear() + '-' + m.date.getMonth();

      if (monthKey !== currentMonthKey) {
        if (currentMonthKey !== '') html += '</div>';
        currentMonthKey = monthKey;
        html += '<h3 class="appfc-month-header">' +
                  MONTHS_LONG[m.date.getMonth()] + ' ' + m.date.getFullYear() +
                '</h3>';
        html += '<div class="appfc-match-list">';
      }

      var mo = MONTHS_SHORT[m.date.getMonth()];
      var dy = m.date.getDate();
      var dow = DAYS[m.date.getDay()];

      var locInner = '<span class="appfc-meta-item">' + ICON_PIN + escapeHtml(m.location) + '</span>';
      var metaHtml = m.mapsUrl
        ? '<a href="' + escapeHtml(m.mapsUrl) + '" target="_blank" rel="noopener">' + locInner + '</a>'
        : locInner;

      var streamPath = streamPaths[m.id];
      if (streamPath) {
        var streamUrl = SE_BASE_URL + streamPath;
        metaHtml +=
          '<a href="' + escapeHtml(streamUrl) + '" target="_blank" rel="noopener">' +
            '<span class="appfc-meta-item appfc-watch">' + ICON_PLAY + 'Watch on SportsEngine</span>' +
          '</a>';
      }

      if (m.detailsUrl) {
        metaHtml +=
          '<a href="' + escapeHtml(m.detailsUrl) + '" target="_blank" rel="noopener">' +
            '<span class="appfc-meta-item">' + ICON_DETAILS + 'Match details</span>' +
          '</a>';
      }

      var isFinal = !!m.score;
      var middleHtml;
      if (isFinal) {
        var appFor = isAppFcHome ? m.score.home : m.score.away;
        var appAg  = isAppFcHome ? m.score.away : m.score.home;
        var resultClass = appFor > appAg ? ' appfc-win'
                         : appFor < appAg ? ' appfc-loss'
                         : ' appfc-draw';
        middleHtml = '<span class="appfc-score' + resultClass + '">' +
                       m.score.home + ' - ' + m.score.away +
                     '</span>';
      } else {
        middleHtml = '<span class="appfc-vs">VS</span>';
      }

      var timeHtml = isFinal
        ? '<span class="appfc-time-label">Final</span>FT'
        : '<span class="appfc-time-label">Kickoff</span>' + formatTime(m.date);

      html +=
        '<div class="appfc-match' + (isAppFcHome ? ' is-home' : '') + (isFinal ? ' is-final' : '') + '">' +
          '<div class="appfc-date">' +
            '<span class="appfc-date-month">' + mo + '</span>' +
            '<span class="appfc-date-day">' + dy + '</span>' +
            '<span class="appfc-date-dow">' + dow + '</span>' +
          '</div>' +
          '<div class="appfc-info">' +
            '<div class="appfc-teams">' +
              renderTeam(m.home) +
              middleHtml +
              renderTeam(m.away) +
            '</div>' +
            '<div class="appfc-meta">' + metaHtml + '</div>' +
          '</div>' +
          '<div class="appfc-time">' + timeHtml + '</div>' +
        '</div>';
    });
    if (currentMonthKey !== '') html += '</div>';

    container.innerHTML = html;
  }

  function load() {
    // Coarse cache-buster: rotates once a minute so updates appear quickly
    // while still letting repeated page loads inside the same minute hit cache.
    var bust = Math.floor(Date.now() / 60000);
    fetch(DATA_URL + '?v=' + bust)
      .then(function (r) {
        if (!r.ok) throw new Error('Failed to load matches: ' + r.status);
        return r.json();
      })
      .then(function (data) {
        var matches = (data.matches || []).map(function (m) {
          return Object.assign({}, m, { date: new Date(m.date) });
        });
        render(matches, data.streams || {});
      })
      .catch(function (err) {
        var container = document.getElementById('appfc-schedule-content');
        if (container) {
          container.innerHTML = '<p style="color:#6b6b6b;font-family:sans-serif;">' +
                                'Unable to load schedule right now.</p>';
        }
        if (window.console) console.error('[appfc-schedule]', err);
      });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', load);
  } else {
    load();
  }
})();
