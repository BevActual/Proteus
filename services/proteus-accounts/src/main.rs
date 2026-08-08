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
// Calendar/mail/contacts write for menu-bar glances (reconnect older seats).
const GOOGLE_SCOPES: &str = "openid email profile \
https://www.googleapis.com/auth/calendar.events \
https://www.googleapis.com/auth/gmail.metadata \
https://www.googleapis.com/auth/gmail.send \
https://www.googleapis.com/auth/contacts";

const MS_AUTH: &str = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
const MS_TOKEN: &str = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
const MS_SCOPES: &str =
    "openid profile email offline_access User.Read Calendars.ReadWrite Mail.ReadBasic Mail.Send Contacts.ReadWrite";

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
    #[serde(default, rename = "baseUrl")]
    base_url: String,
    connected_at: u64,
}

#[derive(Default, Serialize, Deserialize)]
struct Index {
    seats: Vec<Seat>,
}

#[derive(Default, Serialize, Deserialize)]
struct TokenBlob {
    access_token: String,
    #[serde(default)]
    refresh_token: String,
    #[serde(default)]
    expires_at: u64,
    #[serde(default)]
    id_token: String,
    /// Nextcloud instance URL (app-password seats); empty for OAuth providers.
    #[serde(default, rename = "baseUrl")]
    base_url: String,
    #[serde(default)]
    username: String,
    #[serde(default)]
    kind: String,
    /// Apple composite seat — CalDAV home (defaults on connect).
    #[serde(default, rename = "caldavUrl")]
    caldav_url: String,
    /// Apple composite seat — CardDAV home.
    #[serde(default, rename = "carddavUrl")]
    carddav_url: String,
    /// Apple composite seat — IMAP host.
    #[serde(default, rename = "imapHost")]
    imap_host: String,
    /// Apple composite seat — IMAP port.
    #[serde(default, rename = "imapPort")]
    imap_port: u16,
}

