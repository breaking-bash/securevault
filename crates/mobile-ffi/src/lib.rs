//! Facade over the Rust core for the mobile (Flutter) app.
//!
//! Only plain types cross this boundary (`String`, `Vec<u8>`, `bool`, `u32`,
//! simple structs/enums) so `flutter_rust_bridge` can bind it without custom
//! codegen rules. Binding generation lives in the `securevault-mobile` repo.
//!
//! Boundary caveat: plaintext returned as `Vec<u8>` is copied into the host
//! runtime (Dart), where it cannot be reliably zeroized. Keep payloads small
//! and short-lived on the UI side.
//!
//! On-disk layout under `dir`:
//! - `account.sve`: non-secret account envelope
//! - `keys/<vault>.svk`: wrapped vault keys (length-prefixed sealed blobs)
//! - `items/<vault>/<item>.svi`: sealed items
//!
//! The Secret Key is never written here; the app must keep it in the platform
//! keystore or have the user supply it. Pending independent review.

use std::fs;
use std::path::{Path, PathBuf};

use crypto_engine::{Argon2idParams, CryptoError, OsRandom, Sealed, SecureRandom};
use key_manager::{
    AccountEnvelope, KeyError, KeyManager, LockState, SoftwareKeyManager, SECRET_KEY_LEN,
};
use shared_types::{ItemId, VaultId};
use storage_engine::FileStore;
use vault_engine::{SealedVaultEngine, VaultEngine, VaultError};

const DEFAULT_VAULT: &str = "personal";
const ENVELOPE_FILE: &str = "account.sve";
const KEYS_DIR: &str = "keys";
const ITEMS_DIR: &str = "items";
const KEYS_EXT: &str = "svk";

/// Errors visible to the app. Messages never include secret material.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum FfiError {
    /// An argument was malformed.
    #[error("invalid input: {0}")]
    InvalidInput(String),
    /// The vault is locked.
    #[error("locked")]
    Locked,
    /// Password or Secret Key was wrong (deliberately indistinguishable).
    #[error("wrong password or secret key")]
    WrongCredentials,
    /// Item or vault does not exist.
    #[error("not found")]
    NotFound,
    /// An account already exists in the directory.
    #[error("account already exists")]
    AlreadyExists,
    /// Stored data failed authentication or parsing.
    #[error("stored data is corrupt or tampered")]
    Corrupt,
    /// Disk or other internal failure.
    #[error("internal error: {0}")]
    Internal(String),
}

impl From<KeyError> for FfiError {
    fn from(e: KeyError) -> Self {
        match e {
            KeyError::Locked => FfiError::Locked,
            KeyError::UnlockFailed => FfiError::WrongCredentials,
            KeyError::UnknownVault | KeyError::UnknownVersion => FfiError::NotFound,
            KeyError::VaultExists => FfiError::AlreadyExists,
            KeyError::InvalidInput(m) => FfiError::InvalidInput(m.to_string()),
            KeyError::NotImplemented | KeyError::Crypto(_) => FfiError::Internal("crypto".into()),
        }
    }
}

impl From<VaultError> for FfiError {
    fn from(e: VaultError) -> Self {
        match e {
            VaultError::Locked => FfiError::Locked,
            VaultError::NotFound => FfiError::NotFound,
            VaultError::Corrupt => FfiError::Corrupt,
            VaultError::Storage(m) => FfiError::Internal(m),
            VaultError::Key(k) => k.into(),
        }
    }
}

impl From<CryptoError> for FfiError {
    fn from(_: CryptoError) -> Self {
        FfiError::Internal("crypto".into())
    }
}

fn io(e: std::io::Error) -> FfiError {
    FfiError::Internal(e.kind().to_string())
}

fn vault_id(s: &str) -> Result<VaultId, FfiError> {
    VaultId::new(s).map_err(|e| FfiError::InvalidInput(e.to_string()))
}

fn item_id(s: &str) -> Result<ItemId, FfiError> {
    ItemId::new(s).map_err(|e| FfiError::InvalidInput(e.to_string()))
}

fn write_atomic(path: &Path, bytes: &[u8]) -> Result<(), FfiError> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, bytes).map_err(io)?;
    fs::rename(&tmp, path).map_err(io)
}

