#!/usr/bin/env bash
# Fetch the Modular11 public schedule HTML and the SportsEngine Play
# GraphQL livestream list, then emit the MATCHES and STREAM_PATHS blocks
# used by schedule.html.
#
# Usage:
#   ./generate_matches.sh                  # print MATCHES + STREAM_PATHS to stdout
#   ./generate_matches.sh --update         # replace both blocks in schedule.html
#   ./generate_matches.sh --url '<url>'    # use a different Modular11 endpoint
#   ./generate_matches.sh --file <path>    # target a specific schedule.html
#   ./generate_matches.sh --no-streams     # skip SE fetch (MATCHES only)
set -euo pipefail

DEFAULT_URL='https://www.modular11.com/public_schedule/league/get_matches?open_page=0&academy=0&tournament=24&gender=0&age=0&brackets=&groups=&group=&match_number=0&status=all&match_type=2&schedule=0&team=0&teamPlayer=8105&location=0&as_referee=0&report_status=0&start_date=2026-04-21+00%3A00%3A00&end_date=2026-12-31+23%3A59%3A59'

SE_GRAPHQL_URL='https://api.sportsengineplay.com/graphql'
SE_CHANNEL_ID='69a6f38d3a27983e4f7e7bff'
SE_QUERY_HASH='31b3404758f5801d51d1ead0a85505d2fc65f9cd1218f9e398c3dacbc0eab2c5'

URL="$DEFAULT_URL"
UPDATE=0
FILE=""
FETCH_STREAMS=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)         URL="$2"; shift 2 ;;
        --update)      UPDATE=1; shift ;;
        --file)        FILE="$2"; shift 2 ;;
        --no-streams)  FETCH_STREAMS=0; shift ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${FILE:=$SCRIPT_DIR/static_schedule.html}"

