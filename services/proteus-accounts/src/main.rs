//! Online accounts seats for Proteus Settings.
//! Metadata in ~/.config/proteus/accounts.json; tokens in a 0600 vault
//! under ~/.local/share/proteus/accounts/ (never settings.json).
//! Docs: docs/proteus/STACK.md · SETTINGS-IA Online accounts

use base64::engine::general_purpose::{URL_SAFE_NO_PAD, STANDARD as B64};
use base64::Engine;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::time::{SystemTime, UNIX_EPOCH};
use url::Url;

const GOOGLE_AUTH: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN: &str = "https://oauth2.googleapis.com/token";
const GOOGLE_SCOPES: &str = "openid email profile";

#[derive(Clone, Serialize, Deserialize)]
struct CatalogEntry {
    id: String,
    label: String,
    #[serde(rename = "connectKind")]
    connect_kind: String,
    #[serde(rename = "v1Status")]
    v1_status: String,
    hint: String,
}

#[derive(Clone, Serialize, Deserialize)]
struct Seat {
    id: String,
    provider: String,
    label: String,
    #[serde(default)]
    email: String,
    connected_at: u64,
}

#[derive(Default, Serialize, Deserialize)]
struct Index {
    seats: Vec<Seat>,
}

#[derive(Serialize, Deserialize)]
struct TokenBlob {
    access_token: String,
    #[serde(default)]
    refresh_token: String,
    #[serde(default)]
    expires_at: u64,
    #[serde(default)]
    id_token: String,
}

fn usage() -> ! {
    eprintln!(
        "Usage: proteus-accounts <catalog|status|list|connect|disconnect|smoke> [args…]\n\
         catalog              — JSON connector catalog\n\
         status               — catalog + seats (no secrets)\n\
         list                 — connected seats only\n\
         connect <provider>   — google (PKCE); needs PROTEUS_GOOGLE_OAUTH_CLIENT_ID\n\
         disconnect <seat-id> — remove seat + token vault entry\n\
         smoke                — static self-check JSON"
    );
    std::process::exit(2);
}

fn catalog() -> Vec<CatalogEntry> {
    vec![
        CatalogEntry {
            id: "google".into(),
            label: "Google".into(),
            connect_kind: "oauth_pkce".into(),
            v1_status: "connectable".into(),
            hint: "Sign in with Google (openid · email · profile)".into(),
        },
        CatalogEntry {
            id: "microsoft".into(),
            label: "Microsoft".into(),
            connect_kind: "oauth_pkce".into(),
            v1_status: "listed".into(),
            hint: "Entra / MSA — connect later".into(),
        },
        CatalogEntry {
            id: "nextcloud".into(),
            label: "Nextcloud".into(),
            connect_kind: "oauth_or_app_password".into(),
            v1_status: "listed".into(),
            hint: "Self-hosted instance — connect later".into(),
        },
        CatalogEntry {
            id: "apple".into(),
            label: "Apple ID".into(),
            connect_kind: "oauth".into(),
            v1_status: "listed".into(),
            hint: "Sign in with Apple — later".into(),
        },
        CatalogEntry {
            id: "exchange".into(),
            label: "Exchange / Outlook".into(),
            connect_kind: "oauth".into(),
            v1_status: "listed".into(),
            hint: "Work / school mail — later".into(),
        },
        CatalogEntry {
            id: "imap".into(),
            label: "Mail (IMAP/SMTP)".into(),
            connect_kind: "manual".into(),
            v1_status: "listed".into(),
            hint: "Manual credentials — later (not OAuth)".into(),
        },
        CatalogEntry {
            id: "caldav".into(),
            label: "CalDAV".into(),
            connect_kind: "manual".into(),
            v1_status: "listed".into(),
            hint: "Calendar sync — later".into(),
        },
        CatalogEntry {
            id: "carddav".into(),
            label: "CardDAV".into(),
            connect_kind: "manual".into(),
            v1_status: "listed".into(),
            hint: "Contacts sync — later".into(),
        },
    ]
}

fn xdg_config() -> PathBuf {
    env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".config"))
}

fn xdg_data() -> PathBuf {
    env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home().join(".local/share"))
}

