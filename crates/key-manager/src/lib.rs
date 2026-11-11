//! Key manager (ADR-0001).
//!
//! Key hierarchy:
//! 1. `password_key = Argon2id(password, salt)`
//! 2. `AUK = HKDF(password_key || secret_key, "sv/v1/auk")`
//! 3. Per-vault random 256-bit `vault_key`s, wrapped under a purpose-separated
//!    subkey of the AUK, bound to vault id and key version.
//! 4. `item_key = HKDF(vault_key, "sv/v1/item")` for sealing items.
//!
//! The master password never leaves the client. Unwrapped vault keys exist
//! only transiently. **Not independently reviewed; not production-ready.**
//! Recovery and shared-vault key distribution are intentionally absent.

use crypto_engine::{
    hkdf_sha256_subkey, Aead, Argon2idKdf, Argon2idParams, HkdfSubkeys, KeyPurpose, OsRandom,
    PasswordKdf, Sealed, SecureRandom, SubkeyDeriver, XChaChaAead, KEY_LEN,
};
use shared_types::{KeyVersion, VaultId};
use std::collections::HashMap;
use zeroize::Zeroizing;

/// Required Secret Key length in bytes (128 bits).
pub const SECRET_KEY_LEN: usize = 16;
const SALT_LEN: usize = 16;
const AUK_INFO: &[u8] = b"sv/v1/auk";
const CHECK_AAD: &[u8] = b"sv/v1/unlock-check";
const CHECK_PLAINTEXT: &[u8] = b"securevault-unlock-check";

/// Errors returned by key-manager implementations.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum KeyError {
    /// The key manager is locked.
    #[error("key manager is locked")]
    Locked,
    /// Credentials were rejected.
    #[error("unlock failed")]
    UnlockFailed,
    /// The requested key version does not exist.
    #[error("unknown key version")]
    UnknownVersion,
    /// The vault has no keys.
    #[error("unknown vault")]
    UnknownVault,
    /// The vault already has keys.
    #[error("vault already exists")]
    VaultExists,
    /// Input was invalid.
    #[error("invalid input: {0}")]
    InvalidInput(&'static str),
    /// No implementation is available.
    #[error("key management not implemented")]
    NotImplemented,
    /// Underlying crypto failure.
    #[error(transparent)]
    Crypto(#[from] crypto_engine::CryptoError),
}

/// Lock state of the key manager.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockState {
    /// Key material is not available in memory.
    Locked,
    /// Key material is available.
    Unlocked,
}

/// Key lifecycle interface. Secrets must never cross into the frontend.
pub trait KeyManager {
    /// Current lock state.
    fn state(&self) -> LockState;

    /// Unlocks using the master password. It is never sent to a backend.
    fn unlock(&mut self, user_secret: &[u8]) -> Result<(), KeyError>;

    /// Locks and wipes in-memory key material.
    fn lock(&mut self);

    /// Creates version 1 of a new vault key.
    fn create_vault(&mut self, vault: &VaultId) -> Result<KeyVersion, KeyError>;

    /// Current key version for a vault.
    fn current_version(&self, vault: &VaultId) -> Result<KeyVersion, KeyError>;

    /// Rotates the vault key, returning the new version. Older versions are
    /// retained so existing items stay readable until re-encrypted.
    fn rotate(&mut self, vault: &VaultId) -> Result<KeyVersion, KeyError>;

    /// Item cipher for a specific vault key version.
    fn item_cipher(&self, vault: &VaultId, version: KeyVersion) -> Result<Box<dyn Aead>, KeyError>;
}

/// Persistable, non-secret account material. Safe to store; useless without
/// the password and Secret Key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AccountEnvelope {
    /// Argon2id salt.
    pub salt: Vec<u8>,
    /// Argon2id parameters used.
    pub params: Argon2idParams,
    /// Encrypted known value used to verify credentials on unlock.
    pub check: Sealed,
}

/// In-memory key manager holding wrapped vault keys.
pub struct SoftwareKeyManager {
    envelope: AccountEnvelope,
    secret_key: Zeroizing<Vec<u8>>,
    auk: Option<Zeroizing<Vec<u8>>>,
    vaults: HashMap<VaultId, Vec<Sealed>>,
}

impl std::fmt::Debug for SoftwareKeyManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SoftwareKeyManager")
            .field("state", &self.state())
            .field("vaults", &self.vaults.len())
            .finish_non_exhaustive()
    }
}

fn account_version() -> KeyVersion {
    KeyVersion::new(1).expect("1 is a valid key version")
}

fn derive_auk(
    password: &[u8],
    secret_key: &[u8],
    salt: &[u8],
    params: Argon2idParams,
) -> Result<Zeroizing<Vec<u8>>, KeyError> {
    let password_key = Argon2idKdf::new(params)?.derive(password, salt)?;
    let ikm = Zeroizing::new([password_key.as_slice(), secret_key].concat());
    Ok(hkdf_sha256_subkey(&ikm, None, AUK_INFO, KEY_LEN)?)
}

