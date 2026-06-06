mod events;
mod profile;

use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    thread,
    time::Duration,
};

use anyhow::Result;
use clap::Parser;
use serde::Serialize;

#[derive(Parser)]
#[command(name = "calendar-status")]
#[command(about = "Emit upcoming calendar events from Thunderbird's CalDAV cache", long_about = None)]
struct Cli {
    #[arg(short, long, help = "Print current events and exit (don't keep polling)")]
    once: bool,

    #[arg(long, help = "Skip calendars whose name contains this substring (repeatable)")]
    exclude_calendar: Vec<String>,

    #[arg(long, default_value_t = 24, help = "How many hours ahead to look for events")]
    horizon_hours: u64,
}

#[derive(Serialize)]
struct Output {
    events: Vec<events::Event>,
}

const POLL_INTERVAL: Duration = Duration::from_secs(60);

/// How many consecutive failed polls before we stop re-emitting the last
/// good event list and emit an empty one instead.
const MAX_STALE_TICKS: u32 = 5;

fn main() -> Result<()> {
    let cli = Cli::parse();
    let mut last_good: Option<Vec<events::Event>> = None;
    let mut failures: u32 = 0;

    loop {
        let events = resolve_emission(compute(&cli), &mut last_good, &mut failures);
        println!("{}", serde_json::to_string(&Output { events })?);
        std::io::stdout().flush()?;

        if cli.once {
            return Ok(());
        }
        thread::sleep(POLL_INTERVAL);
    }
}

/// Decide what to emit for this tick.
///
/// Transient read failures (a torn copy while Thunderbird is mid-write, a
/// brief lock state the fallback can't get around, ...) re-emit the last
/// good event list so the widget doesn't flicker out for a tick and back.
/// Only after MAX_STALE_TICKS consecutive failures — data genuinely
/// unavailable, e.g. no Thunderbird profile at all — do we emit an empty
/// list. We keep polling forever either way so the widget recovers on its
/// own.
fn resolve_emission(
    result: Result<Vec<events::Event>>,
    last_good: &mut Option<Vec<events::Event>>,
    failures: &mut u32,
) -> Vec<events::Event> {
    match result {
        Ok(events) => {
            *failures = 0;
            *last_good = Some(events.clone());
            events
        }
        Err(_) => {
            *failures += 1;
            if *failures >= MAX_STALE_TICKS {
                Vec::new()
            } else {
                last_good.clone().unwrap_or_default()
            }
        }
    }
}

fn compute(cli: &Cli) -> Result<Vec<events::Event>> {
    let home = std::env::home_dir().ok_or_else(|| anyhow::anyhow!("no home directory"))?;
    let info = profile::discover(&home)?;
    let now_micros = chrono::Utc::now().timestamp_micros();
    let horizon_micros = (cli.horizon_hours as i64) * 3_600_000_000;

    // Try a direct read-only connection first (works when Thunderbird is closed).
    // Thunderbird holds an exclusive lock on cache.sqlite while running, so the
    // connection opens but every query returns SQLITE_BUSY ("database is locked").
    // On any error fall back to copying the db + WAL to a temp path and reading
    // the copy with write access so SQLite can perform WAL recovery on open.
    match query_events(&info.db_path, true, &info, now_micros, horizon_micros, cli) {
        Ok(evs) => Ok(evs),
        Err(_) => {
            let copy_path = copy_db_for_reading(&info.db_path)?;
            query_events(&copy_path, false, &info, now_micros, horizon_micros, cli)
        }
    }
}