fn encode_secret_key(key: &[u8]) -> String {
    let hex: String = key.iter().map(|b| format!("{b:02X}")).collect();
    hex.as_bytes()
        .chunks(4)
        .map(|c| std::str::from_utf8(c).unwrap_or_default())
        .collect::<Vec<_>>()
        .join("-")
}

fn decode_secret_key(text: &str) -> Result<Vec<u8>, FfiError> {
    let bad = || FfiError::InvalidInput("secret key format".into());
    let clean: String = text
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .collect();
    if clean.len() != SECRET_KEY_LEN * 2 || !clean.is_ascii() {
        return Err(bad());
    }
    (0..clean.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&clean[i..i + 2], 16).map_err(|_| bad()))
        .collect()
}

fn encode_keys(keys: &[Sealed]) -> Vec<u8> {
    let mut out = Vec::new();
    for k in keys {
        let w = k.to_wire();
        out.extend_from_slice(&(w.len() as u32).to_be_bytes());
        out.extend_from_slice(&w);
    }
    out
}

fn decode_keys(mut bytes: &[u8]) -> Result<Vec<Sealed>, FfiError> {
    let mut out = Vec::new();
    while !bytes.is_empty() {
        if bytes.len() < 4 {
            return Err(FfiError::Corrupt);
        }
        let len = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as usize;
        let body = bytes.get(4..4 + len).ok_or(FfiError::Corrupt)?;
        out.push(Sealed::from_wire(body).map_err(|_| FfiError::Corrupt)?);
        bytes = &bytes[4 + len..];
    }
    Ok(out)
}

/// A newly created account.
#[derive(Debug)]
pub struct CreatedAccount {
    /// Unlocked account handle.
    pub account: Account,
    /// Secret Key to show once for the Emergency Kit. Not stored by the core.
    pub secret_key: String,
}

/// An account backed by on-disk storage.
pub struct Account {
    dir: PathBuf,
    engine: SealedVaultEngine<SoftwareKeyManager, FileStore>,
}

impl std::fmt::Debug for Account {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Account")
            .field("locked", &self.is_locked())
            .finish_non_exhaustive()
    }
}

/// Creates a new account using the recommended Argon2id parameters.
pub fn create_account(dir: String, password: String) -> Result<CreatedAccount, FfiError> {
    create_account_with(Path::new(&dir), &password, Argon2idParams::recommended())
}

/// Opens an existing account and unlocks it.
pub fn open_account(
    dir: String,
    password: String,
    secret_key: String,
) -> Result<Account, FfiError> {
    let dir = PathBuf::from(dir);
    let envelope = AccountEnvelope::from_bytes(&fs::read(dir.join(ENVELOPE_FILE)).map_err(
        |e| match e.kind() {
            std::io::ErrorKind::NotFound => FfiError::NotFound,
            _ => io(e),
        },
    )?)?;
    let sk = decode_secret_key(&secret_key)?;
    let mut km = SoftwareKeyManager::open(envelope, &sk)?;
    km.unlock(password.as_bytes())?;
    if let Ok(entries) = fs::read_dir(dir.join(KEYS_DIR)) {
        for entry in entries {
            let path = entry.map_err(io)?.path();
            if path.extension().and_then(|e| e.to_str()) != Some(KEYS_EXT) {
                continue;
            }
            let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("");
            let keys = decode_keys(&fs::read(&path).map_err(io)?)?;
            km.restore_vault(vault_id(stem)?, keys)?;
        }
    }
    let store = FileStore::open(dir.join(ITEMS_DIR))?;
    Ok(Account {
        dir,
        engine: SealedVaultEngine::new(km, store),
    })
}

fn create_account_with(
    dir: &Path,
    password: &str,
    params: Argon2idParams,
) -> Result<CreatedAccount, FfiError> {
    if dir.join(ENVELOPE_FILE).exists() {
        return Err(FfiError::AlreadyExists);
    }
    fs::create_dir_all(dir.join(KEYS_DIR)).map_err(io)?;
    let mut sk = [0u8; SECRET_KEY_LEN];
    OsRandom.fill(&mut sk)?;
    let km = SoftwareKeyManager::create(password.as_bytes(), &sk, params)?;
    write_atomic(&dir.join(ENVELOPE_FILE), &km.envelope().to_bytes())?;
    let store = FileStore::open(dir.join(ITEMS_DIR))?;
    let mut account = Account {
        dir: dir.to_path_buf(),
        engine: SealedVaultEngine::new(km, store),
    };
    account.create_vault(DEFAULT_VAULT.to_string())?;
    Ok(CreatedAccount {
        account,
        secret_key: encode_secret_key(&sk),
    })
}

