use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};
use regex::Regex;

pub struct ProfileInfo {
    pub db_path: PathBuf,
    /// cal_id (registry UUID) -> calendar display name
    pub calendar_names: HashMap<String, String>,
    /// The user's own email addresses, for declined-event detection
    pub identity_emails: Vec<String>,
}

/// Locate the default Thunderbird profile and pull out what we need from it.
pub fn discover(home: &Path) -> Result<ProfileInfo> {
    let tb_dir = home.join(".thunderbird");
    let profiles_ini =
        fs::read_to_string(tb_dir.join("profiles.ini")).context("reading profiles.ini")?;
    let profile_rel =
        default_profile(&profiles_ini).context("no default Thunderbird profile found")?;
    let profile_dir = tb_dir.join(profile_rel);
    let prefs = fs::read_to_string(profile_dir.join("prefs.js")).context("reading prefs.js")?;

    Ok(ProfileInfo {
        db_path: profile_dir.join("calendar-data").join("cache.sqlite"),
        calendar_names: parse_calendar_names(&prefs),
        identity_emails: parse_identity_emails(&prefs),
    })
}

/// Find the default profile's relative path from profiles.ini contents.
///
/// Prefers the `Default=` key of an `[Install...]` section (how modern
/// Thunderbird marks the active profile), falling back to the `[Profile...]`
/// section carrying `Default=1`.
fn default_profile(ini: &str) -> Option<String> {
    let sections = parse_ini(ini);

    for (name, kv) in &sections {
        if name.starts_with("Install") {
            if let Some(path) = kv.get("Default") {
                return Some(path.clone());
            }
        }
    }

    for (name, kv) in &sections {
        if name.starts_with("Profile") && kv.get("Default").map(String::as_str) == Some("1") {
            return kv.get("Path").cloned();
        }
    }

    None
}

fn parse_ini(text: &str) -> Vec<(String, HashMap<String, String>)> {
    let mut sections: Vec<(String, HashMap<String, String>)> = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with(';') || line.starts_with('#') {
            continue;
        }
        if line.starts_with('[') && line.ends_with(']') {
            sections.push((line[1..line.len() - 1].to_string(), HashMap::new()));
        } else if let Some((k, v)) = line.split_once('=') {
            if let Some(last) = sections.last_mut() {
                last.1.insert(k.trim().to_string(), v.trim().to_string());
            }
        }
    }
    sections
}

fn parse_calendar_names(prefs: &str) -> HashMap<String, String> {
    let re =
        Regex::new(r#"user_pref\("calendar\.registry\.([^."]+)\.name",\s*"([^"]*)"\)"#).unwrap();
    re.captures_iter(prefs)
        .map(|c| (c[1].to_string(), c[2].to_string()))
        .collect()
}

fn parse_identity_emails(prefs: &str) -> Vec<String> {
    let re = Regex::new(r#"user_pref\("mail\.identity\.[^"]+\.useremail",\s*"([^"]*)"\)"#).unwrap();
    let mut emails: Vec<String> = re.captures_iter(prefs).map(|c| c[1].to_string()).collect();
    emails.sort();
    emails.dedup();
    emails
}

#[cfg(test)]
mod tests {
    use super::*;

    const PROFILES_INI: &str = r#"
[Install0123456789ABCDEF]
Default=abcdefgh.default
Locked=1

[Profile0]
Name=default
IsRelative=1
Path=abcdefgh.default
Default=1
"#;

    const PROFILES_INI_LEGACY: &str = r#"
[Profile1]
Name=other
IsRelative=1
Path=aaaa.other

[Profile0]
Name=default
IsRelative=1
Path=bbbb.default
Default=1
"#;

    const PREFS_JS: &str = r#"
user_pref("calendar.registry.11111111-2222-3333-4444-555555555555.name", "Personal");
user_pref("calendar.registry.11111111-2222-3333-4444-555555555555.type", "caldav");
user_pref("calendar.registry.aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.name", "Holidays in Testland");
user_pref("mail.identity.id1.useremail", "alice@example.com");
user_pref("mail.identity.id2.useremail", "alice@work.example");
user_pref("mail.identity.id3.useremail", "alice@example.com");
"#;

    #[test]
    fn finds_default_profile_from_install_section() {
        assert_eq!(default_profile(PROFILES_INI).as_deref(), Some("abcdefgh.default"));
    }

    #[test]
    fn finds_default_profile_from_legacy_default_flag() {
        assert_eq!(default_profile(PROFILES_INI_LEGACY).as_deref(), Some("bbbb.default"));
    }

    #[test]
    fn returns_none_when_no_default_profile() {
        assert_eq!(default_profile("[General]\nVersion=2\n"), None);
    }

    #[test]
    fn parses_calendar_names() {
        let names = parse_calendar_names(PREFS_JS);
        assert_eq!(
            names.get("11111111-2222-3333-4444-555555555555").map(String::as_str),
            Some("Personal")
        );
        assert_eq!(
            names.get("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee").map(String::as_str),
            Some("Holidays in Testland")
        );
        assert_eq!(names.len(), 2);
    }

    #[test]
    fn parses_identity_emails_deduped() {
        let emails = parse_identity_emails(PREFS_JS);
        assert_eq!(emails, vec!["alice@example.com", "alice@work.example"]);
    }
}
