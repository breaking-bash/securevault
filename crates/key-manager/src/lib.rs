//! Key manager interface.
//!
//! Defines lifecycle contracts (lock/unlock, rotation, versioning).
//! **No implementation and no key storage exists yet.** Recovery and
//! shared-vault key distribution require a reviewed protocol first.

use shared_types::{KeyVersion, VaultId};

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

    /// Unlocks using a user secret. The secret is never sent to a backend.
    fn unlock(&mut self, user_secret: &[u8]) -> Result<(), KeyError>;

    /// Locks and wipes in-memory key material.
    fn lock(&mut self);

    /// Current key version for a vault.
    fn current_version(&self, vault: &VaultId) -> Result<KeyVersion, KeyError>;

    /// Rotates the vault key, returning the new version.
    fn rotate(&mut self, vault: &VaultId) -> Result<KeyVersion, KeyError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Fail-closed stub; performs no key handling.
    struct Unavailable;

    impl KeyManager for Unavailable {
        fn state(&self) -> LockState {
            LockState::Locked
        }
        fn unlock(&mut self, _: &[u8]) -> Result<(), KeyError> {
            Err(KeyError::NotImplemented)
        }
        fn lock(&mut self) {}
        fn current_version(&self, _: &VaultId) -> Result<KeyVersion, KeyError> {
            Err(KeyError::Locked)
        }
        fn rotate(&mut self, _: &VaultId) -> Result<KeyVersion, KeyError> {
            Err(KeyError::Locked)
        }
    }

    #[test]
    fn stub_stays_locked() {
        let mut k: Box<dyn KeyManager> = Box::new(Unavailable);
        assert_eq!(k.state(), LockState::Locked);
        assert_eq!(k.unlock(b"x"), Err(KeyError::NotImplemented));
        let v = VaultId::new("v1").unwrap();
        assert_eq!(k.rotate(&v), Err(KeyError::Locked));
    }
}
