use std::collections::HashMap;

use anyhow::Result;
use rrule::RRuleSet;
use rusqlite::Connection;
use serde::Serialize;

/// Thunderbird's CAL_ITEM_FLAG_EVENT_ALLDAY
const ALLDAY_FLAG: i64 = 8;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Event {
    pub title: String,
    /// epoch seconds
    pub start: i64,
    /// epoch seconds
    pub end: i64,
    pub calendar: String,
    /// Meeting/conference URL, if one was found in cal_properties.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

struct RawEvent {
    cal_id: String,
    id: String,
    title: Option<String>,
    flags: i64,
    ical_status: Option<String>,
    /// PRTime: microseconds since epoch, UTC
    event_start: i64,
    event_end: i64,
    event_start_tz: Option<String>,
    /// Set on recurrence-exception rows: the original occurrence's start (PRTime)
    recurrence_id: Option<i64>,
}

pub fn upcoming_events(
    conn: &Connection,
    calendar_names: &HashMap<String, String>,
    identity_emails: &[String],
    exclude_calendars: &[String],
    now_micros: i64,
    horizon_micros: i64,
) -> Result<Vec<Event>> {
    let window_end = now_micros + horizon_micros;
    let rows = load_events(conn)?;
    let recurrences = load_recurrences(conn)?;

    // recurrence_id values of exception rows, keyed by series, so master
    // expansion can skip occurrences that have been overridden
    let mut exception_ids: HashMap<(String, String), Vec<i64>> = HashMap::new();
    for ev in rows.iter().filter(|e| e.recurrence_id.is_some()) {
        exception_ids
            .entry((ev.cal_id.clone(), ev.id.clone()))
            .or_default()
            .push(ev.recurrence_id.unwrap());
    }

    let mut events = Vec::new();

    for ev in &rows {
        let Some(calendar) = calendar_names.get(&ev.cal_id) else {
            // Calendar no longer registered in prefs.js; stale cache data
            continue;
        };
        let calendar_lower = calendar.to_lowercase();
        if exclude_calendars
            .iter()
            .any(|x| calendar_lower.contains(&x.to_lowercase()))
        {
            continue;
        }
        if ev.flags & ALLDAY_FLAG != 0 {
            continue;
        }
        if ev.ical_status.as_deref() == Some("CANCELLED") {
            continue;
        }

        let key = (ev.cal_id.clone(), ev.id.clone());
        let rules = recurrences.get(&key);

        if ev.recurrence_id.is_none() && rules.is_some() {
            // Recurring master: expand into the window, skipping occurrences
            // that an exception row overrides (the exception row is judged
            // separately by its own start time below).
            let skip = exception_ids.get(&key);
            for (start, end) in expand_master(ev, rules.unwrap(), now_micros, window_end) {
                // PRTime occurrence starts are whole seconds in practice, so this
                // second-precision comparison against exception ids is safe.
                if skip.is_some_and(|ids| ids.contains(&start)) {
                    continue;
                }
                if is_declined(conn, &ev.cal_id, &ev.id, Some(start), identity_emails)? {
                    continue;
                }
                let url = meeting_url(conn, &ev.cal_id, &ev.id, Some(start))?;
                events.push(to_event(ev, calendar, start, end, url));
            }
        } else {
            // Plain event or exception row: judge by its own start time
            if ev.event_start < now_micros || ev.event_start >= window_end {
                continue;
            }
            if is_declined(conn, &ev.cal_id, &ev.id, ev.recurrence_id, identity_emails)? {
                continue;
            }
            let url = meeting_url(conn, &ev.cal_id, &ev.id, ev.recurrence_id)?;
            events.push(to_event(ev, calendar, ev.event_start, ev.event_end, url));
        }
    }

    events.sort_by_key(|e| e.start);
    Ok(events)
}

/// True if one of the user's identities has PARTSTAT=DECLINED on this event.
/// Attendee rows with a NULL recurrence_id apply to the whole series; rows
/// with a recurrence_id only apply to that occurrence.
fn is_declined(
    conn: &Connection,
    cal_id: &str,
    item_id: &str,
    recurrence_id: Option<i64>,
    identity_emails: &[String],
) -> Result<bool> {
    let mut stmt = conn.prepare_cached(
        "SELECT recurrence_id, icalString FROM cal_attendees
         WHERE cal_id = ?1 AND item_id = ?2",
    )?;
    let rows = stmt
        .query_map((cal_id, item_id), |r| {
            Ok((r.get::<_, Option<i64>>(0)?, r.get::<_, String>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    for (rid, ical) in rows {
        if rid.is_some() && rid != recurrence_id {
            continue;
        }
        let upper = ical.to_uppercase();
        if !upper.starts_with("ATTENDEE") || !upper.contains("PARTSTAT=DECLINED") {
            continue;
        }
        if identity_emails
            .iter()
            .any(|email| upper.contains(&format!("MAILTO:{}", email.to_uppercase())))
        {
            return Ok(true);
        }
    }
    Ok(false)
}

fn to_event(
    ev: &RawEvent,
    calendar: &str,
    start_micros: i64,
    end_micros: i64,
    url: Option<String>,
) -> Event {
    Event {
        title: ev.title.clone().unwrap_or_else(|| "(untitled)".to_string()),
        start: start_micros / 1_000_000,
        end: end_micros / 1_000_000,
        calendar: calendar.to_string(),
        url,
    }
}

/// Find a meeting/conference URL for an event from cal_properties.
///
/// Like cal_attendees, property rows with a NULL recurrence_id apply to the
/// whole series; rows with a recurrence_id apply only to that occurrence. We
/// prefer occurrence-specific rows over series rows and ignore rows for other
/// occurrences.
///
/// Priority: X-GOOGLE-CONFERENCE > X-MICROSOFT-SKYPETEAMSMEETINGURL > URL >
/// LOCATION > DESCRIPTION. For the conference/URL keys the value is used
/// verbatim when it looks like an http(s) URL; for LOCATION/DESCRIPTION the
/// first http(s) substring is extracted.
fn meeting_url(
    conn: &Connection,
    cal_id: &str,
    item_id: &str,
    recurrence_id: Option<i64>,
) -> Result<Option<String>> {
    let mut stmt = conn.prepare_cached(
        "SELECT key, value, recurrence_id FROM cal_properties
         WHERE cal_id = ?1 AND item_id = ?2
           AND key IN ('X-GOOGLE-CONFERENCE','X-MICROSOFT-SKYPETEAMSMEETINGURL',
                       'URL','LOCATION','DESCRIPTION')",
    )?;
    let rows = stmt
        .query_map((cal_id, item_id), |r| {
            // value is declared BLOB; read defensively as bytes then lossy-decode.
            let key = r.get::<_, String>(0)?;
            // `value` is declared BLOB but Thunderbird stores URLs as TEXT, so
            // read whatever the column actually holds and coerce to a string.
            let value = match r.get::<_, rusqlite::types::Value>(1)? {
                rusqlite::types::Value::Text(s) => s,
                rusqlite::types::Value::Blob(bytes) => {
                    String::from_utf8_lossy(&bytes).into_owned()
                }
                _ => String::new(),
            };
            let rid = r.get::<_, Option<i64>>(2)?;
            Ok((key, value, rid))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    // For each key, keep the best matching row's value, preferring an
    // occurrence-specific row over a series (NULL) row.
    let mut best: HashMap<String, (bool, String)> = HashMap::new();
    for (key, value, rid) in rows {
        if rid.is_some() && rid != recurrence_id {
            continue;
        }
        let occurrence_specific = rid.is_some();
        match best.get(&key) {
            // Replace only if the existing entry is a series row and this is
            // occurrence-specific.
            Some((existing_specific, _)) if *existing_specific || !occurrence_specific => {}
            _ => {
                best.insert(key, (occurrence_specific, value));
            }
        }
    }

    for key in [
        "X-GOOGLE-CONFERENCE",
        "X-MICROSOFT-SKYPETEAMSMEETINGURL",
        "URL",
    ] {
        if let Some((_, value)) = best.get(key) {
            let trimmed = value.trim();
            if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
                return Ok(Some(trimmed.to_string()));
            }
        }
    }

    for key in ["LOCATION", "DESCRIPTION"] {
        if let Some((_, value)) = best.get(key) {
            if let Some(url) = extract_url(value) {
                return Ok(Some(url));
            }
        }
    }

    Ok(None)
}

/// Extract the first http(s):// URL from free text. Terminates the URL at
/// whitespace, `"`, `>`, or end of string, then trims trailing `)`, `,`, `.`.
fn extract_url(text: &str) -> Option<String> {
    let start = text.find("http://").or_else(|| text.find("https://"))?;
    let rest = &text[start..];
    let end = rest
        .find(|c: char| c.is_whitespace() || c == '"' || c == '>')
        .unwrap_or(rest.len());
    let url = rest[..end].trim_end_matches([')', ',', '.']);
    if url.is_empty() {
        None
    } else {
        Some(url.to_string())
    }
}

/// Expand a recurring master's occurrences within [window_start, window_end),
/// returning (start, end) pairs in PRTime microseconds.
fn expand_master(
    master: &RawEvent,
    rule_lines: &[String],
    window_start: i64,
    window_end: i64,
) -> Vec<(i64, i64)> {
    let mut ical = format_dtstart(master.event_start, master.event_start_tz.as_deref());
    for line in rule_lines {
        let line = line.trim();
        if !line.is_empty() {
            ical.push('\n');
            ical.push_str(line);
        }
    }

    let Ok(set) = ical.parse::<RRuleSet>() else {
        // Unparseable rule: better to show nothing for this series than to crash
        return Vec::new();
    };

    let after = chrono::DateTime::from_timestamp_micros(window_start)
        .unwrap()
        .with_timezone(&rrule::Tz::UTC);
    // rrule's `before` bound is inclusive; subtract 1 microsecond so the
    // effective window is [window_start, window_end).
    let before = chrono::DateTime::from_timestamp_micros(window_end - 1)
        .unwrap()
        .with_timezone(&rrule::Tz::UTC);

    let duration = master.event_end - master.event_start;
    set.after(after)
        .before(before)
        .all(200)
        .dates
        .into_iter()
        .map(|d| {
            let start = d.timestamp() * 1_000_000;
            (start, start + duration)
        })
        .collect()
}

/// Format the master's start as an iCal DTSTART line in its original timezone,
/// so weekly/daily rules expand with correct local-time (DST-aware) semantics.
fn format_dtstart(start_micros: i64, tz_name: Option<&str>) -> String {
    let utc = chrono::DateTime::from_timestamp_micros(start_micros).unwrap();
    match tz_name {
        Some(name) if name != "UTC" && name != "floating" => {
            if let Ok(tz) = name.parse::<chrono_tz::Tz>() {
                let local = utc.with_timezone(&tz);
                return format!("DTSTART;TZID={}:{}", name, local.format("%Y%m%dT%H%M%S"));
            }
            format!("DTSTART:{}", utc.format("%Y%m%dT%H%M%SZ"))
        }
        _ => format!("DTSTART:{}", utc.format("%Y%m%dT%H%M%SZ")),
    }
}

fn load_recurrences(conn: &Connection) -> Result<HashMap<(String, String), Vec<String>>> {
    let mut stmt = conn.prepare("SELECT cal_id, item_id, icalString FROM cal_recurrence")?;
    let mut map: HashMap<(String, String), Vec<String>> = HashMap::new();
    let rows = stmt.query_map([], |r| {
        Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, String>(2)?,
        ))
    })?;
    for row in rows {
        let (cal_id, item_id, ical) = row?;
        map.entry((cal_id, item_id)).or_default().push(ical);
    }
    Ok(map)
}

fn load_events(conn: &Connection) -> Result<Vec<RawEvent>> {
    let mut stmt = conn.prepare(
        "SELECT cal_id, id, title, flags, ical_status,
                event_start, event_end, event_start_tz, recurrence_id
         FROM cal_events",
    )?;
    let rows = stmt
        .query_map([], |r| {
            Ok(RawEvent {
                cal_id: r.get(0)?,
                id: r.get(1)?,
                title: r.get(2)?,
                flags: r.get::<_, Option<i64>>(3)?.unwrap_or(0),
                ical_status: r.get(4)?,
                event_start: r.get(5)?,
                event_end: r.get(6)?,
                event_start_tz: r.get(7)?,
                recurrence_id: r.get(8)?,
            })
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use std::collections::HashMap;

    /// 2026-06-08 ~02:26 UTC, in PRTime (microseconds)
    const NOW: i64 = 1_780_000_000_000_000;
    const HOUR: i64 = 3_600_000_000;
    const DAY: i64 = 24 * HOUR;
    const HORIZON: i64 = 24 * HOUR;

    fn fixture_conn() -> Connection {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "CREATE TABLE cal_events (
                cal_id TEXT, id TEXT, title TEXT, flags INTEGER, ical_status TEXT,
                event_start INTEGER, event_end INTEGER, event_start_tz TEXT,
                recurrence_id INTEGER);
             CREATE TABLE cal_recurrence (item_id TEXT, cal_id TEXT, icalString TEXT);
             CREATE TABLE cal_attendees (
                item_id TEXT, recurrence_id INTEGER, recurrence_id_tz TEXT,
                cal_id TEXT, icalString TEXT);
             CREATE TABLE cal_properties (
                item_id TEXT, key TEXT, value BLOB,
                recurrence_id INTEGER, recurrence_id_tz TEXT, cal_id TEXT);",
        )
        .unwrap();
        conn
    }

    fn insert_event(
        conn: &Connection,
        cal_id: &str,
        id: &str,
        title: &str,
        flags: i64,
        status: &str,
        start: i64,
        end: i64,
        recurrence_id: Option<i64>,
    ) {
        conn.execute(
            "INSERT INTO cal_events VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'UTC', ?8)",
            (cal_id, id, title, flags, status, start, end, recurrence_id),
        )
        .unwrap();
    }

    fn calendars() -> HashMap<String, String> {
        HashMap::from([
            ("cal1".to_string(), "Personal".to_string()),
            ("cal2".to_string(), "Holidays in Testland".to_string()),
        ])
    }

    fn query(conn: &Connection) -> Vec<Event> {
        upcoming_events(
            conn,
            &calendars(),
            &["me@example.com".to_string()],
            &["Holidays in".to_string()],
            NOW,
            HORIZON,
        )
        .unwrap()
    }

    #[test]
    fn includes_upcoming_plain_event() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Standup", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        let events = query(&conn);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].title, "Standup");
        assert_eq!(events[0].start, (NOW + HOUR) / 1_000_000);
        assert_eq!(events[0].end, (NOW + 2 * HOUR) / 1_000_000);
        assert_eq!(events[0].calendar, "Personal");
    }

    #[test]
    fn skips_events_outside_window() {
        let conn = fixture_conn();
        // already started
        insert_event(&conn, "cal1", "e1", "Past", 260, "CONFIRMED", NOW - HOUR, NOW + HOUR, None);
        // beyond horizon
        insert_event(&conn, "cal1", "e2", "Far", 260, "CONFIRMED", NOW + 2 * DAY, NOW + 2 * DAY + HOUR, None);
        assert_eq!(query(&conn).len(), 0);
    }

    #[test]
    fn skips_all_day_events() {
        let conn = fixture_conn();
        // flags 268 = 256 + 8 (all-day) + 4, as seen in real data
        insert_event(&conn, "cal1", "e1", "Birthday", 268, "CONFIRMED", NOW + HOUR, NOW + DAY, None);
        assert_eq!(query(&conn).len(), 0);
    }

    #[test]
    fn skips_cancelled_events() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Cancelled", 260, "CANCELLED", NOW + HOUR, NOW + 2 * HOUR, None);
        assert_eq!(query(&conn).len(), 0);
    }

    #[test]
    fn skips_excluded_calendars() {
        let conn = fixture_conn();
        insert_event(&conn, "cal2", "e1", "Some Holiday", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        assert_eq!(query(&conn).len(), 0);
    }

    #[test]
    fn skips_unknown_calendars() {
        let conn = fixture_conn();
        insert_event(&conn, "stale", "e1", "Orphan", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        assert_eq!(query(&conn).len(), 0);
    }

    #[test]
    fn sorts_by_start_time() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Later", 260, "CONFIRMED", NOW + 3 * HOUR, NOW + 4 * HOUR, None);
        insert_event(&conn, "cal1", "e2", "Sooner", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        let events = query(&conn);
        assert_eq!(events[0].title, "Sooner");
        assert_eq!(events[1].title, "Later");
    }

    fn insert_attendee(
        conn: &Connection,
        cal_id: &str,
        item_id: &str,
        recurrence_id: Option<i64>,
        ical: &str,
    ) {
        conn.execute(
            "INSERT INTO cal_attendees VALUES (?1, ?2, NULL, ?3, ?4)",
            (item_id, recurrence_id, cal_id, ical),
        )
        .unwrap();
    }

    #[test]
    fn skips_declined_events() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Declined mtg", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        insert_attendee(
            &conn, "cal1", "e1", None,
            "ATTENDEE;CN=me@example.com;PARTSTAT=DECLINED;ROLE=REQ-PARTICIPANT:mailto:me@example.com",
        );
        assert_eq!(query(&conn).len(), 0);
    }

    #[test]
    fn keeps_events_declined_only_by_others() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Mtg", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        insert_attendee(
            &conn, "cal1", "e1", None,
            "ATTENDEE;CN=other@example.com;PARTSTAT=DECLINED:mailto:other@example.com",
        );
        insert_attendee(
            &conn, "cal1", "e1", None,
            "ATTENDEE;CN=me@example.com;PARTSTAT=ACCEPTED:mailto:me@example.com",
        );
        assert_eq!(query(&conn).len(), 1);
    }

    #[test]
    fn keeps_events_with_no_attendees() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Solo", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        assert_eq!(query(&conn).len(), 1);
    }

    fn insert_recurrence(conn: &Connection, cal_id: &str, item_id: &str, ical: &str) {
        conn.execute(
            "INSERT INTO cal_recurrence VALUES (?1, ?2, ?3)",
            (item_id, cal_id, ical),
        )
        .unwrap();
    }

    #[test]
    fn expands_daily_rrule_into_window() {
        let conn = fixture_conn();
        // Daily event that started 30 days ago; next occurrence is NOW + 2h
        let master_start = NOW + 2 * HOUR - 30 * DAY;
        insert_event(&conn, "cal1", "rec1", "Daily sync", 276, "CONFIRMED", master_start, master_start + HOUR, None);
        insert_recurrence(&conn, "cal1", "rec1", "RRULE:FREQ=DAILY");
        let events = query(&conn);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].title, "Daily sync");
        assert_eq!(events[0].start, (NOW + 2 * HOUR) / 1_000_000);
        // duration preserved
        assert_eq!(events[0].end, (NOW + 3 * HOUR) / 1_000_000);
    }

    #[test]
    fn master_far_in_past_with_no_occurrence_in_window_yields_nothing() {
        let conn = fixture_conn();
        let master_start = NOW - 30 * DAY;
        insert_event(&conn, "cal1", "rec1", "Yearly", 276, "CONFIRMED", master_start, master_start + HOUR, None);
        insert_recurrence(&conn, "cal1", "rec1", "RRULE:FREQ=YEARLY");
        assert_eq!(query(&conn).len(), 0);
    }

    #[test]
    fn exception_row_overrides_generated_occurrence() {
        let conn = fixture_conn();
        let master_start = NOW + 2 * HOUR - 30 * DAY;
        let original_occurrence = NOW + 2 * HOUR;
        insert_event(&conn, "cal1", "rec1", "Daily sync", 276, "CONFIRMED", master_start, master_start + HOUR, None);
        insert_recurrence(&conn, "cal1", "rec1", "RRULE:FREQ=DAILY");
        // This occurrence was moved 3 hours later
        insert_event(
            &conn, "cal1", "rec1", "Daily sync (moved)", 260, "CONFIRMED",
            original_occurrence + 3 * HOUR, original_occurrence + 4 * HOUR,
            Some(original_occurrence),
        );
        let events = query(&conn);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].title, "Daily sync (moved)");
        assert_eq!(events[0].start, (original_occurrence + 3 * HOUR) / 1_000_000);
    }

    #[test]
    fn cancelled_exception_removes_occurrence() {
        let conn = fixture_conn();
        let master_start = NOW + 2 * HOUR - 30 * DAY;
        let original_occurrence = NOW + 2 * HOUR;
        insert_event(&conn, "cal1", "rec1", "Daily sync", 276, "CONFIRMED", master_start, master_start + HOUR, None);
        insert_recurrence(&conn, "cal1", "rec1", "RRULE:FREQ=DAILY");
        insert_event(
            &conn, "cal1", "rec1", "Daily sync", 260, "CANCELLED",
            original_occurrence, original_occurrence + HOUR,
            Some(original_occurrence),
        );
        assert_eq!(query(&conn).len(), 0);
    }

    fn insert_property(
        conn: &Connection,
        cal_id: &str,
        item_id: &str,
        key: &str,
        value: &str,
        recurrence_id: Option<i64>,
    ) {
        conn.execute(
            "INSERT INTO cal_properties VALUES (?1, ?2, ?3, ?4, NULL, ?5)",
            (item_id, key, value, recurrence_id, cal_id),
        )
        .unwrap();
    }

    #[test]
    fn google_conference_url_wins_over_description() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Mtg", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        insert_property(&conn, "cal1", "e1", "DESCRIPTION", "Join here https://example.com/zoom/123", None);
        insert_property(&conn, "cal1", "e1", "X-GOOGLE-CONFERENCE", "https://meet.google.com/abc-defg-hij", None);
        let events = query(&conn);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].url.as_deref(), Some("https://meet.google.com/abc-defg-hij"));
    }

    #[test]
    fn url_property_used_as_fallback() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Mtg", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        insert_property(&conn, "cal1", "e1", "URL", "https://teams.example.com/meet/xyz", None);
        let events = query(&conn);
        assert_eq!(events[0].url.as_deref(), Some("https://teams.example.com/meet/xyz"));
    }

    #[test]
    fn url_extracted_from_description_text() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Mtg", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        insert_property(
            &conn, "cal1", "e1", "DESCRIPTION",
            "Agenda... join at https://meet.google.com/xyz-wxyz-abc) for the call.", None,
        );
        let events = query(&conn);
        // trailing ')' trimmed, terminated at whitespace
        assert_eq!(events[0].url.as_deref(), Some("https://meet.google.com/xyz-wxyz-abc"));
    }

    #[test]
    fn occurrence_specific_url_preferred_over_series() {
        let conn = fixture_conn();
        let master_start = NOW + 2 * HOUR - 30 * DAY;
        let original_occurrence = NOW + 2 * HOUR;
        insert_event(&conn, "cal1", "rec1", "Daily sync", 276, "CONFIRMED", master_start, master_start + HOUR, None);
        insert_recurrence(&conn, "cal1", "rec1", "RRULE:FREQ=DAILY");
        // series-wide URL plus an occurrence-specific override for this occurrence
        insert_property(&conn, "cal1", "rec1", "X-GOOGLE-CONFERENCE", "https://meet.google.com/series-url", None);
        insert_property(
            &conn, "cal1", "rec1", "X-GOOGLE-CONFERENCE",
            "https://meet.google.com/occurrence-url", Some(original_occurrence),
        );
        let events = query(&conn);
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].url.as_deref(), Some("https://meet.google.com/occurrence-url"));
    }

    #[test]
    fn no_properties_yields_no_url() {
        let conn = fixture_conn();
        insert_event(&conn, "cal1", "e1", "Mtg", 260, "CONFIRMED", NOW + HOUR, NOW + 2 * HOUR, None);
        let events = query(&conn);
        assert_eq!(events[0].url, None);
    }

    #[test]
    fn exdate_removes_occurrence() {
        let conn = fixture_conn();
        let master_start = NOW + 2 * HOUR - 30 * DAY;
        insert_event(&conn, "cal1", "rec1", "Daily sync", 276, "CONFIRMED", master_start, master_start + HOUR, None);
        insert_recurrence(&conn, "cal1", "rec1", "RRULE:FREQ=DAILY");
        // EXDATE for the occurrence that would land at NOW + 2h, in UTC iCal form
        let exdate = chrono::DateTime::from_timestamp_micros(NOW + 2 * HOUR)
            .unwrap()
            .format("EXDATE:%Y%m%dT%H%M%SZ")
            .to_string();
        insert_recurrence(&conn, "cal1", "rec1", &exdate);
        assert_eq!(query(&conn).len(), 0);
    }
}