fn usage() -> ! {
    eprintln!(
        "Usage: proteus-accounts <catalog|status|list|connect|disconnect|token|smoke> [args…]\n\
         catalog              — JSON connector catalog\n\
         status               — catalog + seats (no secrets)\n\
         list                 — connected seats only\n\
         connect google       — Google PKCE (PROTEUS_GOOGLE_OAUTH_CLIENT_ID)\n\
         connect microsoft    — Microsoft PKCE (PROTEUS_MICROSOFT_OAUTH_CLIENT_ID)\n\
         connect nextcloud <base-url> <user> <app-password>\n\
         connect imap <host> <port> <user> <password>\n\
         connect caldav <calendar-home-url> <user> <password>\n\
         connect carddav <addressbook-home-url> <user> <password>\n\
         connect apple <apple-id> <app-specific-password>\n\
         connect exchange     — Exchange / work·school Microsoft PKCE (same client id as microsoft)\n\
         disconnect <seat-id> — remove seat + token vault entry\n\
         token <seat-id|provider> — access token JSON (refresh if needed; calendar/mail glance)\n\
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
            hint: "Sign in with Google (calendar.events · gmail.metadata · gmail.send · contacts) — reconnect if seat predates write/send/contacts scopes".into(),
        },
        CatalogEntry {
            id: "microsoft".into(),
            label: "Microsoft".into(),
            connect_kind: "oauth_pkce".into(),
            v1_status: "connectable".into(),
            hint: "Sign in with Microsoft (Calendars.ReadWrite · Mail.ReadBasic · Mail.Send · Contacts.ReadWrite) — reconnect if seat predates write/send/contacts scopes".into(),
        },
        CatalogEntry {
            id: "nextcloud".into(),
            label: "Nextcloud".into(),
            connect_kind: "app_password".into(),
            v1_status: "connectable".into(),
            hint: "Self-hosted instance · app password (Settings → Security) · CalDAV glance".into(),
        },
        CatalogEntry {
            id: "apple".into(),
            label: "Apple ID".into(),
            connect_kind: "app_password".into(),
            v1_status: "connectable".into(),
            hint: "Apple ID + app-specific password — iCloud IMAP/CalDAV/CardDAV glances + SMTP send (not Sign in with Apple OAuth)".into(),
        },
        CatalogEntry {
            id: "exchange".into(),
            label: "Exchange / Outlook".into(),
            connect_kind: "oauth_pkce".into(),
            v1_status: "connectable".into(),
            hint: "Work / school Microsoft 365 — same PKCE client as Microsoft (Calendars.ReadWrite · Mail.ReadBasic · Mail.Send · Contacts.ReadWrite); not EWS/NTLM".into(),
        },
        CatalogEntry {
            id: "imap".into(),
            label: "Mail (IMAP)".into(),
            connect_kind: "manual".into(),
            v1_status: "connectable".into(),
            hint: "IMAP host · port · user · password/app password (TLS) — mail glance + SMTP send (smtp.* :587)".into(),
        },
        CatalogEntry {
            id: "caldav".into(),
            label: "CalDAV".into(),
            connect_kind: "manual".into(),
            v1_status: "connectable".into(),
            hint: "Calendar home URL · user · password/app password — calendar glance".into(),
        },
        CatalogEntry {
            id: "carddav".into(),
            label: "CardDAV".into(),
            connect_kind: "manual".into(),
            v1_status: "connectable".into(),
            hint: "Address-book home URL · user · password/app password — contacts glance".into(),
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

fn load_token(seat_id: &str) -> Result<TokenBlob, String> {
    let p = vault_path(seat_id);
    let raw = fs::read_to_string(&p).map_err(|_| format!("no token vault for seat {seat_id}"))?;
    serde_json::from_str(&raw).map_err(|e| format!("token vault parse: {e}"))
}

fn find_seat(id_or_provider: &str) -> Result<Seat, String> {
    let key = id_or_provider.trim();
    if key.is_empty() {
        return Err("token requires seat id or provider".into());
    }
    let idx = load_index();
    if let Some(s) = idx.seats.iter().find(|s| s.id == key) {
        return Ok(s.clone());
    }
    if let Some(s) = idx.seats.iter().find(|s| s.provider == key) {
        return Ok(s.clone());
    }
    Err(format!("unknown seat or provider: {key}"))
}

fn refresh_oauth_token(
    token_url: &str,
    client_id: &str,
    refresh_token: &str,
) -> Result<TokenBlob, String> {
    if refresh_token.is_empty() {
        return Err("missing refresh_token — reconnect the seat".into());
    }
    let form = [
        ("client_id", client_id),
        ("grant_type", "refresh_token"),
        ("refresh_token", refresh_token),
    ];
    let resp = ureq::post(token_url)
        .set("Content-Type", "application/x-www-form-urlencoded")
        .send_form(&form)
        .map_err(|e| format!("token refresh: {e}"))?;
    let body: Value = resp.into_json().map_err(|e| format!("token json: {e}"))?;
    if let Some(err) = body.get("error") {
        return Err(format!(
            "refresh error: {err} {}",
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
        .unwrap_or(refresh_token)
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
        base_url: String::new(),
        username: String::new(),
        kind: "oauth_pkce".into(),
        caldav_url: String::new(),
        carddav_url: String::new(),
        imap_host: String::new(),
        imap_port: 0,
    })
}

fn ensure_access_token(seat: &Seat) -> Result<(TokenBlob, bool), String> {
    let mut blob = load_token(&seat.id)?;
    if seat.provider == "nextcloud"
        || seat.provider == "imap"
        || seat.provider == "caldav"
        || seat.provider == "carddav"
        || seat.provider == "apple"
    {
        // Manual / app-password seats: access_token holds the password.
        return Ok((blob, false));
    }
    let skew = 60u64;
    if blob.expires_at > now_secs().saturating_add(skew) && !blob.access_token.is_empty() {
        return Ok((blob, false));
    }
    let client_id = match seat.provider.as_str() {
        "google" => google_client_id()?,
        "microsoft" | "exchange" => microsoft_client_id()?,
        other => return Err(format!("token refresh unsupported for {other}")),
    };
    let token_url = match seat.provider.as_str() {
        "google" => GOOGLE_TOKEN,
        "microsoft" | "exchange" => MS_TOKEN,
        _ => unreachable!(),
    };
    let mut refreshed = refresh_oauth_token(token_url, &client_id, &blob.refresh_token)?;
    // Preserve Nextcloud-only fields (empty for OAuth).
    if refreshed.refresh_token.is_empty() {
        refreshed.refresh_token = blob.refresh_token.clone();
    }
    if refreshed.id_token.is_empty() {
        refreshed.id_token = blob.id_token.clone();
    }
    save_token(&seat.id, &refreshed)?;
    blob = refreshed;
    Ok((blob, true))
}

fn cmd_token(id_or_provider: &str) -> Result<Value, String> {
    let seat = find_seat(id_or_provider)?;
    let (blob, refreshed) = ensure_access_token(&seat)?;
    let mut out = json!({
        "ok": true,
        "seatId": seat.id,
        "provider": seat.provider,
        "label": seat.label,
        "email": seat.email,
        "baseUrl": if blob.base_url.is_empty() { seat.base_url.clone() } else { blob.base_url.clone() },
        "username": blob.username,
        "kind": blob.kind,
        "accessToken": blob.access_token,
        "expiresAt": blob.expires_at,
        "refreshed": refreshed,
        // Never echo refresh_token.
    });
    if let Some(obj) = out.as_object_mut() {
        if !blob.caldav_url.is_empty() {
            obj.insert("caldavUrl".into(), json!(blob.caldav_url));
        }
        if !blob.carddav_url.is_empty() {
            obj.insert("carddavUrl".into(), json!(blob.carddav_url));
        }
        if !blob.imap_host.is_empty() {
            obj.insert("imapHost".into(), json!(blob.imap_host));
            obj.insert(
                "imapPort".into(),
                json!(if blob.imap_port == 0 { 993 } else { blob.imap_port }),
            );
        }
    }
    Ok(out)
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

fn oauth_client_id(env_key: &str, file_name: &str, label: &str) -> Result<String, String> {
    if let Ok(v) = env::var(env_key) {
        let t = v.trim().to_string();
        if !t.is_empty() {
            return Ok(t);
        }
    }
    let p = xdg_config().join("proteus").join(file_name);
    if let Ok(s) = fs::read_to_string(p) {
        let t = s.trim().to_string();
        if !t.is_empty() {
            return Ok(t);
        }
    }
    Err(format!(
        "{label} client id missing — set {env_key} or ~/.config/proteus/{file_name}"
    ))
}

fn google_client_id() -> Result<String, String> {
    oauth_client_id(
        "PROTEUS_GOOGLE_OAUTH_CLIENT_ID",
        "oauth-google-client-id",
        "Google",
    )
}

fn microsoft_client_id() -> Result<String, String> {
    oauth_client_id(
        "PROTEUS_MICROSOFT_OAUTH_CLIENT_ID",
        "oauth-microsoft-client-id",
        "Microsoft",
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
        base_url: String::new(),
        username: String::new(),
        kind: "oauth_pkce".into(),
        caldav_url: String::new(),
        carddav_url: String::new(),
        imap_host: String::new(),
        imap_port: 0,
    })
}

fn exchange_oauth_token(
    token_url: &str,
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
    let resp = ureq::post(token_url)
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
        base_url: String::new(),
        username: String::new(),
        kind: "oauth_pkce".into(),
        caldav_url: String::new(),
        carddav_url: String::new(),
        imap_host: String::new(),
        imap_port: 0,
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
    for key in ["email", "preferred_username", "upn"] {
        if let Some(e) = v.get(key).and_then(|e| e.as_str()) {
            if !e.is_empty() {
                return e.to_string();
            }
        }
    }
    String::new()
}

/// Upsert one seat without wiping sibling seats for the same provider.
/// Prefer `PROTEUS_ACCOUNTS_REPLACE_SEAT` (edit path); else match
/// provider + email + baseUrl identity; else append a new seat.
fn upsert_seat(mut seat: Seat, blob: &TokenBlob) -> Result<Value, String> {
    let mut idx = load_index();
    let replace_env = env::var("PROTEUS_ACCOUNTS_REPLACE_SEAT")
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());
    let match_pos = replace_env
        .as_deref()
        .and_then(|id| {
            idx.seats
                .iter()
                .position(|s| s.id == id && s.provider == seat.provider)
        })
        .or_else(|| {
            let email = seat.email.trim().to_ascii_lowercase();
            let base = seat.base_url.trim().trim_end_matches('/').to_string();
            idx.seats.iter().position(|s| {
                s.provider == seat.provider
                    && s.email.trim().eq_ignore_ascii_case(&email)
                    && s.base_url.trim().trim_end_matches('/') == base
            })
        });

    if let Some(i) = match_pos {
        let old_id = idx.seats[i].id.clone();
        seat.id = old_id;
        idx.seats[i] = seat.clone();
    } else {
        idx.seats.push(seat.clone());
    }
    save_token(&seat.id, blob)?;
    save_index(&idx)?;
    Ok(json!({
        "ok": true,
        "seat": {
            "id": seat.id,
            "provider": seat.provider,
            "label": seat.label,
            "email": seat.email,
            "baseUrl": seat.base_url,
        }
    }))
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
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "google".into(),
            label,
            email,
            base_url: String::new(),
            connected_at: now_secs(),
        },
        &blob,
    )
}