fn wrapping_aead(auk: &[u8]) -> Result<XChaChaAead, KeyError> {
    let key = HkdfSubkeys.derive_subkey(auk, KeyPurpose::KeyWrapping)?;
    Ok(XChaChaAead::new(
        &key,
        account_version(),
        KeyPurpose::KeyWrapping,
    )?)
}

fn wrap_aad(vault: &VaultId, version: KeyVersion) -> Vec<u8> {
    let id = vault.as_str().as_bytes();
    let mut v = b"sv/v1/vault-key".to_vec();
    v.extend_from_slice(&(id.len() as u32).to_be_bytes());
    v.extend_from_slice(id);
    v.extend_from_slice(&version.get().to_be_bytes());
    v
}

fn check_secret_key(secret_key: &[u8]) -> Result<(), KeyError> {
    if secret_key.len() != SECRET_KEY_LEN {
        return Err(KeyError::InvalidInput("secret key must be 16 bytes"));
    }
    Ok(())
}

impl SoftwareKeyManager {
    /// Creates a new account and returns an unlocked manager.
    pub fn create(
        password: &[u8],
        secret_key: &[u8],
        params: Argon2idParams,
    ) -> Result<Self, KeyError> {
        if password.is_empty() {
            return Err(KeyError::InvalidInput("password must not be empty"));
        }
        check_secret_key(secret_key)?;
        let mut salt = vec![0u8; SALT_LEN];
        OsRandom.fill(&mut salt)?;
        let auk = derive_auk(password, secret_key, &salt, params)?;
        let check =
            wrapping_aead(&auk)?.seal(KeyPurpose::KeyWrapping, CHECK_AAD, CHECK_PLAINTEXT)?;
        Ok(Self {
            envelope: AccountEnvelope {
                salt,
                params,
                check,
            },
            secret_key: Zeroizing::new(secret_key.to_vec()),
            auk: Some(auk),
            vaults: HashMap::new(),
        })
    }

    /// Opens an existing account in the locked state.
    pub fn open(envelope: AccountEnvelope, secret_key: &[u8]) -> Result<Self, KeyError> {
        check_secret_key(secret_key)?;
        Ok(Self {
            envelope,
            secret_key: Zeroizing::new(secret_key.to_vec()),
            auk: None,
            vaults: HashMap::new(),
        })
    }

    /// Non-secret account material to persist.
    pub fn envelope(&self) -> &AccountEnvelope {
        &self.envelope
    }

    /// Wrapped vault keys, oldest first, for persistence.
    pub fn wrapped_keys(&self, vault: &VaultId) -> Result<&[Sealed], KeyError> {
        self.vaults
            .get(vault)
            .map(Vec::as_slice)
            .ok_or(KeyError::UnknownVault)
    }

    /// Restores wrapped keys loaded from storage (verified lazily on use).
    pub fn restore_vault(&mut self, vault: VaultId, wrapped: Vec<Sealed>) -> Result<(), KeyError> {
        if wrapped.is_empty() {
            return Err(KeyError::InvalidInput("no wrapped keys"));
        }
        self.vaults.insert(vault, wrapped);
        Ok(())
    }

    fn auk(&self) -> Result<&[u8], KeyError> {
        self.auk
            .as_deref()
            .map(Vec::as_slice)
            .ok_or(KeyError::Locked)
    }

    fn new_wrapped_key(&self, vault: &VaultId, version: KeyVersion) -> Result<Sealed, KeyError> {
        let wrapper = wrapping_aead(self.auk()?)?;
        let mut key = Zeroizing::new(vec![0u8; KEY_LEN]);
        OsRandom.fill(&mut key)?;
        Ok(wrapper.seal(KeyPurpose::KeyWrapping, &wrap_aad(vault, version), &key)?)
    }

    fn vault_key(
        &self,
        vault: &VaultId,
        version: KeyVersion,
    ) -> Result<Zeroizing<Vec<u8>>, KeyError> {
        let wrapper = wrapping_aead(self.auk()?)?;
        let list = self.vaults.get(vault).ok_or(KeyError::UnknownVault)?;
        let idx = (version.get() as usize)
            .checked_sub(1)
            .ok_or(KeyError::UnknownVersion)?;
        let sealed = list.get(idx).ok_or(KeyError::UnknownVersion)?;
        Ok(wrapper.open(KeyPurpose::KeyWrapping, &wrap_aad(vault, version), sealed)?)
    }
}

impl KeyManager for SoftwareKeyManager {
    fn state(&self) -> LockState {
        if self.auk.is_some() {
            LockState::Unlocked
        } else {
            LockState::Locked
        }
    }

