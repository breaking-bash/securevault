//! SecureVault desktop shell.
//!
//! The UI never performs cryptography: it calls the narrow commands below,
//! which delegate to the Rust core via `mobile-ffi::Session`. The Secret Key
//! and master password are only held in memory for the duration of a call;
//! locking drops the unlocked account so keys are zeroized. No filesystem,
//! shell or process access is granted to the webview. Not independently
//! reviewed; not production-ready.

use std::sync::Mutex;

use mobile_ffi::{Session, SessionStatus};
use serde::Serialize;
use tauri::{Manager, State};

/// Non-sensitive application metadata returned to the frontend.
#[derive(Debug, Serialize, PartialEq, Eq)]
pub struct AppInfo {
    name: &'static str,
    version: &'static str,
}

fn build_info() -> AppInfo {
    AppInfo {
        name: "securevault",
        version: env!("CARGO_PKG_VERSION"),
    }
}

/// Shared, lock-protected session.
struct AppState(Mutex<Session>);

fn status_str(s: SessionStatus) -> &'static str {
    match s {
        SessionStatus::NoAccount => "no_account",
        SessionStatus::Locked => "locked",
        SessionStatus::Unlocked => "unlocked",
    }
}

fn with_session<T>(
    state: &State<'_, AppState>,
    f: impl FnOnce(&mut Session) -> Result<T, mobile_ffi::FfiError>,
) -> Result<T, String> {
    let mut guard = state.0.lock().map_err(|_| "internal error".to_string())?;
    f(&mut guard).map_err(|e| e.to_string())
}

/// Returns static application metadata.
#[tauri::command]
fn app_info() -> AppInfo {
    build_info()
}

/// One of `no_account`, `locked`, `unlocked`.
#[tauri::command]
fn vault_status(state: State<'_, AppState>) -> Result<&'static str, String> {
    with_session(&state, |s| Ok(status_str(s.status())))
}

/// Creates the account; returns the Secret Key to show exactly once.
#[tauri::command]
fn create_account(state: State<'_, AppState>, password: String) -> Result<String, String> {
    with_session(&state, |s| s.create(&password))
}

/// Unlocks with master password and Secret Key.
#[tauri::command]
fn unlock(state: State<'_, AppState>, password: String, secret_key: String) -> Result<(), String> {
    with_session(&state, |s| s.unlock(&password, &secret_key))
}

/// Locks the vault, dropping key material.
#[tauri::command]
fn lock(state: State<'_, AppState>) -> Result<(), String> {
    with_session(&state, |s| {
        s.lock();
        Ok(())
    })
}

/// Lists item IDs.
#[tauri::command]
fn list_items(state: State<'_, AppState>) -> Result<Vec<String>, String> {
    with_session(&state, |s| s.list_items())
}

/// Returns an item payload (UTF-8 text produced by the UI).
#[tauri::command]
fn get_item(state: State<'_, AppState>, id: String) -> Result<String, String> {
    with_session(&state, |s| s.get_item(&id))
        .and_then(|b| String::from_utf8(b).map_err(|_| "corrupt item".to_string()))
}

/// Creates (no `id`) or replaces an item; returns its ID.
#[tauri::command]
fn save_item(
    state: State<'_, AppState>,
    id: Option<String>,
    payload: String,
) -> Result<String, String> {
    with_session(&state, |s| s.save_item(id.as_deref(), payload.as_bytes()))
}

/// Deletes an item.
#[tauri::command]
fn delete_item(state: State<'_, AppState>, id: String) -> Result<(), String> {
    with_session(&state, |s| s.delete_item(&id))
}

/// Generates a random password.
#[tauri::command]
fn generate_password(length: u32, symbols: bool) -> Result<String, String> {
    mobile_ffi::generate_password(length, symbols, false).map_err(|e| e.to_string())
}

/// Starts the desktop application.
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let dir = app.path().app_data_dir()?.join("vault");
            app.manage(AppState(Mutex::new(Session::new(dir))));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            vault_status,
            create_account,
            unlock,
            lock,
            list_items,
            get_item,
            save_item,
            delete_item,
            generate_password
        ])
        .run(tauri::generate_context!())
        .expect("error while running SecureVault desktop");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn info_has_name_and_version() {
        let i = build_info();
        assert_eq!(i.name, "securevault");
        assert!(!i.version.is_empty());
    }

    #[test]
    fn status_strings_are_stable() {
        assert_eq!(status_str(SessionStatus::NoAccount), "no_account");
        assert_eq!(status_str(SessionStatus::Locked), "locked");
        assert_eq!(status_str(SessionStatus::Unlocked), "unlocked");
    }
}
