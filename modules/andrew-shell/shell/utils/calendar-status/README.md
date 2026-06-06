# calendar-status

Emits upcoming calendar events as JSON lines by reading Thunderbird's local
CalDAV cache directly. Built for the andrew-shell status bar widget
(`config/blocks/Calendar.qml` via `config/singletons/CalendarStatus.qml`), but
it is a standalone binary with no IPC dependency on Thunderbird itself.

## What it does

On each tick (every 60s, or once with `--once`) it:

1. **Discovers the Thunderbird profile** (`src/profile.rs`)
   - Reads `~/.thunderbird/profiles.ini` and resolves the default profile:
     the `Default=` key of an `[Install*]` section is preferred (how modern
     Thunderbird marks the active profile), falling back to the `[Profile*]`
     section carrying `Default=1`.
   - Parses `prefs.js` in that profile with regexes to extract:
     - `calendar.registry.<uuid>.name` → cal_id → display-name map. This is
       also the source of truth for which calendars exist; cached events
       whose cal_id is no longer registered are dropped as stale.
     - `mail.identity.*.useremail` → the user's own email addresses, used
       for declined-event detection.

2. **Opens the calendar cache** (`src/main.rs`)
   - The database is `<profile>/calendar-data/cache.sqlite`, where
     Thunderbird caches CalDAV calendar items.
   - First tries a direct read-only connection. This works while Thunderbird
     is closed; while it is running, Thunderbird holds an exclusive lock on
     the database, so the connection opens but every query fails with
     `SQLITE_BUSY`.
   - On any error it falls back to copying `cache.sqlite` (plus its `-wal`
     file if present) to a fixed path under the temp dir and opening the copy
     read-write — write access is required so SQLite can perform WAL recovery
     on the copied database. The copy path is reused every tick, so no temp
     files accumulate. The `-shm` file is never copied (SQLite rebuilds it
     during WAL recovery) and any stale one is removed.

3. **Queries upcoming events** (`src/events.rs`)
   - Loads all rows from `cal_events`, plus `cal_recurrence`,
     `cal_attendees`, and `cal_properties` as needed.
   - Filters out: all-day events (flag bit `8`), `CANCELLED` events, events
     in calendars matched by `--exclude-calendar` (case-insensitive substring
     on the display name), events in unregistered calendars, and events the
     user has declined (an `ATTENDEE` row with `PARTSTAT=DECLINED` and
     `mailto:` matching one of the identity emails; rows with a NULL
     `recurrence_id` apply to the whole series, otherwise only to that
     occurrence).
   - Expands recurring masters with the `rrule` crate: the stored
     `RRULE`/`EXDATE`/`RDATE` lines are combined with a synthesized `DTSTART`
     in the master's original timezone so weekly/daily rules expand with
     correct local-time (DST-aware) semantics. Occurrences overridden by an
     exception row (same `cal_id`+`id` with a `recurrence_id`) are skipped
     during expansion; the exception row is judged separately by its own
     start time. Unparseable rules drop the series rather than crashing.
   - Resolves a meeting URL per event from `cal_properties`, preferring
     occurrence-specific rows over series rows, with key priority
     `X-GOOGLE-CONFERENCE` > `X-MICROSOFT-SKYPETEAMSMEETINGURL` > `URL` >
     `LOCATION` > `DESCRIPTION`. The first three are used verbatim when they
     look like http(s) URLs; for the last two the first http(s) substring is
     extracted from the free text.
   - Keeps events starting within `[now, now + horizon)` (default 24h),
     sorted by start time.

4. **Emits one JSON object per line** on stdout:

   ```json
   {"events":[{"title":"Standup","start":1780003600,"end":1780007200,"calendar":"Personal","url":"https://meet.google.com/..."}]}
   ```

   `start`/`end` are epoch seconds; `url` is omitted when none was found.

### Failure handling

Transient read failures (a torn copy while Thunderbird is mid-write, a brief
lock state the fallback can't get around) re-emit the last good event list so
the consuming widget doesn't flicker out for a tick. Only after 5 consecutive
failed polls — data genuinely unavailable, e.g. no Thunderbird profile at
all — does it emit an empty list. It keeps polling forever either way, so the
widget recovers on its own.

## CLI

```
calendar-status [--once] [--exclude-calendar <substr>]... [--horizon-hours <n>]
```

- `--once` — print current events and exit instead of polling.
- `--exclude-calendar` — skip calendars whose name contains this substring
  (case-insensitive, repeatable).
- `--horizon-hours` — how many hours ahead to look (default 24).

## Assumptions

These are deliberate simplifications, scoped to the system this repo builds:

- **Linux, default Thunderbird location.** The profile root is hardcoded to
  `~/.thunderbird`. No support for `XDG_DATA_HOME` layouts, Flatpak/Snap
  (`~/.var/app/...`), macOS, or Windows.
- **A single default profile exists** and is marked in `profiles.ini` via an
  `[Install*]` section or `Default=1`. Profile paths are assumed relative to
  `~/.thunderbird` (`IsRelative` is not consulted).
- **Thunderbird's internal schema is stable enough.** The `cache.sqlite`
  tables (`cal_events`, `cal_recurrence`, `cal_attendees`, `cal_properties`),
  the all-day flag bit (`CAL_ITEM_FLAG_EVENT_ALLDAY = 8`), PRTime
  (microseconds-since-epoch) timestamps, and the `prefs.js` line format are
  undocumented internals and could change across Thunderbird versions.
- **Only CalDAV-cached calendars are seen.** Local (storage) calendars live
  in `local.sqlite`, which is not read.
- **`/tmp` is per-machine and single-user** (NixOS with tmpfs on `/tmp`), so
  the fixed fallback-copy filename `calendar-status-cache.sqlite` is safe —
  no per-user namespacing, no `O_EXCL`, and the copy briefly exposes calendar
  data at a world-readable default path on multi-user systems.
- **The copy fallback is best-effort, not transactional.** The db and WAL are
  copied non-atomically while Thunderbird may be writing, so a torn copy is
  possible; the stale-tick logic above papers over that rather than
  preventing it.
- **Occurrence starts are whole seconds.** Exception matching compares
  rrule-generated occurrence starts (second precision) against PRTime
  `recurrence_id` values, which holds because Thunderbird stores these as
  whole seconds in practice.
- **Recurrence expansion is bounded** at 200 occurrences per series within
  the window — far above anything a real horizon produces, but a pathological
  rule (e.g. minutely) would be truncated silently.
- **Identity emails sync with calendar attendance.** Declined-event detection
  only works when the declining attendee's email matches one of the
  `mail.identity.*.useremail` addresses in `prefs.js`.