fn connect_microsoft() -> Result<Value, String> {
    let client_id = microsoft_client_id()?;
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let redirect = format!("http://127.0.0.1:{port}/callback");
    let verifier = b64url_rand(32);
    let challenge = pkce_challenge(&verifier);
    let state = b64url_rand(16);

    let mut auth = Url::parse(MS_AUTH).map_err(|e| e.to_string())?;
    {
        let mut q = auth.query_pairs_mut();
        q.append_pair("client_id", &client_id);
        q.append_pair("redirect_uri", &redirect);
        q.append_pair("response_type", "code");
        q.append_pair("scope", MS_SCOPES);
        q.append_pair("state", &state);
        q.append_pair("code_challenge", &challenge);
        q.append_pair("code_challenge_method", "S256");
        q.append_pair("prompt", "select_account");
    }

    eprintln!("Opening browser for Microsoft sign-in…");
    eprintln!("If nothing opens, visit:\n  {}", auth.as_str());
    let _ = open_browser(auth.as_str());

    let code = wait_oauth_code(&listener, &state)?;
    let blob = exchange_oauth_token(MS_TOKEN, &client_id, &code, &redirect, &verifier)?;
    let email = email_from_id_token(&blob.id_token);
    let label = if email.is_empty() {
        "Microsoft".to_string()
    } else {
        email.clone()
    };
    let seat_id = format!("microsoft-{}", now_secs());
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "microsoft".into(),
            label,
            email,
            base_url: String::new(),
            connected_at: now_secs(),
        },
        &blob,
    )
}

