# appfc-schedule

Embeddable HTML/JS/CSS schedule widget for Appalachian FC, plus a helper
script that refreshes the match list from Modular11.

## Files

- `schedule.html` — the widget. Drop-in HTML with inline CSS/JS. Matches are
  hardcoded in a `var MATCHES = [...]` array near the top of the `<script>`
  block.
- `generate_matches.sh` — scrapes the Modular11 public schedule endpoint and
  emits a `MATCHES` array in the exact shape `schedule.html` expects. Can
  either print the block or rewrite `schedule.html` in place.

## Refreshing the schedule

The widget renders from a static `MATCHES` array, so updating the schedule
means regenerating that array from the Modular11 source of truth.

### Option 1: update `schedule.html` in place

```sh
./generate_matches.sh --update
```

This fetches the default Modular11 URL (filtered to Appalachian FC,
`teamPlayer=8105`, scheduled matches, 2026-04-21 → 2026-12-31), parses the
HTML response, and replaces the `var MATCHES = [ ... ];` block in
`schedule.html`. The `APPFC_CREST` constant is preserved — home/away entries
for team id `8105` are emitted as `crest: APPFC_CREST` rather than an inline
URL.

### Option 2: print the block for manual paste

```sh
./generate_matches.sh
```

Prints the generated `var MATCHES = [ ... ];` block to stdout so you can
inspect or copy it into `schedule.html` yourself.

### Flags

- `--update` — rewrite `schedule.html` in place instead of printing to stdout.
- `--url '<url>'` — use a different Modular11 endpoint (e.g. next season,
  different team filter, wider date range).
- `--file <path>` — target a specific `schedule.html` when updating. Defaults
  to the one next to the script.

### Example: pull next season

```sh
./generate_matches.sh --update --url 'https://www.modular11.com/public_schedule/league/get_matches?...&teamPlayer=8105&start_date=2027-01-01+00%3A00%3A00&end_date=2027-12-31+23%3A59%3A59'
```

## How it works

Modular11's `get_matches` endpoint returns HTML (not JSON) — a table of match
rows. `generate_matches.sh` uses `curl` + `awk` to split the response on the
`table-content-row-uls` row marker and pull out each match's:

- match id (from the `uid-mobile-style` cell)
- kickoff date/time (the `MM/DD/YY HH:MMam/pm` literal)
- Google Maps link (first `maps/search` href in the row)
- venue name (the portion after `" - "` in the location `data-title`)
- home and away team id, display name, and crest URL (from
  `/league-schedule/teams/<id>` links and their `.club-photo`
  `background-image`)

Matches are sorted by kickoff and emitted as a JS array literal using
`new Date(YYYY, monthIdx, D, H, M)` so the widget can render them without a
date-parsing step.

## Requirements

- `bash`, `curl`, `awk` (BSD awk on macOS is fine)
- `perl` (only used when `--update` is run against a file with no trailing
  newline, to preserve that)
