//! The notification list both the cards and the bell's panel draw from. Pure logic: each change
//! returns the D-Bus signals it owes, which `notify::with` sends.
//! Ported in part from hokum (https://github.com/anomalyco/hokum, MIT): src/cards.rs.

use std::time::{Duration, Instant};

use super::note::{default_timeout, Note};

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Reason { Expired = 1, Dismissed = 2, Closed = 3 }

#[derive(Clone, Debug, PartialEq)]
pub enum Out { Closed(u32, Reason), Action(u32, String) }

/// A notification's pop-up card. `until` runs while not hovered; `left` holds the time left
/// while hovered. Neither: it stays until dismissed.
#[derive(Clone, Copy, Debug)]
struct Card { until: Option<Instant>, left: Option<Duration> }

#[derive(Debug)]
struct Entry { note: Note, card: Option<Card> }

#[derive(Debug, Default)]
pub struct Store {
    pub dnd: bool,
    /// The bar holds `org.freedesktop.Notifications`.
    pub owned: bool,
    /// Newest first.
    entries: Vec<Entry>,
    paused: bool,
}

/// Cards shown at once; the rest wait behind a "N more" pill.
pub const SHOWN: usize = 4;

impl Card {
    fn start(n: &Note, paused: bool, now: Instant) -> Card {
        match default_timeout(n) {
            None => Card { until: None, left: None },
            Some(t) if paused => Card { until: None, left: Some(t) },
            Some(t) => Card { until: Some(now + t), left: None },
        }
    }
}

impl Store {
    /// A Notify call: replaces the entry with the same id, or the same stack tag from the same
    /// app, in place; else goes first. Its card (re)starts, unless Do Not Disturb holds it back.
    pub fn upsert(&mut self, n: Note, now: Instant) -> Vec<Out> {
        let card = (!self.dnd || n.urgency >= 2).then(|| Card::start(&n, self.paused, now));
        let same = |o: &Entry| o.note.id == n.id || (n.tag.is_some() && o.note.tag == n.tag && o.note.app == n.app);
        let mut outs = Vec::new();
        match self.entries.iter().position(same) {
            Some(i) => {
                if self.entries[i].note.id != n.id { outs.push(Out::Closed(self.entries[i].note.id, Reason::Closed)); }
                self.entries[i] = Entry { note: n, card };
            }
            None if card.is_none() && n.transient => outs.push(Out::Closed(n.id, Reason::Expired)),
            None => self.entries.insert(0, Entry { note: n, card }),
        }
        outs
    }

    fn remove(&mut self, keep: impl Fn(&Note) -> bool, reason: Reason) -> Vec<Out> {
        let mut outs = Vec::new();
        self.entries.retain(|e| keep(&e.note) || { outs.push(Out::Closed(e.note.id, reason)); false });
        outs
    }

    /// The app's CloseNotification.
    pub fn withdraw(&mut self, id: u32) -> Vec<Out> { self.remove(|n| n.id != id, Reason::Closed) }
    pub fn dismiss(&mut self, id: u32) -> Vec<Out> { self.remove(|n| n.id != id, Reason::Dismissed) }
    pub fn clear(&mut self) -> Vec<Out> { self.remove(|n| n.transient, Reason::Dismissed) }

    /// A card's × or right-click: the card leaves, the entry stays (a transient one, never
    /// listed, ends).
    pub fn hide_card(&mut self, id: u32) -> Vec<Out> {
        self.entries.iter_mut().filter(|e| e.note.id == id).for_each(|e| e.card = None);
        self.remove(|n| n.id != id || !n.transient, Reason::Dismissed)
    }

    /// Default action or a button: the app hears it, then the notification is done with
    /// (Android's auto-cancel), unless it's resident.
    /// The stack's "Clear all": every card goes; the list stays (transients, never listed, end).
    pub fn hide_cards(&mut self) -> Vec<Out> {
        self.entries.iter_mut().for_each(|e| e.card = None);
        self.remove(|n| !n.transient, Reason::Dismissed)
    }

    pub fn invoke(&mut self, id: u32, key: &str) -> Vec<Out> {
        let Some(e) = self.entries.iter_mut().find(|e| e.note.id == id) else { return Vec::new() };
        e.card = None;
        let resident = e.note.resident;
        let mut outs = vec![Out::Action(id, key.to_owned())];
        if !resident { outs.extend(self.dismiss(id)); }
        outs
    }

    pub fn expire(&mut self, now: Instant) -> Vec<Out> {
        for e in &mut self.entries {
            if e.card.is_some_and(|c| c.until.is_some_and(|u| u <= now)) { e.card = None; }
        }
        let ended = |e: &Entry| e.note.transient && e.card.is_none();
        let outs = self.entries.iter().filter(|e| ended(e)).map(|e| Out::Closed(e.note.id, Reason::Expired)).collect();
        self.entries.retain(|e| !ended(e));
        outs
    }