impl Account {
    /// True when key material is not in memory.
    pub fn is_locked(&self) -> bool {
        self.engine.keys().state() == LockState::Locked
    }

    /// Wipes key material from memory.
    pub fn lock(&mut self) {
        self.engine.keys_mut().lock();
    }

    /// Unlocks a locked account.
    pub fn unlock(&mut self, password: String) -> Result<(), FfiError> {
        Ok(self.engine.keys_mut().unlock(password.as_bytes())?)
    }

    /// Lists vault identifiers.
    pub fn list_vaults(&self) -> Vec<String> {
        self.engine
            .keys()
            .vault_ids()
            .iter()
            .map(ToString::to_string)
            .collect()
    }

    /// Creates a vault with fresh keys.
    pub fn create_vault(&mut self, vault: String) -> Result<(), FfiError> {
        let id = vault_id(&vault)?;
        self.engine.keys_mut().create_vault(&id)?;
        self.persist_keys(&id)
    }

    /// Rotates a vault key and re-encrypts its items. Returns items re-sealed.
    pub fn rotate_vault(&mut self, vault: String) -> Result<u32, FfiError> {
        let id = vault_id(&vault)?;
        self.engine.keys_mut().rotate(&id)?;
        self.persist_keys(&id)?;
        Ok(self.engine.reseal_vault(&id)? as u32)
    }

    /// Stores or replaces an item.
    pub fn put_item(
        &mut self,
        vault: String,
        item: String,
        payload: Vec<u8>,
    ) -> Result<(), FfiError> {
        Ok(self
            .engine
            .put_item(&vault_id(&vault)?, &item_id(&item)?, &payload)?)
    }

    /// Reads and decrypts an item.
    pub fn get_item(&self, vault: String, item: String) -> Result<Vec<u8>, FfiError> {
        let plain = self.engine.get_item(&vault_id(&vault)?, &item_id(&item)?)?;
        Ok(plain.to_vec())
    }

    /// Deletes an item.
    pub fn delete_item(&mut self, vault: String, item: String) -> Result<(), FfiError> {
        Ok(self
            .engine
            .delete_item(&vault_id(&vault)?, &item_id(&item)?)?)
    }

    /// Lists item identifiers in a vault.
    pub fn list_items(&self, vault: String) -> Result<Vec<String>, FfiError> {
        Ok(self
            .engine
            .list_items(&vault_id(&vault)?)?
            .iter()
            .map(ToString::to_string)
            .collect())
    }

    fn persist_keys(&self, vault: &VaultId) -> Result<(), FfiError> {
        let keys = self.engine.keys().wrapped_keys(vault)?;
        let path = self
            .dir
            .join(KEYS_DIR)
            .join(format!("{}.{KEYS_EXT}", vault.as_str()));
        write_atomic(&path, &encode_keys(keys))
    }
}