/// Open the SQLite database at `db_path` and return upcoming events.
///
/// When `read_only` is true the connection is opened with
/// `SQLITE_OPEN_READ_ONLY`; otherwise standard read-write flags are used
/// (required for WAL recovery on a copied database).
fn query_events(
    db_path: &Path,
    read_only: bool,
    info: &profile::ProfileInfo,
    now_micros: i64,
    horizon_micros: i64,
    cli: &Cli,
) -> Result<Vec<events::Event>> {
    let conn = if read_only {
        rusqlite::Connection::open_with_flags(
            db_path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        )?
    } else {
        rusqlite::Connection::open(db_path)?
    };
    events::upcoming_events(
        &conn,
        &info.calendar_names,
        &info.identity_emails,
        &cli.exclude_calendar,
        now_micros,
        horizon_micros,
    )
}

/// Copy the SQLite database (and its WAL file if present) to a stable temp
/// path so it can be opened even when the original is exclusively locked by
/// Thunderbird.
///
/// The destination path is reused every tick (overwritten), so no temp files
/// accumulate.
///
/// ASSUMPTION: /tmp is per-machine and single-user on this system (NixOS with
/// tmpfs on /tmp), so a fixed filename is safe.
fn copy_db_for_reading(db_path: &Path) -> Result<PathBuf> {
    let dest = std::env::temp_dir().join("calendar-status-cache.sqlite");
    let dest_wal = dest.with_extension("sqlite-wal");
    let dest_shm = dest.with_extension("sqlite-shm");

    // Copy main database file.
    fs::copy(db_path, &dest)?;

    // Copy WAL if it exists; otherwise remove any stale WAL from a previous tick
    // (a stale WAL against a fresh database copy would corrupt the copy).
    let src_wal = db_path.with_extension("sqlite-wal");
    if src_wal.exists() {
        fs::copy(&src_wal, &dest_wal)?;
    } else if dest_wal.exists() {
        let _ = fs::remove_file(&dest_wal);
    }

    // Never copy the SHM file; SQLite rebuilds it during WAL recovery.
    // Remove any stale one left from a previous tick.
    if dest_shm.exists() {
        let _ = fs::remove_file(&dest_shm);
    }

    Ok(dest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use std::collections::HashMap;

    /// Create a minimal database file at `path` with the calendar schema,
    /// insert one event, and return an open connection that holds an exclusive
    /// WAL lock (simulating Thunderbird while it is running).
    fn make_locked_db(path: &Path) -> Connection {
        // Open the file (not in-memory) so we have a real on-disk database.
        let conn = Connection::open(path).unwrap();
        conn.execute_batch(
            "PRAGMA journal_mode=WAL;
             PRAGMA locking_mode=EXCLUSIVE;
             CREATE TABLE cal_events (
                 cal_id TEXT, id TEXT, title TEXT, flags INTEGER, ical_status TEXT,
                 event_start INTEGER, event_end INTEGER, event_start_tz TEXT,
                 recurrence_id INTEGER);
             CREATE TABLE cal_recurrence (item_id TEXT, cal_id TEXT, icalString TEXT);
             CREATE TABLE cal_attendees (
                 item_id TEXT, recurrence_id INTEGER, recurrence_id_tz TEXT,
                 cal_id TEXT, icalString TEXT);
             CREATE TABLE cal_properties (
                 item_id TEXT, key TEXT, value BLOB,
                 recurrence_id INTEGER, recurrence_id_tz TEXT, cal_id TEXT);
             -- Insert a dummy write so the exclusive WAL lock is actually held.
             INSERT INTO cal_events VALUES
                 ('cal1','e1','Locked Event',260,'CONFIRMED',
                  1780000000000000,1780003600000000,'UTC',NULL);",
        )
        .unwrap();
        // Perform a write to ensure the WAL lock is engaged.
        conn.execute("UPDATE cal_events SET title = title WHERE id = 'e1'", [])
            .unwrap();
        conn
    }

    fn dummy_event(title: &str) -> events::Event {
        events::Event {
            title: title.to_string(),
            start: 1_780_000_000,
            end: 1_780_003_600,
            calendar: "Personal".to_string(),
            url: None,
        }
    }

    #[test]
    fn emission_success_resets_failures_and_remembers_events() {
        let mut last_good = None;
        let mut failures = 3;
        let evs = vec![dummy_event("A")];
        let out = resolve_emission(Ok(evs.clone()), &mut last_good, &mut failures);
        assert_eq!(out, evs);
        assert_eq!(failures, 0);
        assert_eq!(last_good, Some(evs));
    }

    #[test]
    fn emission_transient_failure_holds_last_good() {
        let evs = vec![dummy_event("A")];
        let mut last_good = Some(evs.clone());
        let mut failures = 0;
        let out = resolve_emission(
            Err(anyhow::anyhow!("torn copy")),
            &mut last_good,
            &mut failures,
        );
        assert_eq!(out, evs, "single failure should re-emit last good data");
        assert_eq!(failures, 1);
    }

    #[test]
    fn emission_failure_without_history_is_empty() {
        let mut last_good = None;
        let mut failures = 0;
        let out = resolve_emission(
            Err(anyhow::anyhow!("no profile")),
            &mut last_good,
            &mut failures,
        );
        assert!(out.is_empty());
    }

    #[test]
    fn emission_persistent_failure_goes_empty() {
        let mut last_good = Some(vec![dummy_event("A")]);
        let mut failures = 0;
        for _ in 0..MAX_STALE_TICKS - 1 {
            let out = resolve_emission(
                Err(anyhow::anyhow!("locked")),
                &mut last_good,
                &mut failures,
            );
            assert!(!out.is_empty(), "should hold last good below the threshold");
        }
        let out = resolve_emission(
            Err(anyhow::anyhow!("locked")),
            &mut last_good,
            &mut failures,
        );
        assert!(out.is_empty(), "should go empty at the threshold");
    }

    #[test]
    fn locked_db_fallback_via_copy_succeeds() {
        // Use a unique filename per test run to avoid cross-test interference.
        let db_path = std::env::temp_dir()
            .join(format!("calendar-status-test-{}.sqlite", std::process::id()));

        // _conn stays alive for the duration of the test to hold the lock.
        let _conn = make_locked_db(&db_path);

        // 1. Direct read-only query must fail (database is locked).
        let ro_result = Connection::open_with_flags(
            &db_path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY,
        )
        .and_then(|c| c.query_row("SELECT COUNT(*) FROM cal_events", [], |r| r.get::<_, i64>(0)));
        assert!(
            ro_result.is_err(),
            "expected read-only query to fail while lock is held, got: {:?}",
            ro_result
        );

        // 2. copy_db_for_reading + read-write connection must succeed.
        let copy_path = copy_db_for_reading(&db_path).expect("copy_db_for_reading failed");
        let rw_conn = Connection::open(&copy_path).expect("open copy failed");
        let count: i64 = rw_conn
            .query_row("SELECT COUNT(*) FROM cal_events", [], |r| r.get(0))
            .expect("query on copy failed");
        assert_eq!(count, 1, "expected 1 row in the copy");

        // 3. Validate the copied row via upcoming_events.
        let now_micros: i64 = 1_780_000_000_000_000 - 3_600_000_000; // 1h before the event
        let horizon_micros: i64 = 24 * 3_600_000_000;
        let calendar_names =
            HashMap::from([("cal1".to_string(), "Personal".to_string())]);
        let evs = events::upcoming_events(
            &rw_conn,
            &calendar_names,
            &[],
            &[],
            now_micros,
            horizon_micros,
        )
        .expect("upcoming_events on copy failed");
        assert_eq!(evs.len(), 1);
        assert_eq!(evs[0].title, "Locked Event");

        // Cleanup.
        drop(_conn);
        let _ = fs::remove_file(&db_path);
        let wal = db_path.with_extension("sqlite-wal");
        let shm = db_path.with_extension("sqlite-shm");
        let _ = fs::remove_file(&wal);
        let _ = fs::remove_file(&shm);
    }
}