fn home() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn index_path() -> PathBuf {
    xdg_config().join("proteus/accounts.json")
}

fn vault_dir() -> PathBuf {
    xdg_data().join("proteus/accounts/tokens")
}

fn load_index() -> Index {
    let p = index_path();
    match fs::read_to_string(&p) {
        Ok(s) => serde_json::from_str(&s).unwrap_or_default(),
        Err(_) => Index::default(),
    }
}

fn save_index(idx: &Index) -> Result<(), String> {
    let p = index_path();
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let raw = serde_json::to_string_pretty(idx).map_err(|e| e.to_string())?;
    fs::write(&p, raw + "\n").map_err(|e| e.to_string())
}

fn vault_path(seat_id: &str) -> PathBuf {
    vault_dir().join(format!("{seat_id}.token.json"))
}

fn save_token(seat_id: &str, blob: &TokenBlob) -> Result<(), String> {
    let dir = vault_dir();
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
    }
    let p = vault_path(seat_id);
    let raw = serde_json::to_string_pretty(blob).map_err(|e| e.to_string())?;
    fs::write(&p, raw + "\n").map_err(|e| e.to_string())?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&p, fs::Permissions::from_mode(0o600));
    }
    Ok(())
}

fn clear_token(seat_id: &str) {
    let _ = fs::remove_file(vault_path(seat_id));
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn b64url_rand(n: usize) -> String {
    let mut buf = vec![0u8; n];
    rand::thread_rng().fill_bytes(&mut buf);
    URL_SAFE_NO_PAD.encode(buf)
}

fn pkce_challenge(verifier: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(verifier.as_bytes());
    URL_SAFE_NO_PAD.encode(hasher.finalize())
}

fn google_client_id() -> Result<String, String> {
    if let Ok(v) = env::var("PROTEUS_GOOGLE_OAUTH_CLIENT_ID") {
        let t = v.trim().to_string();
        if !t.is_empty() {
            return Ok(t);
        }
    }
    let p = xdg_config().join("proteus/oauth-google-client-id");
    if let Ok(s) = fs::read_to_string(p) {
        let t = s.trim().to_string();
        if !t.is_empty() {
            return Ok(t);
        }
    }
    Err(
        "Google client id missing — set PROTEUS_GOOGLE_OAUTH_CLIENT_ID or \
         ~/.config/proteus/oauth-google-client-id"
            .into(),
    )
}

fn open_browser(url: &str) -> Result<(), String> {
    let status = Command::new("xdg-open")
        .arg(url)
        .status()
        .map_err(|e| format!("xdg-open: {e}"))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!("xdg-open exited {}", status.code().unwrap_or(-1)))
    }
}

fn read_http_request(stream: &mut TcpStream) -> Result<String, String> {
    let mut buf = [0u8; 8192];
    let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
    Ok(String::from_utf8_lossy(&buf[..n]).to_string())
}

fn write_http_ok(stream: &mut TcpStream, body: &str) -> Result<(), String> {
    let resp = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    stream.write_all(resp.as_bytes()).map_err(|e| e.to_string())
}

fn wait_oauth_code(listener: &TcpListener, expected_state: &str) -> Result<String, String> {
    loop {
        let (mut stream, _) = listener.accept().map_err(|e| e.to_string())?;
        let req = read_http_request(&mut stream)?;
        let line = req.lines().next().unwrap_or("");
        // GET /callback?code=...&state=... HTTP/1.1
        let path = line.split_whitespace().nth(1).unwrap_or("/");
        let url = Url::parse(&format!("http://127.0.0.1{path}")).map_err(|e| e.to_string())?;
        let mut code = None;
        let mut state = None;
        let mut err = None;
        for (k, v) in url.query_pairs() {
            match k.as_ref() {
                "code" => code = Some(v.to_string()),
                "state" => state = Some(v.to_string()),
                "error" => err = Some(v.to_string()),
                _ => {}
            }
        }
        if let Some(e) = err {
            let _ = write_http_ok(
                &mut stream,
                &format!("<html><body><h1>Sign-in failed</h1><p>{e}</p></body></html>"),
            );
            return Err(format!("oauth error: {e}"));
        }
        if state.as_deref() != Some(expected_state) {
            let _ = write_http_ok(
                &mut stream,
                "<html><body><h1>State mismatch</h1></body></html>",
            );
            continue;
        }
        if let Some(c) = code {
            let _ = write_http_ok(
                &mut stream,
                "<html><body><h1>Connected</h1><p>You can close this window.</p></body></html>",
            );
            return Ok(c);
        }
        let _ = write_http_ok(
            &mut stream,
            "<html><body><h1>Missing code</h1></body></html>",
        );
    }
}