/// Work / school Exchange Online via the same Microsoft Graph PKCE as `connect microsoft`.
/// Separate seat provider so personal Microsoft and org Exchange can coexist.
/// Out: EWS SOAP · Autodiscover UI · on-prem NTLM · basic auth.
fn connect_exchange() -> Result<Value, String> {
    let client_id = microsoft_client_id()?;
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let redirect = format!("http://127.0.0.1:{port}/callback");
    let verifier = b64url_rand(32);
    let challenge = pkce_challenge(&verifier);
    let state = b64url_rand(16);

    let mut auth = Url::parse(MS_AUTH).map_err(|e| e.to_string())?;
    {
        let mut q = auth.query_pairs_mut();
        q.append_pair("client_id", &client_id);
        q.append_pair("redirect_uri", &redirect);
        q.append_pair("response_type", "code");
        q.append_pair("scope", MS_SCOPES);
        q.append_pair("state", &state);
        q.append_pair("code_challenge", &challenge);
        q.append_pair("code_challenge_method", "S256");
        q.append_pair("prompt", "select_account");
    }

    eprintln!("Opening browser for Exchange / work·school Microsoft sign-in…");
    eprintln!("If nothing opens, visit:\n  {}", auth.as_str());
    let _ = open_browser(auth.as_str());

    let code = wait_oauth_code(&listener, &state)?;
    let blob = exchange_oauth_token(MS_TOKEN, &client_id, &code, &redirect, &verifier)?;
    let email = email_from_id_token(&blob.id_token);
    let label = if email.is_empty() {
        "Exchange".to_string()
    } else {
        format!("{email} · Exchange")
    };
    let seat_id = format!("exchange-{}", now_secs());
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "exchange".into(),
            label,
            email,
            base_url: String::new(),
            connected_at: now_secs(),
        },
        &blob,
    )
}

fn normalize_nextcloud_base(raw: &str) -> Result<String, String> {
    let t = raw.trim().trim_end_matches('/').to_string();
    if t.is_empty() {
        return Err("nextcloud base URL required".into());
    }
    let url = Url::parse(&t).map_err(|e| format!("invalid nextcloud URL: {e}"))?;
    match url.scheme() {
        "http" | "https" => {}
        other => return Err(format!("nextcloud URL scheme must be http(s), got {other}")),
    }
    if url.host_str().unwrap_or("").is_empty() {
        return Err("nextcloud URL missing host".into());
    }
    Ok(t)
}

