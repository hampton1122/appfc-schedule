#!/usr/bin/env bash
# Fetch Modular11 schedule + SportsEngine Play livestreams, emit matches.json
# in the shape schedule.js expects:
#   { "matches": [ {id,date,home,away,location,mapsUrl,detailsUrl,score}, ... ],
#     "streams": { "<matchId>": "<sportsenginepath>", ... } }
#
# Usage:
#   ./generate_matches_json.sh                # print JSON to stdout
#   ./generate_matches_json.sh --update       # write matches.json next to script
#   ./generate_matches_json.sh --url '<url>'  # alternate Modular11 endpoint
#   ./generate_matches_json.sh --file <path>  # alternate output file
#   ./generate_matches_json.sh --no-streams   # skip SE fetch (matches only)
set -euo pipefail

DEFAULT_URL='https://www.modular11.com/public_schedule/league/get_matches?open_page=0&academy=0&tournament=24&gender=0&age=0&brackets=&groups=&group=&match_number=0&status=all&match_type=2&schedule=0&team=0&teamPlayer=8105&location=0&as_referee=0&report_status=0&start_date=2026-04-21+00%3A00%3A00&end_date=2026-12-31+23%3A59%3A59'

SE_GRAPHQL_URL='https://api.sportsengineplay.com/graphql'
# Appalachian FC's own SportsEngine Play channel (not the league-wide channel) -
# this is the channel the public streams list page itself queries against:
# https://sportsengineplay.com/USL/Appalachian-FC-682886/Appalachian-FC?viewType=list
SE_CHANNEL_ID='69b05a33cc6b669785b21fe3'

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
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${FILE:=$SCRIPT_DIR/matches.json}"

# Parse Modular11 HTML into a TSV with one match per line. Fields are tab-
# separated and may be empty. Python then builds the final JSON so we don't
# have to do JSON escaping inside awk.
#
# Columns:
#   id, year, month_idx, day, hour, minute,
#   home_id, home_name, home_crest,
#   away_id, away_name, away_crest,
#   location, maps_url, details_url,
#   home_score, away_score
IFS= read -r -d '' AWK_PROG <<'AWK_EOF' || true
BEGIN {
    RS = "<div class=\"row table-content-row table-content-row-uls"
    FS = "\n"
    OFS = "\t"
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

    print id, year, month_idx, dy, hour, minute, \
          t_ids[1], t_names[1], home_crest, \
          t_ids[2], t_names[2], away_crest, \
          location, maps_url, details_url, \
          home_score, away_score
}
AWK_EOF

MATCH_TSV="$(curl -fsS --compressed "$URL" -H 'X-Requested-With: XMLHttpRequest' | awk "$AWK_PROG")"

if [[ -z "$MATCH_TSV" ]]; then
    echo "No matches parsed from response." >&2
    exit 1
fi