    /// While the pointer is over the cards their timers stand still.
    pub fn pause(&mut self, paused: bool, now: Instant) {
        if paused == self.paused { return; }
        self.paused = paused;
        for c in self.entries.iter_mut().filter_map(|e| e.card.as_mut()) {
            *c = match (paused, c.until, c.left) {
                (true, Some(u), _) => Card { until: None, left: Some(u.saturating_duration_since(now)) },
                (false, _, Some(l)) => Card { until: Some(now + l), left: None },
                _ => *c,
            };
        }
    }

    pub fn set_dnd(&mut self, on: bool) {
        self.dnd = on;
        if on { self.entries.iter_mut().filter(|e| e.note.urgency < 2).for_each(|e| e.card = None); }
    }

    pub fn next_deadline(&self) -> Option<Instant> {
        self.entries.iter().filter_map(|e| e.card?.until).min()
    }

    /// The cards to show, newest first, and how many more wait.
    pub fn cards(&self) -> (Vec<&Note>, usize) {
        let all: Vec<&Note> = self.entries.iter().filter(|e| e.card.is_some()).map(|e| &e.note).collect();
        let more = all.len().saturating_sub(SHOWN);
        (all.into_iter().take(SHOWN).collect(), more)
    }

    fn listed(&self) -> impl Iterator<Item = &Note> { self.entries.iter().map(|e| &e.note).filter(|n| !n.transient) }

    /// The list by app, newest group first, newest first within a group; silent ones apart.
    pub fn groups(&self) -> Vec<(String, Vec<&Note>)> {
        let mut groups: Vec<(String, Vec<&Note>)> = Vec::new();
        for n in self.listed().filter(|n| n.urgency >= 1) {
            match groups.iter_mut().find(|(a, _)| *a == n.app) {
                Some((_, v)) => v.push(n),
                None => groups.push((n.app.clone(), vec![n])),
            }
        }
        groups
    }

    pub fn silent(&self) -> Vec<&Note> { self.listed().filter(|n| n.urgency == 0).collect() }
    pub fn is_empty(&self) -> bool { self.listed().next().is_none() }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn note(id: u32, app: &str, urgency: u8) -> Note {
        let mut n = Note::new(id, app, &format!("s{id}"), "");
        n.urgency = urgency;
        n
    }
    fn ids(v: &[&Note]) -> Vec<u32> { v.iter().map(|n| n.id).collect() }
    fn listed(s: &Store) -> Vec<u32> {
        s.groups().into_iter().flat_map(|(_, v)| ids(&v)).chain(ids(&s.silent())).collect()
    }

    #[test]
    fn replace_by_id_and_tag_updates_in_place() {
        let (mut s, t) = (Store::default(), Instant::now());
        s.upsert(note(1, "a", 1), t);
        s.upsert(note(2, "b", 1), t);
        let mut n = note(1, "a", 1);
        n.summary = "new".into();
        assert_eq!(s.upsert(n, t), vec![]);
        assert_eq!(listed(&s), vec![2, 1]);
        assert_eq!(s.groups()[1].1[0].summary, "new");
        let mut v = note(3, "vol", 1);
        v.tag = Some("volume".into());
        s.upsert(v.clone(), t);
        v.id = 4;
        assert_eq!(s.upsert(v, t), vec![Out::Closed(3, Reason::Closed)]);
        assert_eq!(listed(&s), vec![4, 2, 1]);
    }

    #[test]
    fn replace_unknown_id_inserts() {
        let mut s = Store::default();
        s.upsert(note(50, "a", 1), Instant::now());
        assert_eq!(listed(&s), vec![50]);
    }

    #[test]
    fn hiding_a_card_keeps_the_entry_and_owes_nothing() {
        let mut s = Store::default();
        s.upsert(note(1, "a", 1), Instant::now());
        assert_eq!(s.hide_card(1), vec![]);
        assert!(s.cards().0.is_empty());
        assert_eq!(listed(&s), vec![1]);
    }

    #[test]
    fn withdraw_removes_card_and_entry_once() {
        let mut s = Store::default();
        s.upsert(note(1, "a", 1), Instant::now());
        assert_eq!(s.withdraw(1), vec![Out::Closed(1, Reason::Closed)]);
        assert_eq!(s.withdraw(1), vec![]);
        assert!(s.cards().0.is_empty() && s.is_empty());
    }