fn basic_auth_header(user: &str, pass: &str) -> String {
    format!("Basic {}", B64.encode(format!("{user}:{pass}")))
}

fn verify_nextcloud(base: &str, user: &str, pass: &str) -> Result<(), String> {
    if env::var("PROTEUS_ACCOUNTS_SKIP_VERIFY")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        return Ok(());
    }
    let status_url = format!("{base}/status.php");
    let status = ureq::get(&status_url)
        .timeout(std::time::Duration::from_secs(12))
        .call()
        .map_err(|e| format!("nextcloud status.php unreachable: {e}"))?;
    if !(200..300).contains(&status.status()) {
        return Err(format!(
            "nextcloud status.php HTTP {}",
            status.status()
        ));
    }
    let ocs = format!("{base}/ocs/v2.php/cloud/user");
    let resp = ureq::get(&ocs)
        .timeout(std::time::Duration::from_secs(12))
        .set("OCS-APIRequest", "true")
        .set("Accept", "application/json")
        .set("Authorization", &basic_auth_header(user, pass))
        .call()
        .map_err(|e| format!("nextcloud auth failed: {e}"))?;
    if !(200..300).contains(&resp.status()) {
        return Err(format!(
            "nextcloud app-password rejected (HTTP {})",
            resp.status()
        ));
    }
    Ok(())
}

fn connect_nextcloud(base_url: &str, username: &str, app_password: &str) -> Result<Value, String> {
    let base = normalize_nextcloud_base(base_url)?;
    let user = username.trim().to_string();
    let pass = app_password.trim().to_string();
    if user.is_empty() {
        return Err("nextcloud username required".into());
    }
    if pass.is_empty() {
        return Err("nextcloud app password required".into());
    }
    verify_nextcloud(&base, &user, &pass)?;
    let label = format!("{user}@{base}");
    let seat_id = format!("nextcloud-{}", now_secs());
    let blob = TokenBlob {
        access_token: pass,
        refresh_token: String::new(),
        expires_at: 0,
        id_token: String::new(),
        base_url: base.clone(),
        username: user.clone(),
        kind: "app_password".into(),
        caldav_url: String::new(),
        carddav_url: String::new(),
        imap_host: String::new(),
        imap_port: 0,
    };
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "nextcloud".into(),
            label,
            email: user,
            base_url: base,
            connected_at: now_secs(),
        },
        &blob,
    )
}

fn verify_imap(host: &str, port: u16, user: &str, pass: &str) -> Result<(), String> {
    if env::var("PROTEUS_ACCOUNTS_SKIP_VERIFY")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        return Ok(());
    }
    // Stdlib imaplib — matches mail-glance stack; no new Rust IMAP crate.
    let py = format!(
        r#"import imaplib,sys
host=sys.argv[1]; port=int(sys.argv[2]); user=sys.argv[3]; pw=sys.argv[4]
M=imaplib.IMAP4_SSL(host,port,timeout=12)
try:
    typ,_=M.login(user,pw)
    if typ!="OK":
        raise SystemExit("login failed")
    typ,_=M.select("INBOX",readonly=True)
    if typ!="OK":
        raise SystemExit("INBOX select failed")
finally:
    try: M.logout()
    except Exception: pass
"#
    );
    let out = std::process::Command::new("python3")
        .args(["-c", &py, host, &port.to_string(), user, pass])
        .output()
        .map_err(|e| format!("imap verify (python3): {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        let msg = err.trim();
        return Err(if msg.is_empty() {
            "imap login failed".into()
        } else {
            format!("imap: {}", msg.chars().take(200).collect::<String>())
        });
    }
    Ok(())
}

fn normalize_caldav_base(raw: &str) -> Result<String, String> {
    let t = raw.trim().trim_end_matches('/').to_string();
    if t.is_empty() {
        return Err("caldav calendar home URL required".into());
    }
    let url = Url::parse(&t).map_err(|e| format!("invalid caldav URL: {e}"))?;
    match url.scheme() {
        "http" | "https" => {}
        other => return Err(format!("caldav URL scheme must be http(s), got {other}")),
    }
    if url.host_str().unwrap_or("").is_empty() {
        return Err("caldav URL missing host".into());
    }
    Ok(t)
}

fn verify_caldav(base: &str, user: &str, pass: &str) -> Result<(), String> {
    if env::var("PROTEUS_ACCOUNTS_SKIP_VERIFY")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        return Ok(());
    }
    let propfind = r#"<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop><d:displayname/><d:resourcetype/></d:prop>
