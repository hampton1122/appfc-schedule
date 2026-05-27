# appfc-schedule

Embeddable schedule widget for Appalachian FC, hosted on GitHub Pages and
embedded in [appalachianfc.com](https://appalachianfc.com) (Square Online).

## How it's wired

| File | Purpose |
| --- | --- |
| `schedule.html` | The embed snippet. Paste into Square. Loads CSS/JS from GitHub Pages. |
| `schedule.css` | Widget styles. Served from `https://hampton1122.github.io/appfc-schedule/schedule.css`. |
| `schedule.js`  | Renderer. Fetches `matches.json` from the same path it was loaded from. |
| `matches.json` | Schedule data: `{ matches: [...], streams: {...} }`. Regenerated from Modular11 + SportsEngine Play. |
| `generate_matches_json.sh` | Refreshes `matches.json`. |
| `generate_matches.sh` | Original generator that rewrote inline `MATCHES`/`STREAM_PATHS` blocks in `schedule.html`. **Obsolete** now that the data lives in `matches.json`; kept for reference. |
| `.github/workflows/refresh-matches.yml` | Cron job that runs `generate_matches_json.sh --update` every 30 min and commits the result. |

GitHub Pages must be enabled on the repo (Settings → Pages → Deploy from
branch `master` / root). Pages auto-redeploys on every push.

## Embedding

Paste the contents of `schedule.html` into a Square Online code block. The
embed is just a `<link>`, a root `<div>`, and a `<script>` tag — the actual
markup is rendered client-side by `schedule.js`.

If you serve from a different host (custom domain, alternate fork), update
the two URLs in `schedule.html` accordingly.

## Refreshing scores and the schedule

You normally don't need to do anything — the GitHub Action runs every 30 min
and commits any changes to `matches.json`. The widget picks up new data
within ~1 minute of the push (`schedule.js` cache-busts the fetch each
minute).

Manual refresh:

```sh
./generate_matches_json.sh --update      # write matches.json
./generate_matches_json.sh               # print to stdout (preview)
./generate_matches_json.sh --no-streams  # skip SportsEngine fetch
./generate_matches_json.sh --url '<url>' # alternate Modular11 endpoint
./generate_matches_json.sh --file <path> # alternate output file
```

The script merges new SportsEngine livestream URLs with the existing
`streams` block in `matches.json`, so past games keep their stream links
even after the SE API drops them from "upcoming" results.

## Data shape

`matches.json`:

```json
{
  "matches": [
    {
      "id": "116260",
      "date": "2026-05-13T19:00:00",
      "home": { "name": "Appalachian FC", "id": "8105" },
      "away": { "name": "Asheville City SC", "id": "2016", "crest": "https://..." },
      "location": "Ted Mackorell Soccer Complex",
      "mapsUrl": "https://www.google.com/maps/search/...",
      "detailsUrl": "https://www.modular11.com/match_details/116260/2",
      "score": { "home": 0, "away": 0 }
    }
  ],
  "streams": {
    "116260": "/USL/.../game/...?video_id=..."
  }
}
```

Notes:
- Dates are ISO local strings with no timezone (`new Date(str)` parses as
  local time in modern browsers). Match times are stored as local kickoff
  time at the venue.
- `home.crest` is omitted for Appalachian FC (id `8105`); `schedule.js`
  fills in the canonical crest URL.
- `score` is `null` for scheduled matches, `{home, away}` once final.

## How the generator works

Modular11's `get_matches` endpoint returns HTML — a table of match rows.
`generate_matches_json.sh` uses `curl` + `awk` to extract each match's id,
kickoff date/time, venue, Google Maps link, team ids/names/crests, and
final score. Python then assembles the JSON and merges in the
SportsEngine Play livestream catalog (a separate GraphQL request) by date
+ team-name matching.

## Requirements

- `bash`, `curl`, `awk` (BSD awk on macOS is fine)
- `python3` (3.6+ for f-strings)