    #[test]
    fn invoke_owes_action_then_dismissed_unless_resident() {
        let mut s = Store::default();
        s.upsert(note(1, "a", 1), Instant::now());
        assert_eq!(s.invoke(1, "default"), vec![Out::Action(1, "default".into()), Out::Closed(1, Reason::Dismissed)]);
        assert!(s.is_empty());
        let mut r = note(2, "a", 1);
        r.resident = true;
        s.upsert(r, Instant::now());
        assert_eq!(s.invoke(2, "play"), vec![Out::Action(2, "play".into())]);
        assert_eq!(listed(&s), vec![2]);
        assert_eq!(s.invoke(9, "x"), vec![]);
    }

    #[test]
    fn dnd_hides_cards_but_lists_and_lets_critical_through() {
        let (mut s, t) = (Store::default(), Instant::now());
        s.upsert(note(1, "a", 1), t);
        s.set_dnd(true);
        assert!(s.cards().0.is_empty());
        s.upsert(note(2, "a", 1), t);
        s.upsert(note(3, "a", 2), t);
        assert_eq!(ids(&s.cards().0), vec![3]);
        assert_eq!(listed(&s), vec![3, 2, 1]);
    }

    #[test]
    fn expiry_hides_cards_and_ends_transients() {
        let (mut s, t) = (Store::default(), Instant::now());
        let mut tr = note(1, "a", 1);
        tr.transient = true;
        s.upsert(tr, t);
        s.upsert(note(2, "b", 1), t);
        assert!(!s.is_empty());
        assert_eq!(s.next_deadline(), Some(t + Duration::from_secs(6)));
        assert_eq!(s.expire(t + Duration::from_secs(5)), vec![]);
        assert_eq!(s.expire(t + Duration::from_secs(6)), vec![Out::Closed(1, Reason::Expired)]);
        assert!(s.cards().0.is_empty());
        assert_eq!(listed(&s), vec![2]);
        assert_eq!(s.next_deadline(), None);
    }

    #[test]
    fn transients_are_never_listed() {
        let mut s = Store::default();
        let mut tr = note(1, "a", 1);
        tr.transient = true;
        s.upsert(tr, Instant::now());
        assert_eq!(ids(&s.cards().0), vec![1]);
        assert!(s.is_empty() && listed(&s).is_empty());
        assert_eq!(s.hide_card(1), vec![Out::Closed(1, Reason::Dismissed)]);
    }

    #[test]
    fn pause_keeps_time_left() {
        let (mut s, t) = (Store::default(), Instant::now());
        s.upsert(note(1, "a", 1), t);
        s.pause(true, t + Duration::from_secs(2));
        assert_eq!(s.next_deadline(), None);
        assert_eq!(s.expire(t + Duration::from_secs(30)), vec![]);
        s.pause(false, t + Duration::from_secs(10));
        assert_eq!(s.next_deadline(), Some(t + Duration::from_secs(14)));
    }

    #[test]
    fn burst_shows_four_cards_and_counts_the_rest() {
        let (mut s, t) = (Store::default(), Instant::now());
        for id in 1..=30 { s.upsert(note(id, "chat", 1), t); }
        let (cards, more) = s.cards();
        assert_eq!(ids(&cards), vec![30, 29, 28, 27]);
        assert_eq!(more, 26);
    }

    #[test]
    fn groups_by_app_newest_first_and_silent_apart() {
        let (mut s, t) = (Store::default(), Instant::now());
        s.upsert(note(1, "a", 1), t);
        s.upsert(note(2, "b", 1), t);
        s.upsert(note(3, "a", 1), t);
        s.upsert(note(4, "c", 0), t);
        let g = s.groups();
        assert_eq!(g.iter().map(|(a, v)| (a.as_str(), ids(v))).collect::<Vec<_>>(), vec![("a", vec![3, 1]), ("b", vec![2])]);
        assert_eq!(ids(&s.silent()), vec![4]);
        assert_eq!(s.dismiss(2), vec![Out::Closed(2, Reason::Dismissed)]);
    }

    #[test]
    fn hiding_all_cards_keeps_the_list() {
        let (mut s, t) = (Store::default(), Instant::now());
        let mut tr = note(1, "a", 1);
        tr.transient = true;
        s.upsert(tr, t);
        s.upsert(note(2, "b", 1), t);
        assert_eq!(s.hide_cards(), vec![Out::Closed(1, Reason::Dismissed)]);
        assert!(s.cards().0.is_empty());
        assert_eq!(listed(&s), vec![2]);
    }

    #[test]
    fn clear_owes_dismissed_for_every_entry() {
        let (mut s, t) = (Store::default(), Instant::now());
        s.upsert(note(1, "a", 1), t);
        s.upsert(note(2, "b", 0), t);
        assert_eq!(s.clear(), vec![Out::Closed(2, Reason::Dismissed), Out::Closed(1, Reason::Dismissed)]);
        assert!(s.is_empty() && s.cards().0.is_empty());
    }
}