</d:propfind>
"#;
    let url = format!("{base}/");
    let resp = ureq::request("PROPFIND", &url)
        .timeout(std::time::Duration::from_secs(12))
        .set("Depth", "0")
        .set("Content-Type", "application/xml; charset=utf-8")
        .set("Authorization", &basic_auth_header(user, pass))
        .send_string(propfind)
        .map_err(|e| format!("caldav PROPFIND: {e}"))?;
    let status = resp.status();
    // 207 Multi-Status is the usual success; some servers return 200.
    if status != 207 && !(200..300).contains(&status) {
        return Err(format!("caldav auth/home rejected (HTTP {status})"));
    }
    Ok(())
}

fn connect_caldav(base_url: &str, username: &str, password: &str) -> Result<Value, String> {
    let base = normalize_caldav_base(base_url)?;
    let user = username.trim().to_string();
    let pass = password.trim().to_string();
    if user.is_empty() {
        return Err("caldav username required".into());
    }
    if pass.is_empty() {
        return Err("caldav password required".into());
    }
    verify_caldav(&base, &user, &pass)?;
    let host = Url::parse(&base)
        .ok()
        .and_then(|u| u.host_str().map(|h| h.to_string()))
        .unwrap_or_else(|| "caldav".into());
    let label = format!("{user}@{host}");
    let seat_id = format!("caldav-{}", now_secs());
    let blob = TokenBlob {
        access_token: pass,
        refresh_token: String::new(),
        expires_at: 0,
        id_token: String::new(),
        base_url: base.clone(),
        username: user.clone(),
        kind: "caldav_manual".into(),
        caldav_url: String::new(),
        carddav_url: String::new(),
        imap_host: String::new(),
        imap_port: 0,
    };
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "caldav".into(),
            label,
            email: user,
            base_url: base,
            connected_at: now_secs(),
        },
        &blob,
    )
}

fn normalize_carddav_base(raw: &str) -> Result<String, String> {
    let t = raw.trim().trim_end_matches('/').to_string();
    if t.is_empty() {
        return Err("carddav address-book home URL required".into());
    }
    let url = Url::parse(&t).map_err(|e| format!("invalid carddav URL: {e}"))?;
    match url.scheme() {
        "http" | "https" => {}
        other => return Err(format!("carddav URL scheme must be http(s), got {other}")),
    }
    if url.host_str().unwrap_or("").is_empty() {
        return Err("carddav URL missing host".into());
    }
    Ok(t)
}

fn verify_carddav(base: &str, user: &str, pass: &str) -> Result<(), String> {
    if env::var("PROTEUS_ACCOUNTS_SKIP_VERIFY")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
    {
        return Ok(());
    }
    let propfind = r#"<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop><d:displayname/><d:resourcetype/></d:prop>
</d:propfind>
"#;
    let url = format!("{base}/");
    let resp = ureq::request("PROPFIND", &url)
        .timeout(std::time::Duration::from_secs(12))
        .set("Depth", "0")
        .set("Content-Type", "application/xml; charset=utf-8")
        .set("Authorization", &basic_auth_header(user, pass))
        .send_string(propfind)
        .map_err(|e| format!("carddav PROPFIND: {e}"))?;
    let status = resp.status();
    if status != 207 && !(200..300).contains(&status) {
        return Err(format!("carddav auth/home rejected (HTTP {status})"));
    }
    Ok(())
}

fn connect_carddav(base_url: &str, username: &str, password: &str) -> Result<Value, String> {
    let base = normalize_carddav_base(base_url)?;
    let user = username.trim().to_string();
    let pass = password.trim().to_string();
    if user.is_empty() {
        return Err("carddav username required".into());
    }
    if pass.is_empty() {
        return Err("carddav password required".into());
    }
    verify_carddav(&base, &user, &pass)?;
    let host = Url::parse(&base)
        .ok()
        .and_then(|u| u.host_str().map(|h| h.to_string()))
        .unwrap_or_else(|| "carddav".into());
    let label = format!("{user}@{host}");
    let seat_id = format!("carddav-{}", now_secs());
    let blob = TokenBlob {
        access_token: pass,
        refresh_token: String::new(),
        expires_at: 0,
        id_token: String::new(),
        base_url: base.clone(),
        username: user.clone(),
        kind: "carddav_manual".into(),
        caldav_url: String::new(),
        carddav_url: String::new(),
        imap_host: String::new(),
        imap_port: 0,
    };
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "carddav".into(),
            label,
            email: user,
            base_url: base,
            connected_at: now_secs(),
        },
        &blob,
    )
}

