//! The bar's notification daemon (`org.freedesktop.Notifications`), replacing SwayNC: pop-up
//! cards like hokum's, and the bell's panel, Android's notification list. Much of it is ported
//! from hokum (https://github.com/anomalyco/hokum, MIT; licence in `HOKUM-LICENSE`).

pub mod note;
pub mod store;
pub mod apps;
pub mod bus;

use std::sync::OnceLock;
use std::sync::mpsc;
use std::time::Instant;

use store::{Out, Store};

static OWED: OnceLock<tokio::sync::mpsc::UnboundedSender<Out>> = OnceLock::new();
static TIMER: OnceLock<std::sync::Mutex<mpsc::Sender<()>>> = OnceLock::new();

/// Starts the bus server and the card timer, each on a thread of its own.
pub fn start() {
    let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
    let _ = OWED.set(tx);
    let _ = std::thread::Builder::new().name("notify-bus".into()).spawn(move || {
        let Ok(rt) = tokio::runtime::Builder::new_current_thread().enable_all().build() else { return };
        if let Err(e) = rt.block_on(bus::serve(rx)) { eprintln!("andrew-bar: notifications: {e}"); }
    });
    let (poke, woken) = mpsc::channel();
    let _ = TIMER.set(std::sync::Mutex::new(poke));
    let _ = std::thread::Builder::new().name("notify-timer".into()).spawn(move || loop {
        let due = crate::hub::data().notify.next_deadline();
        let waited = match due {
            Some(at) => woken.recv_timeout(at.saturating_duration_since(Instant::now())),
            None => woken.recv().map_err(|_| mpsc::RecvTimeoutError::Disconnected),
        };
        match waited {
            Err(mpsc::RecvTimeoutError::Timeout) => with(|s, now| s.expire(now)),
            Err(mpsc::RecvTimeoutError::Disconnected) => return,
            Ok(()) => {}
        }
    });
}

/// Changes the store, sends the signals the change owes, and re-arms the card timer.
pub fn with(f: impl FnOnce(&mut Store, Instant) -> Vec<Out>) {
    let mut owed = Vec::new();
    crate::hub::set(|d| owed = f(&mut d.notify, Instant::now()));
    if let Some(tx) = OWED.get() { for o in owed { let _ = tx.send(o); } }
    if let Some(t) = TIMER.get() { let _ = t.lock().unwrap().send(()); }
    cards::sync();
}

/// `--notify-demo`: hokum's sample notifications, for headless previews.
pub fn demo() {
    let now = Instant::now();
    crate::hub::set(|d| for mut n in cards::samples() { bus::decode(&mut n); d.notify.upsert(n, now); });
}
pub mod cards;
pub mod panel;