    fn unlock(&mut self, user_secret: &[u8]) -> Result<(), KeyError> {
        let auk = derive_auk(
            user_secret,
            &self.secret_key,
            &self.envelope.salt,
            self.envelope.params,
        )
        .map_err(|e| match e {
            KeyError::Crypto(_) => KeyError::UnlockFailed,
            other => other,
        })?;
        let ok = wrapping_aead(&auk)?
            .open(KeyPurpose::KeyWrapping, CHECK_AAD, &self.envelope.check)
            .map(|p| p.as_slice() == CHECK_PLAINTEXT)
            .unwrap_or(false);
        if !ok {
            self.auk = None;
            return Err(KeyError::UnlockFailed);
        }
        self.auk = Some(auk);
        Ok(())
    }

    fn lock(&mut self) {
        self.auk = None;
    }

    fn create_vault(&mut self, vault: &VaultId) -> Result<KeyVersion, KeyError> {
        self.auk()?;
        if self.vaults.contains_key(vault) {
            return Err(KeyError::VaultExists);
        }
        let v1 = KeyVersion::new(1).expect("1 is valid");
        let wrapped = self.new_wrapped_key(vault, v1)?;
        self.vaults.insert(vault.clone(), vec![wrapped]);
        Ok(v1)
    }

    fn current_version(&self, vault: &VaultId) -> Result<KeyVersion, KeyError> {
        self.auk()?;
        let n = self.vaults.get(vault).ok_or(KeyError::UnknownVault)?.len();
        KeyVersion::new(n as u32).map_err(|_| KeyError::UnknownVersion)
    }

    fn rotate(&mut self, vault: &VaultId) -> Result<KeyVersion, KeyError> {
        let next = self
            .current_version(vault)?
            .next()
            .ok_or(KeyError::InvalidInput("key version overflow"))?;
        let wrapped = self.new_wrapped_key(vault, next)?;
        self.vaults
            .get_mut(vault)
            .ok_or(KeyError::UnknownVault)?
            .push(wrapped);
        Ok(next)
    }

