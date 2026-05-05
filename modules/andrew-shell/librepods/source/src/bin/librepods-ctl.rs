// Thin CLI on top of the librepods daemon's Unix-socket IPC. Each subcommand
// is a one-shot connect/send/receive, except `watch` which streams snapshot
// JSON forever.

use clap::{Parser, Subcommand};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::time::Duration;

#[derive(Parser)]
#[command(version, about = "Talk to the librepods daemon")]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Print the current snapshot as JSON.
    Status,
    /// Set noise-control mode: off | anc | transparency | adaptive
    Mode {
        value: String,
    },
    /// Toggle conversational awareness.
    ConversationalAwareness {
        #[arg(value_parser = parse_bool)]
        value: bool,
    },
    /// Reclaim audio from whichever peer currently owns it.
    TakeBack,
    /// Stream snapshots: one JSON object per line, on every state change.
    Watch,
}

fn parse_bool(s: &str) -> Result<bool, String> {
    match s.to_lowercase().as_str() {
        "on" | "true" | "1" | "yes" => Ok(true),
        "off" | "false" | "0" | "no" => Ok(false),
        _ => Err(format!("expected on/off, got {}", s)),
    }
}

fn socket_path() -> PathBuf {
    if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
        return PathBuf::from(dir).join("librepods.sock");
    }
    PathBuf::from("/tmp/librepods.sock")
}

fn main() {
    let cli = Cli::parse();
    let path = socket_path();
    let mut stream = match UnixStream::connect(&path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!(
                "librepods-ctl: cannot connect to {}: {}",
                path.display(),
                e
            );
            eprintln!("hint: is the librepods daemon running?");
            std::process::exit(2);
        }
    };
    let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));

    let request = match &cli.command {
        Cmd::Status => serde_json::json!({"cmd": "status"}),
        Cmd::Mode { value } => serde_json::json!({"cmd": "mode", "value": value}),
        Cmd::ConversationalAwareness { value } => serde_json::json!({
            "cmd": "conversational_awareness",
            "value": value,
        }),
        Cmd::TakeBack => serde_json::json!({"cmd": "take_back"}),
        Cmd::Watch => {
            // Watch needs a longer (effectively no) timeout for reads.
            let _ = stream.set_read_timeout(None);
            serde_json::json!({"cmd": "watch"})
        }
    };

    let mut req_bytes = serde_json::to_vec(&request).unwrap();
    req_bytes.push(b'\n');
    if let Err(e) = stream.write_all(&req_bytes) {
        eprintln!("librepods-ctl: write failed: {}", e);
        std::process::exit(2);
    }

    let mut reader = BufReader::new(stream);

    if matches!(cli.command, Cmd::Watch) {
        // Stream lines forever (or until the daemon closes).
        loop {
            let mut line = String::new();
            match reader.read_line(&mut line) {
                Ok(0) => return,
                Ok(_) => {
                    print!("{}", line);
                    let _ = std::io::stdout().flush();
                }
                Err(e) => {
                    eprintln!("librepods-ctl: read failed: {}", e);
                    std::process::exit(2);
                }
            }
        }
    }

    let mut line = String::new();
    if let Err(e) = reader.read_line(&mut line) {
        eprintln!("librepods-ctl: read failed: {}", e);
        std::process::exit(2);
    }
    print!("{}", line);

    // Surface non-success responses as a non-zero exit so shell scripts can
    // branch on them (e.g. quickmenu showing an error toast).
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(&line) {
        if let Some(err) = v.get("error").and_then(|e| e.as_str()) {
            eprintln!("librepods-ctl: error: {}", err);
            std::process::exit(1);
        }
    }
}