if [[ "$FETCH_STREAMS" -eq 1 ]]; then
    # Send the full query text (as the site itself does) rather than a
    # persisted-query hash, which goes stale server-side without warning.
    SE_QUERY=$'query GetLiveStreams($page: Int, $limit: Int = 9, $sort: JSON, $channelId: ID, $isLiveOrUpcoming: Boolean, $gender: String, $level: String, $sublevel: String, $sport: String, $hidePrivateAndUnfollowed: Boolean, $onlyPublic: Boolean, $categories: [ID!], $startDate: String, $endDate: String, $teamId: ID, $participantId: ID, $showNonScheduled: Boolean = false, $hideCourtStreams: Boolean = true, $showOnlyCourtStreams: Boolean = false, $subVenue: String, $venue: String, $hidePins: Boolean = false) {\n  liveStreams(\n    page: $page\n    limit: $limit\n    sort: $sort\n    channelId: $channelId\n    isLiveOrUpcoming: $isLiveOrUpcoming\n    teamId: $teamId\n    teamGender: $gender\n    teamLevel: $level\n    teamSublevel: $sublevel\n    teamSport: $sport\n    hidePrivateAndUnfollowed: $hidePrivateAndUnfollowed\n    onlyPublic: $onlyPublic\n    categories: $categories\n    startDateGte: $startDate\n    startDateLte: $endDate\n    participantId: $participantId\n    showNonScheduled: $showNonScheduled\n    hideCourtStreams: $hideCourtStreams\n    showOnlyCourtStreams: $showOnlyCourtStreams\n    subVenue: $subVenue\n    venue: $venue\n    hidePins: $hidePins\n  ) {\n    totalRecords\n    data {\n      id\n      pageUrl\n      liveStartDateTime\n      eventName\n      homeTeamChannel { team { name } }\n      awayTeamChannel { team { name } }\n      __typename\n    }\n    __typename\n  }\n}\n'
    SE_REQUEST=$(python3 -c '
import json, sys
print(json.dumps({
    "operationName": "GetLiveStreams",
    "variables": {
        "limit": 100, "showNonScheduled": False, "hideCourtStreams": True,
        "showOnlyCourtStreams": False, "hidePins": False, "page": 1,
        "sort": {"liveStartDateTime": 1, "weight": 1},
        "channelId": sys.argv[1], "teamId": None, "participantId": None,
        "gender": "", "level": "", "sublevel": "", "sport": "",
        "isLiveOrUpcoming": True, "venue": "", "subVenue": None,
    },
    "query": sys.argv[2],
}))
' "$SE_CHANNEL_ID" "$SE_QUERY")
    SE_JSON=$(curl -fsS --compressed -X POST "$SE_GRAPHQL_URL" \
        -H 'Content-Type: application/json' \
        --data "$SE_REQUEST")
else
    SE_JSON='{"data":{"liveStreams":{"data":[]}}}'
fi

JSON_OUT=$(
    MATCH_TSV="$MATCH_TSV" SE_JSON="$SE_JSON" EXISTING_FILE="$FILE" \
    python3 - <<'PYEOF'
import json, os, re, datetime

APPFC_ID = "8105"

def parse_matches(tsv):
    rows = []
    for line in tsv.splitlines():
        if not line.strip():
            continue
        f = line.split("\t")
        if len(f) < 17:
            continue
        (mid, year, mon_idx, dy, hh, mm,
         h_id, h_name, h_crest,
         a_id, a_name, a_crest,
         loc, maps_url, details_url,
         h_score, a_score) = f

        def team(tid, name, crest):
            t = {"name": name, "id": tid}
            if crest and tid != APPFC_ID:
                t["crest"] = crest
            return t

        score = None
        if h_score and a_score:
            score = {"home": int(h_score), "away": int(a_score)}

        rows.append({
            "id": mid,
            "_sort": (int(year), int(mon_idx), int(dy), int(hh), int(mm)),
            "_date_key": f"{int(year):04d}-{int(mon_idx)+1:02d}-{int(dy):02d}",
            "obj": {
                "id": mid,
                "date": f"{int(year):04d}-{int(mon_idx)+1:02d}-{int(dy):02d}T{int(hh):02d}:{int(mm):02d}:00",
                "home": team(h_id, h_name, h_crest),
                "away": team(a_id, a_name, a_crest),
                "location": loc,
                "mapsUrl": maps_url,
                "detailsUrl": details_url,
                "score": score,
            },
            "home_name": h_name,
            "away_name": a_name,
        })
    rows.sort(key=lambda r: r["_sort"])
    return rows

def load_existing_streams(path):
    if not (path and os.path.exists(path)):
        return {}
    try:
        with open(path) as fh:
            return (json.load(fh).get("streams") or {})
    except Exception:
        return {}

def norm(s):
    return re.sub(r"\s+", " ", (s or "").strip().lower())

def build_streams(rows, se_json, existing):
    streams = (((se_json.get("data") or {}).get("liveStreams") or {}).get("data") or [])
    by_date = {}
    for s in streams:
        page_url = s.get("pageUrl")
        ts = s.get("liveStartDateTime")
        if not page_url or ts is None:
            continue
        dt = datetime.datetime.fromtimestamp(int(ts) / 1000)
        key = dt.strftime("%Y-%m-%d")
        h = norm((((s.get("homeTeamChannel") or {}).get("team") or {}).get("name")))
        a = norm((((s.get("awayTeamChannel") or {}).get("team") or {}).get("name")))
        by_date.setdefault(key, []).append((page_url, h, a))

    out = {}
    for r in rows:
        candidates = by_date.get(r["_date_key"], [])
        chosen = None
        if len(candidates) == 1:
            chosen = candidates[0][0]
        elif len(candidates) > 1:
            h = norm(r["home_name"])
            for url, sh, sa in candidates:
                if h and sh and h.split()[0] == sh.split()[0]:
                    chosen = url
                    break
            if not chosen:
                chosen = candidates[0][0]
        if not chosen:
            chosen = existing.get(r["id"])
        if chosen:
            out[r["id"]] = chosen
    return out

rows = parse_matches(os.environ["MATCH_TSV"])
se_json = json.loads(os.environ["SE_JSON"])
existing = load_existing_streams(os.environ.get("EXISTING_FILE", ""))
streams = build_streams(rows, se_json, existing)

print(json.dumps({
    "matches": [r["obj"] for r in rows],
    "streams": streams,
}, indent=2))
PYEOF
)

if [[ "$UPDATE" -eq 1 ]]; then
    printf '%s\n' "$JSON_OUT" > "$FILE"
    echo "Wrote $FILE" >&2
else
    printf '%s\n' "$JSON_OUT"
fi
