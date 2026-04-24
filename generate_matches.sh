#!/usr/bin/env bash
# Fetch the Modular11 public schedule HTML and emit the MATCHES array
# used by schedule.html.
#
# Usage:
#   ./generate_matches.sh                  # print MATCHES JS to stdout
#   ./generate_matches.sh --update         # replace MATCHES block in schedule.html
#   ./generate_matches.sh --url '<url>'    # use a different Modular11 endpoint
#   ./generate_matches.sh --file <path>    # target a specific schedule.html
set -euo pipefail

DEFAULT_URL='https://www.modular11.com/public_schedule/league/get_matches?open_page=0&academy=0&tournament=24&gender=0&age=0&brackets=&groups=&group=&match_number=0&status=scheduled&match_type=2&schedule=0&team=0&teamPlayer=8105&location=0&as_referee=0&report_status=0&start_date=2026-04-21+00%3A00%3A00&end_date=2026-12-31+23%3A59%3A59'

URL="$DEFAULT_URL"
UPDATE=0
FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)    URL="$2"; shift 2 ;;
        --update) UPDATE=1; shift ;;
        --file)   FILE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${FILE:=$SCRIPT_DIR/schedule.html}"

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

    n++
    sort_keys[n] = sprintf("%04d-%02d-%02d-%02d-%02d", year, month_idx, dy, hour, minute)
    js_records[n] = \
        "    {\n" \
        "      id: " jsstr(id) ",\n" \
        "      date: new Date(" year ", " month_idx ", " dy ", " hour ", " minute "),\n" \
        "      home: " team_js(t_names[1], t_ids[1], home_crest) ",\n" \
        "      away: " team_js(t_names[2], t_ids[2], away_crest) ",\n" \
        "      location: " jsstr(location) ",\n" \
        "      mapsUrl: " jsstr(maps_url) "\n" \
        "    }"
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
}
AWK_EOF

BLOCK="$(curl -fsS --compressed "$URL" -H 'X-Requested-With: XMLHttpRequest' | awk "$AWK_PROG")"

if [[ -z "$BLOCK" ]]; then
    echo "No matches parsed from response." >&2
    exit 1
fi

if [[ "$UPDATE" -eq 1 ]]; then
    [[ -f "$FILE" ]] || { echo "File not found: $FILE" >&2; exit 1; }
    TMP="$(mktemp)"
    if ! BLOCK_CONTENT="$BLOCK" awk '
            BEGIN { replaced = 0; in_block = 0 }
            !in_block && /var MATCHES = \[/ {
                print ENVIRON["BLOCK_CONTENT"]
                in_block = 1
                replaced = 1
                next
            }
            in_block {
                if ($0 ~ /^  \];/) { in_block = 0 }
                next
            }
            { print }
            END { if (!replaced) exit 3 }
        ' "$FILE" > "$TMP"; then
        echo "MATCHES block not found in $FILE" >&2
        rm -f "$TMP"
        exit 1
    fi
    # Preserve original's trailing-newline state.
    if [[ -n "$(tail -c 1 "$FILE" | tr -d '\n')" ]]; then
        perl -i -pe 'chomp if eof' "$TMP"
    fi
    mv "$TMP" "$FILE"
    echo "Updated $FILE" >&2
else
    printf '%s\n' "$BLOCK"
fi