/// Thin Apple / iCloud seat — Apple ID + app-specific password.
/// Defaults: IMAP imap.mail.me.com:993 · CalDAV caldav.icloud.com · CardDAV contacts.icloud.com.
fn connect_apple(apple_id: &str, app_password: &str) -> Result<Value, String> {
    let user = apple_id.trim().to_string();
    let pass = app_password.trim().to_string();
    if user.is_empty() || !user.contains('@') {
        return Err("apple id must be a full email (Apple ID)".into());
    }
    if pass.is_empty() {
        return Err("apple app-specific password required".into());
    }
    let imap_host = "imap.mail.me.com";
    let imap_port: u16 = 993;
    let caldav = "https://caldav.icloud.com";
    let carddav = "https://contacts.icloud.com";
    verify_imap(imap_host, imap_port, &user, &pass)?;
    verify_caldav(caldav, &user, &pass)?;
    verify_carddav(carddav, &user, &pass)?;
    let label = format!("{user} · iCloud");
    let seat_id = format!("apple-{}", now_secs());
    let blob = TokenBlob {
        access_token: pass,
        refresh_token: String::new(),
        expires_at: 0,
        id_token: String::new(),
        base_url: caldav.into(),
        username: user.clone(),
        kind: "apple_app_password".into(),
        caldav_url: caldav.into(),
        carddav_url: carddav.into(),
        imap_host: imap_host.into(),
        imap_port,
    };
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "apple".into(),
            label,
            email: user,
            base_url: caldav.into(),
            connected_at: now_secs(),
        },
        &blob,
    )
}

fn connect_imap(host: &str, port_s: &str, username: &str, password: &str) -> Result<Value, String> {
    let host = host.trim().to_string();
    let user = username.trim().to_string();
    let pass = password.trim().to_string();
    if host.is_empty() {
        return Err("imap host required".into());
    }
    if host.contains('/') || host.contains(' ') {
        return Err("imap host must be a hostname (no URL path)".into());
    }
    let port: u16 = port_s
        .trim()
        .parse()
        .map_err(|_| "imap port must be a number".to_string())?;
    if !(1..=65535).contains(&port) {
        return Err("imap port out of range".into());
    }
    if user.is_empty() {
        return Err("imap username required".into());
    }
    if pass.is_empty() {
        return Err("imap password required".into());
    }
    verify_imap(&host, port, &user, &pass)?;
    let base = format!("imaps://{host}:{port}");
    let label = format!("{user}@{host}");
    let seat_id = format!("imap-{}", now_secs());
    let blob = TokenBlob {
        access_token: pass,
        refresh_token: String::new(),
        expires_at: 0,
        id_token: String::new(),
        base_url: base.clone(),
        username: user.clone(),
        kind: "imap_manual".into(),
        caldav_url: String::new(),
        carddav_url: String::new(),
        imap_host: String::new(),
        imap_port: 0,
    };
    upsert_seat(
        Seat {
            id: seat_id,
            provider: "imap".into(),
            label,
            email: user,
            base_url: base,
            connected_at: now_secs(),
        },
        &blob,
    )
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
    let microsoft_ready = microsoft_client_id().is_ok();
    json!({
        "ok": true,
        "googleClientConfigured": google_ready,
        "microsoftClientConfigured": microsoft_ready,
        "nextcloudConnectable": true,
        "imapConnectable": true,
        "caldavConnectable": true,
        "carddavConnectable": true,
        "appleConnectable": true,
        "exchangeConnectable": microsoft_ready,
        "connectors": rows,
        "seats": seats,
    })
}