fn exchange_google_token(
    client_id: &str,
    code: &str,
    redirect_uri: &str,
    verifier: &str,
) -> Result<TokenBlob, String> {
    let form = [
        ("code", code),
        ("client_id", client_id),
        ("redirect_uri", redirect_uri),
        ("grant_type", "authorization_code"),
        ("code_verifier", verifier),
    ];
    let resp = ureq::post(GOOGLE_TOKEN)
        .set("Content-Type", "application/x-www-form-urlencoded")
        .send_form(&form)
        .map_err(|e| format!("token exchange: {e}"))?;
    let body: Value = resp.into_json().map_err(|e| format!("token json: {e}"))?;
    if let Some(err) = body.get("error") {
        return Err(format!(
            "token error: {err} {}",
            body.get("error_description").unwrap_or(&Value::Null)
        ));
    }
    let access = body
        .get("access_token")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "missing access_token".to_string())?
        .to_string();
    let refresh = body
        .get("refresh_token")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let id_token = body
        .get("id_token")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    let expires_in = body.get("expires_in").and_then(|v| v.as_u64()).unwrap_or(3600);
    Ok(TokenBlob {
        access_token: access,
        refresh_token: refresh,
        expires_at: now_secs().saturating_add(expires_in),
        id_token,
    })
}

fn email_from_id_token(id_token: &str) -> String {
    let parts: Vec<_> = id_token.split('.').collect();
    if parts.len() < 2 {
        return String::new();
    }
    let padded = match parts[1].len() % 4 {
        0 => parts[1].to_string(),
        2 => format!("{}==", parts[1]),
        3 => format!("{}=", parts[1]),
        _ => return String::new(),
    };
    let bytes = B64.decode(padded.replace('-', "+").replace('_', "/")).ok();
    let Some(bytes) = bytes else {
        return String::new();
    };
    let Ok(v) = serde_json::from_slice::<Value>(&bytes) else {
        return String::new();
    };
    v.get("email")
        .and_then(|e| e.as_str())
        .unwrap_or("")
        .to_string()
}

fn connect_google() -> Result<Value, String> {
    let client_id = google_client_id()?;
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let redirect = format!("http://127.0.0.1:{port}/callback");
    let verifier = b64url_rand(32);
    let challenge = pkce_challenge(&verifier);
    let state = b64url_rand(16);

    let mut auth = Url::parse(GOOGLE_AUTH).map_err(|e| e.to_string())?;
    {
        let mut q = auth.query_pairs_mut();
        q.append_pair("client_id", &client_id);
        q.append_pair("redirect_uri", &redirect);
        q.append_pair("response_type", "code");
        q.append_pair("scope", GOOGLE_SCOPES);
        q.append_pair("state", &state);
        q.append_pair("code_challenge", &challenge);
        q.append_pair("code_challenge_method", "S256");
        q.append_pair("access_type", "offline");
        q.append_pair("prompt", "consent");
    }

    eprintln!("Opening browser for Google sign-in…");
    eprintln!("If nothing opens, visit:\n  {}", auth.as_str());
    let _ = open_browser(auth.as_str());

    let code = wait_oauth_code(&listener, &state)?;
    let blob = exchange_google_token(&client_id, &code, &redirect, &verifier)?;
    let email = email_from_id_token(&blob.id_token);
    let label = if email.is_empty() {
        "Google".to_string()
    } else {
        email.clone()
    };
    let seat_id = format!("google-{}", now_secs());
    save_token(&seat_id, &blob)?;

    let mut idx = load_index();
    // Replace prior google seats (one Google identity seat for v1).
    let old: Vec<_> = idx
        .seats
        .iter()
        .filter(|s| s.provider == "google")
        .map(|s| s.id.clone())
        .collect();
    for id in &old {
        clear_token(id);
    }
    idx.seats.retain(|s| s.provider != "google");
    idx.seats.push(Seat {
        id: seat_id.clone(),
        provider: "google".into(),
        label: label.clone(),
        email: email.clone(),
        connected_at: now_secs(),
    });
    save_index(&idx)?;

    Ok(json!({
        "ok": true,
        "seat": {
            "id": seat_id,
            "provider": "google",
            "label": label,
            "email": email,
        }
    }))
}