IFS= read -r -d '' AWK_PROG <<'AWK_EOF' || true
BEGIN {
    RS = "<div class=\"row table-content-row table-content-row-uls"
    APPFC_ID = "8105"
    SQ = sprintf("%c", 39)
    n = 0
}
NR == 1 { next }
{
    chunk = $0

    id = ""
    if (match(chunk, /uid-mobile-style">[ \t\n]*[0-9]+/)) {
        s = substr(chunk, RSTART, RLENGTH)
        sub(/.*>[ \t\n]*/, "", s)
        id = s
    }
    if (id == "") next

    mo = 0; dy = 0; yr = 0; hh = 0; mm = 0; ap = ""
    if (match(chunk, /[0-9][0-9]\/[0-9][0-9]\/[0-9][0-9] [0-9][0-9]:[0-9][0-9][ap]m/)) {
        dt = substr(chunk, RSTART, RLENGTH)
        mo = substr(dt, 1, 2) + 0
        dy = substr(dt, 4, 2) + 0
        yr = substr(dt, 7, 2) + 0
        hh = substr(dt, 10, 2) + 0
        mm = substr(dt, 13, 2) + 0
        ap = substr(dt, 15, 2)
    }
    year = 2000 + yr
    month_idx = mo - 1
    hour = hh % 12
    if (ap == "pm") hour += 12
    minute = mm

    maps_url = ""
    if (match(chunk, /href="https:\/\/www\.google\.com\/maps\/search\/[^"]*"/)) {
        s = substr(chunk, RSTART, RLENGTH)
        sub(/^href="/, "", s)
        sub(/"$/, "", s)
        gsub(/&amp;/, "\\&", s)
        maps_url = s
    }

    location = ""
    if (match(chunk, /<p data-title="[^"]+"/)) {
        s = substr(chunk, RSTART, RLENGTH)
        sub(/^<p data-title="/, "", s)
        sub(/"$/, "", s)
        p = index(s, " - ")
        if (p > 0) s = substr(s, p + 3)
        location = s
    }

    t_ids[1] = ""; t_ids[2] = ""
    t_names[1] = ""; t_names[2] = ""
    rest = chunk
    tn = 0
    while (tn < 2 && match(rest, /\/league-schedule\/teams\/[0-9]+"[^>]*>[ \t\n]*<p data-title="[^"]+"/)) {
        outer_rs = RSTART; outer_rl = RLENGTH
        seg = substr(rest, outer_rs, outer_rl)
        tid = ""; tname = ""
        if (match(seg, /teams\/[0-9]+/)) {
            tid = substr(seg, RSTART + 6, RLENGTH - 6)
        }
        if (match(seg, /data-title="[^"]+"/)) {
            tname = substr(seg, RSTART + 12, RLENGTH - 13)
        }
        tn++
        t_ids[tn] = tid
        t_names[tn] = tname
        rest = substr(rest, outer_rs + outer_rl)
    }

    delete crest_ids
    delete crest_urls
    rest = chunk
    cn = 0
    while (match(rest, /\/league-schedule\/teams\/[0-9]+"[^>]*>[ \t\n]*<div class="club-photo" style="background-image: url\('[^']*'\)/)) {
        outer_rs = RSTART; outer_rl = RLENGTH
        seg = substr(rest, outer_rs, outer_rl)
        cid = ""; cu = ""
        if (match(seg, /teams\/[0-9]+/)) {
            cid = substr(seg, RSTART + 6, RLENGTH - 6)
        }
        if (match(seg, /url\('[^']*'\)/)) {
            cu = substr(seg, RSTART + 5, RLENGTH - 7)
        }
        cn++
        crest_ids[cn] = cid
        crest_urls[cn] = cu
        rest = substr(rest, outer_rs + outer_rl)
    }

    home_crest = ""; away_crest = ""
    for (i = 1; i <= cn; i++) {
        if (crest_ids[i] == t_ids[1] && home_crest == "") home_crest = crest_urls[i]
        if (crest_ids[i] == t_ids[2] && away_crest == "") away_crest = crest_urls[i]
    }

    home_score = ""; away_score = ""
    if (match(chunk, /<span class="score-match-table">[^<]*<\/span>/)) {
        s = substr(chunk, RSTART, RLENGTH)
        sub(/^<span[^>]*>/, "", s)
        sub(/<\/span>$/, "", s)
        gsub(/&nbsp;?/, "", s)
        gsub(/[ \t]/, "", s)
        if (match(s, /^[0-9]+:[0-9]+$/)) {
            colon = index(s, ":")
            home_score = substr(s, 1, colon - 1)
            away_score = substr(s, colon + 1)
        }
    }

    details_url = ""
    if (match(chunk, /href="\/match_details\/[0-9]+\/[0-9]+"/)) {
        s = substr(chunk, RSTART, RLENGTH)
        sub(/^href="/, "", s)
        sub(/"$/, "", s)
        details_url = "https://www.modular11.com" s
    }

    if (home_score != "" && away_score != "") {
        score_js = "{ home: " home_score ", away: " away_score " }"
    } else {
        score_js = "null"
    }

    n++
    sort_keys[n] = sprintf("%04d-%02d-%02d-%02d-%02d", year, month_idx, dy, hour, minute)
    js_records[n] = \
        "    {\n" \
        "      id: " jsstr(id) ",\n" \
        "      date: new Date(" year ", " month_idx ", " dy ", " hour ", " minute "),\n" \
        "      home: " team_js(t_names[1], t_ids[1], home_crest) ",\n" \
        "      away: " team_js(t_names[2], t_ids[2], away_crest) ",\n" \
        "      location: " jsstr(location) ",\n" \
        "      mapsUrl: " jsstr(maps_url) ",\n" \
        "      detailsUrl: " jsstr(details_url) ",\n" \
        "      score: " score_js "\n" \
        "    }"

    # Sidecar index for downstream stream-URL matching.
    idx_records[n] = sprintf("%s\t%04d-%02d-%02d\t%s\t%s", id, year, month_idx + 1, dy, t_names[1], t_names[2])
}

function jsstr(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/'/, "\\'", s)
    return SQ s SQ
}

function team_js(name, id, crest) {
    if (id == APPFC_ID) {
        return "{ name: " jsstr(name) ", id: " jsstr(id) ", crest: APPFC_CREST }"
    }
    return "{ name: " jsstr(name) ", id: " jsstr(id) ", crest: " jsstr(crest) " }"
}

END {
    for (i = 1; i <= n; i++) ord[i] = i
    for (i = 2; i <= n; i++) {
        k = ord[i]
        j = i - 1
        while (j >= 1 && sort_keys[ord[j]] > sort_keys[k]) {
            ord[j+1] = ord[j]
            j--
        }
        ord[j+1] = k
    }
    print "  var MATCHES = ["
    for (i = 1; i <= n; i++) {
        line = js_records[ord[i]]
        if (i < n) line = line ","
        print line
    }
    print "  ];"
    print "##__INDEX__##"
    for (i = 1; i <= n; i++) {
        print idx_records[ord[i]]
    }
}
AWK_EOF

# --- Fetch + parse Modular11 -------------------------------------------------

RAW_OUT="$(curl -fsS --compressed "$URL" -H 'X-Requested-With: XMLHttpRequest' | awk "$AWK_PROG")"

if [[ -z "$RAW_OUT" ]]; then
    echo "No matches parsed from response." >&2
    exit 1
fi

MATCHES_BLOCK="${RAW_OUT%%##__INDEX__##*}"
MATCHES_BLOCK="${MATCHES_BLOCK%$'\n'}"
INDEX_BLOCK="${RAW_OUT#*##__INDEX__##}"
INDEX_BLOCK="${INDEX_BLOCK#$'\n'}"

# --- Fetch SE streams + build STREAM_PATHS ---------------------------------

if [[ "$FETCH_STREAMS" -eq 1 ]]; then
    SE_REQUEST=$(cat <<JSON
{"operationName":"GetLiveStreams","variables":{"limit":100,"showNonScheduled":false,"hideCourtStreams":true,"showOnlyCourtStreams":false,"channelId":"${SE_CHANNEL_ID}","page":1,"gender":"","level":"","sport":"","sort":{"liveStartDateTime":1,"weight":1},"isLiveOrUpcoming":true,"teamId":"","participantId":null,"subVenue":null,"venue":""},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"${SE_QUERY_HASH}"}}}
JSON
)
    SE_JSON=$(curl -fsS --compressed -X POST "$SE_GRAPHQL_URL" \
        -H 'Content-Type: application/json' \
        --data "$SE_REQUEST")
else
    SE_JSON='{"data":{"liveStreams":{"data":[]}}}'
fi

STREAM_PATHS_BLOCK=$(
    SE_JSON="$SE_JSON" INDEX_BLOCK="$INDEX_BLOCK" EXISTING_FILE="$FILE" \
    python3 - <<'PYEOF'
import json, os, re, sys, datetime

se = json.loads(os.environ["SE_JSON"])
streams = (se.get("data") or {}).get("liveStreams") or {}
streams = streams.get("data") or []

def norm(name):
    return re.sub(r"\s+", " ", (name or "").strip().lower())

# date_key -> list of (pageUrl, home_norm, away_norm)
by_date = {}
for s in streams:
    page_url = s.get("pageUrl")
    ts = s.get("liveStartDateTime")
    if not page_url or ts is None:
        continue
    dt = datetime.datetime.fromtimestamp(int(ts) / 1000)
    key = dt.strftime("%Y-%m-%d")
    home = (((s.get("homeTeamChannel") or {}).get("team") or {}).get("name")) or ""
    away = (((s.get("awayTeamChannel") or {}).get("team") or {}).get("name")) or ""
    by_date.setdefault(key, []).append((page_url, norm(home), norm(away)))

# Load existing STREAM_PATHS (preserve entries the API didn't return — e.g. past games).
existing = {}
file_path = os.environ.get("EXISTING_FILE", "")
if file_path and os.path.exists(file_path):
    with open(file_path) as f:
        src = f.read()
    m = re.search(r"var STREAM_PATHS = \{(.*?)\};", src, re.DOTALL)
    if m:
        for line in m.group(1).splitlines():
            entry = re.match(r"\s*'([^']+)'\s*:\s*'([^']+)'", line)
            if entry:
                existing[entry.group(1)] = entry.group(2)

# Walk the Modular11 match index, pick a stream per match.
out = []
for line in os.environ["INDEX_BLOCK"].splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    if len(parts) < 4:
        continue
    mid, date_key, home, away = parts[0], parts[1], parts[2], parts[3]
    candidates = by_date.get(date_key, [])
    chosen = None
    if len(candidates) == 1:
        chosen = candidates[0][0]
    elif len(candidates) > 1:
        h, a = norm(home), norm(away)
        for url, sh, sa in candidates:
            if h and sh and h.split()[0] == sh.split()[0]:
                chosen = url
                break
        if not chosen:
            chosen = candidates[0][0]
    if not chosen:
        chosen = existing.get(mid)
    if chosen:
        out.append((mid, chosen))

print("  var STREAM_PATHS = {")
for i, (mid, url) in enumerate(out):
    mid_esc = mid.replace("\\", "\\\\").replace("'", "\\'")
    url_esc = url.replace("\\", "\\\\").replace("'", "\\'")
    comma = "," if i < len(out) - 1 else ""
    print(f"    '{mid_esc}': '{url_esc}'{comma}")
print("  };")
PYEOF
)

COMBINED_BLOCK="${MATCHES_BLOCK}"$'\n\n'"${STREAM_PATHS_BLOCK}"

# --- Output or in-place update ---------------------------------------------

replace_block() {
    # $1 = file, $2 = start regex, $3 = end regex, $4 = replacement content
    local file="$1" start_re="$2" end_re="$3" content="$4"
    local tmp; tmp="$(mktemp)"
    if ! START_RE="$start_re" END_RE="$end_re" REPL="$content" awk '
            BEGIN { replaced = 0; in_block = 0; start_re = ENVIRON["START_RE"]; end_re = ENVIRON["END_RE"] }
            !in_block && $0 ~ start_re {
                print ENVIRON["REPL"]
                in_block = 1
                replaced = 1
                next
            }
            in_block {
                if ($0 ~ end_re) { in_block = 0 }
                next
            }
            { print }
            END { if (!replaced) exit 3 }
        ' "$file" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if [[ -n "$(tail -c 1 "$file" | tr -d '\n')" ]]; then
        perl -i -pe 'chomp if eof' "$tmp"
    fi
    mv "$tmp" "$file"
}

if [[ "$UPDATE" -eq 1 ]]; then
    [[ -f "$FILE" ]] || { echo "File not found: $FILE" >&2; exit 1; }
    replace_block "$FILE" 'var MATCHES = \[' '^  \];' "$MATCHES_BLOCK" \
        || { echo "MATCHES block not found in $FILE" >&2; exit 1; }
    replace_block "$FILE" 'var STREAM_PATHS = \{' '^  \};' "$STREAM_PATHS_BLOCK" \
        || { echo "STREAM_PATHS block not found in $FILE" >&2; exit 1; }
    echo "Updated $FILE" >&2
else
    printf '%s\n' "$COMBINED_BLOCK"
fi