fn smoke_json() -> Value {
    let vault = vault_dir();
    let microsoft_ready = microsoft_client_id().is_ok();
    json!({
        "ok": true,
        "catalogCount": catalog().len(),
        "indexPath": index_path().display().to_string(),
        "vaultDir": vault.display().to_string(),
        "googleClientConfigured": google_client_id().is_ok(),
        "microsoftClientConfigured": microsoft_ready,
        "nextcloudConnectable": true,
        "imapConnectable": true,
        "caldavConnectable": true,
        "carddavConnectable": true,
        "appleConnectable": true,
        "exchangeConnectable": microsoft_ready,
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
                "microsoft" => connect_microsoft(),
                "exchange" => connect_exchange(),
                "nextcloud" => {
                    let base = args.next().unwrap_or_default();
                    let user = args.next().unwrap_or_default();
                    let pass = args.next().unwrap_or_default();
                    if base.is_empty() || user.is_empty() || pass.is_empty() {
                        Err(
                            "connect nextcloud requires <base-url> <user> <app-password>".into(),
                        )
                    } else {
                        connect_nextcloud(&base, &user, &pass)
                    }
                }
                "imap" => {
                    let host = args.next().unwrap_or_default();
                    let port = args.next().unwrap_or_else(|| "993".into());
                    let user = args.next().unwrap_or_default();
                    let pass = args.next().unwrap_or_default();
                    if host.is_empty() || user.is_empty() || pass.is_empty() {
                        Err("connect imap requires <host> <port> <user> <password>".into())
                    } else {
                        connect_imap(&host, &port, &user, &pass)
                    }
                }
                "caldav" => {
                    let base = args.next().unwrap_or_default();
                    let user = args.next().unwrap_or_default();
                    let pass = args.next().unwrap_or_default();
                    if base.is_empty() || user.is_empty() || pass.is_empty() {
                        Err(
                            "connect caldav requires <calendar-home-url> <user> <password>".into(),
                        )
                    } else {
                        connect_caldav(&base, &user, &pass)
                    }
                }
                "carddav" => {
                    let base = args.next().unwrap_or_default();
                    let user = args.next().unwrap_or_default();
                    let pass = args.next().unwrap_or_default();
                    if base.is_empty() || user.is_empty() || pass.is_empty() {
                        Err(
                            "connect carddav requires <addressbook-home-url> <user> <password>"
                                .into(),
                        )
                    } else {
                        connect_carddav(&base, &user, &pass)
                    }
                }
                "apple" => {
                    let user = args.next().unwrap_or_default();
                    let pass = args.next().unwrap_or_default();
                    if user.is_empty() || pass.is_empty() {
                        Err("connect apple requires <apple-id> <app-specific-password>".into())
                    } else {
                        connect_apple(&user, &pass)
                    }
                }
                "" => Err(
                    "connect requires provider (google|microsoft|nextcloud|imap|caldav|carddav|apple|exchange)"
                        .into(),
                ),
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
        "token" => {
            let id = args.next().unwrap_or_default();
            cmd_token(&id)
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
        assert_eq!(
            catalog().iter().find(|c| c.id == "google").unwrap().v1_status,
            "connectable"
        );
        assert_eq!(
            catalog()
                .iter()
                .find(|c| c.id == "microsoft")
                .unwrap()
                .v1_status,
            "connectable"
        );
        assert_eq!(
            catalog()
                .iter()
                .find(|c| c.id == "nextcloud")
                .unwrap()
                .v1_status,
            "connectable"
        );
        assert_eq!(
            catalog()
                .iter()
                .find(|c| c.id == "imap")
                .unwrap()
                .v1_status,
            "connectable"
        );
        assert_eq!(
            catalog()
                .iter()
                .find(|c| c.id == "caldav")
                .unwrap()
                .v1_status,
            "connectable"
        );
        assert_eq!(
            catalog()
                .iter()
                .find(|c| c.id == "apple")
                .unwrap()
                .v1_status,
            "connectable"
        );
        assert_eq!(
            catalog()
                .iter()
                .find(|c| c.id == "carddav")
                .unwrap()
                .v1_status,
            "connectable"
        );
        assert_eq!(
            catalog()
                .iter()
                .find(|c| c.id == "exchange")
                .unwrap()
                .v1_status,
            "connectable"
        );
    }

    #[test]
    fn pkce_challenge_stable() {
        let c = pkce_challenge("test-verifier-value-0123456789");
        assert!(!c.is_empty());
        assert_eq!(c, pkce_challenge("test-verifier-value-0123456789"));
    }

    #[test]
    fn nextcloud_url_normalizes() {
        assert_eq!(
            normalize_nextcloud_base("https://cloud.example/").unwrap(),
            "https://cloud.example"
        );
        assert!(normalize_nextcloud_base("ftp://x").is_err());
        assert!(normalize_nextcloud_base("").is_err());
    }
}