fn disconnect_seat(seat_id: &str) -> Result<Value, String> {
    let mut idx = load_index();
    let before = idx.seats.len();
    idx.seats.retain(|s| s.id != seat_id);
    if idx.seats.len() == before {
        return Err(format!("unknown seat id: {seat_id}"));
    }
    clear_token(seat_id);
    save_index(&idx)?;
    Ok(json!({ "ok": true, "disconnected": seat_id }))
}

fn status_json() -> Value {
    let cat = catalog();
    let idx = load_index();
    let seats = &idx.seats;
    let rows: Vec<Value> = cat
        .into_iter()
        .map(|c| {
            let connected: Vec<_> = seats
                .iter()
                .filter(|s| s.provider == c.id)
                .cloned()
                .collect();
            let status = if !connected.is_empty() {
                "connected"
            } else if c.v1_status == "connectable" {
                "not_connected"
            } else {
                "coming_later"
            };
            json!({
                "id": c.id,
                "label": c.label,
                "connectKind": c.connect_kind,
                "v1Status": c.v1_status,
                "hint": c.hint,
                "status": status,
                "seats": connected,
            })
        })
        .collect();
    let google_ready = google_client_id().is_ok();
    json!({
        "ok": true,
        "googleClientConfigured": google_ready,
        "connectors": rows,
        "seats": seats,
    })
}

fn smoke_json() -> Value {
    let vault = vault_dir();
    json!({
        "ok": true,
        "catalogCount": catalog().len(),
        "indexPath": index_path().display().to_string(),
        "vaultDir": vault.display().to_string(),
        "googleClientConfigured": google_client_id().is_ok(),
        "secretsInSettingsJson": false,
    })
}

fn print_json(v: &Value) {
    println!("{}", serde_json::to_string_pretty(v).unwrap_or_else(|_| "{}".into()));
}

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let cmd = match args.next() {
        Some(c) => c,
        None => usage(),
    };

    let result = match cmd.as_str() {
        "catalog" => Ok(json!({ "ok": true, "connectors": catalog() })),
        "list" => Ok(json!({ "ok": true, "seats": load_index().seats })),
        "status" => Ok(status_json()),
        "smoke" => Ok(smoke_json()),
        "connect" => {
            let provider = args.next().unwrap_or_default();
            match provider.as_str() {
                "google" => connect_google(),
                "" => Err("connect requires provider (google)".into()),
                other => Err(format!("provider not connectable in v1: {other}")),
            }
        }
        "disconnect" => {
            let id = args.next().unwrap_or_default();
            if id.is_empty() {
                Err("disconnect requires seat id".into())
            } else {
                disconnect_seat(&id)
            }
        }
        "-h" | "--help" | "help" => usage(),
        other => Err(format!("unknown command: {other}")),
    };

    match result {
        Ok(v) => {
            print_json(&v);
            ExitCode::SUCCESS
        }
        Err(e) => {
            print_json(&json!({ "ok": false, "error": e }));
            ExitCode::from(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catalog_has_priority_providers() {
        let ids: Vec<_> = catalog().into_iter().map(|c| c.id).collect();
        assert!(ids.contains(&"google".into()));
        assert!(ids.contains(&"microsoft".into()));
        assert!(ids.contains(&"nextcloud".into()));
        assert_eq!(catalog().iter().find(|c| c.id == "google").unwrap().v1_status, "connectable");
    }

    #[test]
    fn pkce_challenge_stable() {
        let c = pkce_challenge("test-verifier-value-0123456789");
        assert!(!c.is_empty());
        assert_eq!(c, pkce_challenge("test-verifier-value-0123456789"));
    }
}
