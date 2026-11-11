//! SecureVault desktop shell (Phase 1 scaffold).
//!
//! Exposes only narrow, explicitly allowed commands. No cryptography is
//! implemented and no filesystem, shell or process access is granted.

use serde::Serialize;

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

/// Returns static application metadata.
#[tauri::command]
fn app_info() -> AppInfo {
    build_info()
}

/// Starts the desktop application.
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![app_info])
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
}