    fn item_cipher(&self, vault: &VaultId, version: KeyVersion) -> Result<Box<dyn Aead>, KeyError> {
        let vault_key = self.vault_key(vault, version)?;
        let item_key = HkdfSubkeys.derive_subkey(&vault_key, KeyPurpose::ItemEncryption)?;
        Ok(Box::new(XChaChaAead::new(
            &item_key,
            version,
            KeyPurpose::ItemEncryption,
        )?))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SK: [u8; SECRET_KEY_LEN] = [5u8; SECRET_KEY_LEN];
    const P: KeyPurpose = KeyPurpose::ItemEncryption;

    fn mgr() -> SoftwareKeyManager {
        SoftwareKeyManager::create(b"correct horse", &SK, Argon2idParams::minimum()).unwrap()
    }

    fn vid(s: &str) -> VaultId {
        VaultId::new(s).unwrap()
    }

    #[test]
    fn unlock_roundtrip_and_lock() {
        let m = mgr();
        let mut m2 = SoftwareKeyManager::open(m.envelope().clone(), &SK).unwrap();
        assert_eq!(m2.state(), LockState::Locked);
        m2.unlock(b"correct horse").unwrap();
        assert_eq!(m2.state(), LockState::Unlocked);
        m2.lock();
        assert_eq!(m2.state(), LockState::Locked);
    }

    #[test]
    fn wrong_password_fails() {
        let mut m = SoftwareKeyManager::open(mgr().envelope().clone(), &SK).unwrap();
        assert_eq!(m.unlock(b"wrong"), Err(KeyError::UnlockFailed));
        assert_eq!(m.state(), LockState::Locked);
    }

    #[test]
    fn wrong_secret_key_fails() {
        let mut m =
            SoftwareKeyManager::open(mgr().envelope().clone(), &[6u8; SECRET_KEY_LEN]).unwrap();
        assert_eq!(m.unlock(b"correct horse"), Err(KeyError::UnlockFailed));
    }

    #[test]
    fn tampered_envelope_fails() {
        let mut env = mgr().envelope().clone();
        env.salt[0] ^= 1;
        let mut m = SoftwareKeyManager::open(env, &SK).unwrap();
        assert_eq!(m.unlock(b"correct horse"), Err(KeyError::UnlockFailed));
    }

    #[test]
    fn rejects_bad_inputs() {
        let p = Argon2idParams::minimum();
        assert!(SoftwareKeyManager::create(b"", &SK, p).is_err());
        assert!(SoftwareKeyManager::create(b"pw", &[1u8; 8], p).is_err());
        let weak = Argon2idParams { memory_kib: 8, ..p };
        assert!(SoftwareKeyManager::create(b"pw", &SK, weak).is_err());
    }

    #[test]
    fn locked_operations_fail() {
        let mut m = mgr();
        let v = vid("v1");
        m.create_vault(&v).unwrap();
        m.lock();
        assert_eq!(m.create_vault(&vid("v2")), Err(KeyError::Locked));
        assert_eq!(m.current_version(&v), Err(KeyError::Locked));
        assert_eq!(m.rotate(&v), Err(KeyError::Locked));
        assert!(m.item_cipher(&v, KeyVersion::new(1).unwrap()).is_err());
    }

    #[test]
    fn vault_lifecycle_and_item_encryption() {
        let mut m = mgr();
        let v = vid("v1");
        assert_eq!(m.create_vault(&v).unwrap().get(), 1);
        assert_eq!(m.create_vault(&v), Err(KeyError::VaultExists));
        let v1 = KeyVersion::new(1).unwrap();
        let sealed = m
            .item_cipher(&v, v1)
            .unwrap()
            .seal(P, b"item1", b"secret")
            .unwrap();

        m.lock();
        m.unlock(b"correct horse").unwrap();
        let out = m
            .item_cipher(&v, v1)
            .unwrap()
            .open(P, b"item1", &sealed)
            .unwrap();
        assert_eq!(out.as_slice(), b"secret");
    }

    #[test]
    fn rotation_keeps_old_versions_readable_and_separate() {
        let mut m = mgr();
        let v = vid("v1");
        m.create_vault(&v).unwrap();
        let (v1, v2) = (KeyVersion::new(1).unwrap(), KeyVersion::new(2).unwrap());
        let old = m.item_cipher(&v, v1).unwrap().seal(P, b"", b"old").unwrap();
        assert_eq!(m.rotate(&v).unwrap(), v2);
        assert_eq!(m.current_version(&v).unwrap(), v2);
        assert_eq!(
            m.item_cipher(&v, v1)
                .unwrap()
                .open(P, b"", &old)
                .unwrap()
                .as_slice(),
            b"old"
        );
        assert!(m.item_cipher(&v, v2).unwrap().open(P, b"", &old).is_err());
        assert_eq!(
            m.item_cipher(&v, KeyVersion::new(3).unwrap()).err(),
            Some(KeyError::UnknownVersion)
        );
    }

    #[test]
    fn vaults_have_independent_keys() {
        let mut m = mgr();
        let (a, b) = (vid("a"), vid("b"));
        m.create_vault(&a).unwrap();
        m.create_vault(&b).unwrap();
        let v1 = KeyVersion::new(1).unwrap();
        let s = m.item_cipher(&a, v1).unwrap().seal(P, b"", b"x").unwrap();
        assert!(m.item_cipher(&b, v1).unwrap().open(P, b"", &s).is_err());
    }

    #[test]
    fn wrapped_key_cannot_be_moved_between_vaults_or_versions() {
        let mut m = mgr();
        let (a, b) = (vid("a"), vid("b"));
        m.create_vault(&a).unwrap();
        m.create_vault(&b).unwrap();
        let v1 = KeyVersion::new(1).unwrap();
        let stolen = m.wrapped_keys(&a).unwrap().to_vec();
        m.vaults.insert(b.clone(), stolen);
        assert!(m.item_cipher(&b, v1).is_err());

        m.rotate(&a).unwrap();
        let mut swapped = m.wrapped_keys(&a).unwrap().to_vec();
        swapped.swap(0, 1);
        m.vaults.insert(a.clone(), swapped);
        assert!(m.item_cipher(&a, v1).is_err());
    }

    #[test]
    fn restore_wrapped_keys_in_new_session() {
        let mut m = mgr();
        let v = vid("v1");
        m.create_vault(&v).unwrap();
        m.rotate(&v).unwrap();
        let v2 = KeyVersion::new(2).unwrap();
        let s = m
            .item_cipher(&v, v2)
            .unwrap()
            .seal(P, b"", b"data")
            .unwrap();
        let wrapped = m.wrapped_keys(&v).unwrap().to_vec();

        let mut m2 = SoftwareKeyManager::open(m.envelope().clone(), &SK).unwrap();
        m2.unlock(b"correct horse").unwrap();
        m2.restore_vault(v.clone(), wrapped).unwrap();
        assert_eq!(m2.current_version(&v).unwrap(), v2);
        assert_eq!(
            m2.item_cipher(&v, v2)
                .unwrap()
                .open(P, b"", &s)
                .unwrap()
                .as_slice(),
            b"data"
        );
        assert!(m2.restore_vault(vid("x"), vec![]).is_err());
    }

    #[test]
    fn debug_does_not_leak() {
        let d = format!("{:?}", mgr());
        assert!(!d.contains("correct") && !d.contains("secret_key"));
    }
}