/// Generates a random password (OS CSPRNG).
pub fn generate_password(
    length: u32,
    symbols: bool,
    exclude_ambiguous: bool,
) -> Result<String, FfiError> {
    let policy = password_generator::Policy {
        length: length as usize,
        symbols,
        exclude_ambiguous,
        ..password_generator::Policy::default()
    };
    password_generator::generate(&policy)
        .map(|p| p.to_string())
        .map_err(|e| FfiError::InvalidInput(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fast(dir: &Path, pw: &str) -> CreatedAccount {
        create_account_with(dir, pw, Argon2idParams::minimum()).unwrap()
    }

    fn s(x: &str) -> String {
        x.to_string()
    }

    #[test]
    fn full_lifecycle_across_restart() {
        let dir = tempfile::tempdir().unwrap();
        let created = fast(dir.path(), "correct horse");
        let sk = created.secret_key.clone();
        let mut acc = created.account;
        assert_eq!(acc.list_vaults(), vec![s("personal")]);
        acc.put_item(s("personal"), s("bank"), b"{\"pw\":\"x\"}".to_vec())
            .unwrap();
        drop(acc);

        let mut again = open_account(
            dir.path().display().to_string(),
            s("correct horse"),
            sk.clone(),
        )
        .unwrap();
        assert_eq!(
            again.get_item(s("personal"), s("bank")).unwrap(),
            b"{\"pw\":\"x\"}"
        );
        again.lock();
        assert!(again.is_locked());
        assert_eq!(
            again.get_item(s("personal"), s("bank")),
            Err(FfiError::Locked)
        );
        assert_eq!(again.unlock(s("nope")), Err(FfiError::WrongCredentials));
        again.unlock(s("correct horse")).unwrap();
        assert_eq!(again.list_items(s("personal")).unwrap(), vec![s("bank")]);
        again.delete_item(s("personal"), s("bank")).unwrap();
        assert_eq!(
            again.get_item(s("personal"), s("bank")),
            Err(FfiError::NotFound)
        );
    }

    #[test]
    fn wrong_credentials_and_bad_secret_key_are_rejected() {
        let dir = tempfile::tempdir().unwrap();
        let sk = fast(dir.path(), "pw-one").secret_key;
        let d = dir.path().display().to_string();
        assert_eq!(
            open_account(d.clone(), s("pw-two"), sk.clone()).unwrap_err(),
            FfiError::WrongCredentials
        );
        assert_eq!(
            open_account(
                d.clone(),
                s("pw-one"),
                s("0000-0000-0000-0000-0000-0000-0000-0000")
            )
            .unwrap_err(),
            FfiError::WrongCredentials
        );
        assert!(matches!(
            open_account(d, s("pw-one"), s("short")),
            Err(FfiError::InvalidInput(_))
        ));
    }

    #[test]
    fn existing_account_is_not_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        fast(dir.path(), "pw");
        assert_eq!(
            create_account_with(dir.path(), "pw2", Argon2idParams::minimum()).unwrap_err(),
            FfiError::AlreadyExists
        );
    }

    #[test]
    fn rotation_persists_and_items_survive_restart() {
        let dir = tempfile::tempdir().unwrap();
        let created = fast(dir.path(), "pw");
        let sk = created.secret_key;
        let mut acc = created.account;
        acc.put_item(s("personal"), s("a"), b"one".to_vec())
            .unwrap();
        assert_eq!(acc.rotate_vault(s("personal")).unwrap(), 1);
        acc.create_vault(s("work")).unwrap();
        acc.put_item(s("work"), s("w"), b"two".to_vec()).unwrap();
        drop(acc);
        let acc = open_account(dir.path().display().to_string(), s("pw"), sk).unwrap();
        assert_eq!(acc.list_vaults(), vec![s("personal"), s("work")]);
        assert_eq!(acc.get_item(s("personal"), s("a")).unwrap(), b"one");
        assert_eq!(acc.get_item(s("work"), s("w")).unwrap(), b"two");
    }

    #[test]
    fn disk_contents_do_not_contain_plaintext() {
        let dir = tempfile::tempdir().unwrap();
        let mut acc = fast(dir.path(), "pw").account;
        acc.put_item(s("personal"), s("a"), b"PLAINTEXT-MARKER".to_vec())
            .unwrap();
        fn scan(p: &Path, found: &mut bool) {
            for e in fs::read_dir(p).unwrap() {
                let path = e.unwrap().path();
                if path.is_dir() {
                    scan(&path, found);
                } else if fs::read(&path)
                    .unwrap()
                    .windows(9)
                    .any(|w| w == b"PLAINTEXT")
                {
                    *found = true;
                }
            }
        }
        let mut found = false;
        scan(dir.path(), &mut found);
        assert!(!found);
    }

    #[test]
    fn secret_key_codec_roundtrips_and_validates() {
        let raw = [0xABu8; SECRET_KEY_LEN];
        let text = encode_secret_key(&raw);
        assert_eq!(text, "ABAB-ABAB-ABAB-ABAB-ABAB-ABAB-ABAB-ABAB");
        assert_eq!(decode_secret_key(&text.to_lowercase()).unwrap(), raw);
        assert!(decode_secret_key("zz").is_err());
        assert!(decode_secret_key(&"é".repeat(32)).is_err());
    }

    #[test]
    fn password_generation_validates_input() {
        assert_eq!(generate_password(24, true, false).unwrap().len(), 24);
        assert!(generate_password(2, true, false).is_err());
    }
}
