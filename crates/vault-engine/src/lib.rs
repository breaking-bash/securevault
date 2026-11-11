//! Vault engine.
//!
//! Seals item payloads with per-vault keys from a [`KeyManager`] before they
//! reach an [`ItemStore`]. Each ciphertext is bound to its vault and item ID
//! through the AEAD associated data, so a stored blob moved to another slot
//! fails authentication. Pending independent cryptographic review.

use std::collections::BTreeMap;

use crypto_engine::{CryptoError, KeyPurpose, Sealed};
use key_manager::{KeyError, KeyManager, LockState};
use shared_types::{ItemId, VaultId};
use zeroize::Zeroizing;

/// Errors returned by vault-engine implementations.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum VaultError {
    /// The vault is locked.
    #[error("vault is locked")]
    Locked,
    /// Item not found.
    #[error("item not found")]
    NotFound,
    /// The persistence layer failed.
    #[error("storage failure: {0}")]
    Storage(String),
    /// Key manager failure.
    #[error(transparent)]
    Key(KeyError),
    /// Stored data could not be authenticated or parsed.
    #[error("stored item is corrupt or tampered")]
    Corrupt,
}

impl From<KeyError> for VaultError {
    fn from(e: KeyError) -> Self {
        match e {
            KeyError::Locked => VaultError::Locked,
            other => VaultError::Key(other),
        }
    }
}

/// Vault item operations. Implementations must encrypt before persisting.
pub trait VaultEngine {
    /// Stores or replaces an item.
    fn put_item(
        &mut self,
        vault: &VaultId,
        item: &ItemId,
        payload: &[u8],
    ) -> Result<(), VaultError>;

    /// Retrieves an item. The plaintext is zeroized on drop.
    fn get_item(&self, vault: &VaultId, item: &ItemId) -> Result<Zeroizing<Vec<u8>>, VaultError>;

    /// Deletes an item.
    fn delete_item(&mut self, vault: &VaultId, item: &ItemId) -> Result<(), VaultError>;

    /// Lists item identifiers in a vault.
    fn list_items(&self, vault: &VaultId) -> Result<Vec<ItemId>, VaultError>;
}

/// Persistence for sealed (already encrypted) item blobs.
pub trait ItemStore {
    /// Stores a blob, replacing any existing one.
    fn put(&mut self, vault: &VaultId, item: &ItemId, blob: Vec<u8>) -> Result<(), VaultError>;
    /// Loads a blob.
    fn get(&self, vault: &VaultId, item: &ItemId) -> Result<Option<Vec<u8>>, VaultError>;
    /// Removes a blob; returns whether it existed.
    fn delete(&mut self, vault: &VaultId, item: &ItemId) -> Result<bool, VaultError>;
    /// Lists item IDs of a vault.
    fn list(&self, vault: &VaultId) -> Result<Vec<ItemId>, VaultError>;
}

/// Volatile [`ItemStore`] for tests and ephemeral sessions.
#[derive(Debug, Default)]
pub struct MemoryStore {
    blobs: BTreeMap<(String, String), Vec<u8>>,
}

impl ItemStore for MemoryStore {
    fn put(&mut self, vault: &VaultId, item: &ItemId, blob: Vec<u8>) -> Result<(), VaultError> {
        self.blobs
            .insert((vault.to_string(), item.to_string()), blob);
        Ok(())
    }

    fn get(&self, vault: &VaultId, item: &ItemId) -> Result<Option<Vec<u8>>, VaultError> {
        Ok(self
            .blobs
            .get(&(vault.to_string(), item.to_string()))
            .cloned())
    }

    fn delete(&mut self, vault: &VaultId, item: &ItemId) -> Result<bool, VaultError> {
        Ok(self
            .blobs
            .remove(&(vault.to_string(), item.to_string()))
            .is_some())
    }

    fn list(&self, vault: &VaultId) -> Result<Vec<ItemId>, VaultError> {
        self.blobs
            .keys()
            .filter(|(v, _)| v == vault.as_str())
            .map(|(_, i)| ItemId::new(i.clone()).map_err(|_| VaultError::Corrupt))
            .collect()
    }
}

/// Binds ciphertext to its location. IDs cannot contain NUL, so this is
/// unambiguous.
fn item_aad(vault: &VaultId, item: &ItemId) -> Vec<u8> {
    let mut aad = Vec::with_capacity(vault.as_str().len() + item.as_str().len() + 1);
    aad.extend_from_slice(vault.as_str().as_bytes());
    aad.push(0);
    aad.extend_from_slice(item.as_str().as_bytes());
    aad
}

/// Vault engine that encrypts items with keys from a [`KeyManager`].
pub struct SealedVaultEngine<K: KeyManager, S: ItemStore> {
    keys: K,
    store: S,
}

impl<K: KeyManager, S: ItemStore> SealedVaultEngine<K, S> {
    /// Creates an engine over a key manager and a store.
    pub fn new(keys: K, store: S) -> Self {
        Self { keys, store }
    }

    /// Access to the key manager (for unlock/lock/rotate).
    pub fn keys(&self) -> &K {
        &self.keys
    }

    /// Mutable access to the key manager.
    pub fn keys_mut(&mut self) -> &mut K {
        &mut self.keys
    }

    /// Access to the underlying store.
    pub fn store(&self) -> &S {
        &self.store
    }

    /// Mutable access to the underlying store.
    pub fn store_mut(&mut self) -> &mut S {
        &mut self.store
    }

    /// Re-encrypts every item in `vault` under the current key version.
    /// Call after [`KeyManager::rotate`]. Returns the number re-sealed.
    pub fn reseal_vault(&mut self, vault: &VaultId) -> Result<usize, VaultError> {
        if self.keys.state() == LockState::Locked {
            return Err(VaultError::Locked);
        }
        let current = self.keys.current_version(vault)?;
        let mut count = 0;
        for item in self.store.list(vault)? {
            let blob = self.store.get(vault, &item)?.ok_or(VaultError::NotFound)?;
            let sealed = Sealed::from_wire(&blob).map_err(|_| VaultError::Corrupt)?;
            if sealed.key_version == current {
                continue;
            }
            let plain = self.get_item(vault, &item)?;
            self.put_item(vault, &item, &plain)?;
            count += 1;
        }
        Ok(count)
    }
}

impl<K: KeyManager, S: ItemStore> VaultEngine for SealedVaultEngine<K, S> {
    fn put_item(
        &mut self,
        vault: &VaultId,
        item: &ItemId,
        payload: &[u8],
    ) -> Result<(), VaultError> {
        let version = self.keys.current_version(vault)?;
        let cipher = self.keys.item_cipher(vault, version)?;
        let sealed = cipher
            .seal(KeyPurpose::ItemEncryption, &item_aad(vault, item), payload)
            .map_err(KeyError::from)?;
        self.store.put(vault, item, sealed.to_wire())
    }

    fn get_item(&self, vault: &VaultId, item: &ItemId) -> Result<Zeroizing<Vec<u8>>, VaultError> {
        if self.keys.state() == LockState::Locked {
            return Err(VaultError::Locked);
        }
        let blob = self.store.get(vault, item)?.ok_or(VaultError::NotFound)?;
        let sealed = Sealed::from_wire(&blob).map_err(|_| VaultError::Corrupt)?;
        let cipher = self.keys.item_cipher(vault, sealed.key_version)?;
        cipher
            .open(KeyPurpose::ItemEncryption, &item_aad(vault, item), &sealed)
            .map_err(|e| match e {
                CryptoError::AuthenticationFailed => VaultError::Corrupt,
                other => VaultError::Key(KeyError::Crypto(other)),
            })
    }

    fn delete_item(&mut self, vault: &VaultId, item: &ItemId) -> Result<(), VaultError> {
        if self.keys.state() == LockState::Locked {
            return Err(VaultError::Locked);
        }
        if self.store.delete(vault, item)? {
            Ok(())
        } else {
            Err(VaultError::NotFound)
        }
    }

    fn list_items(&self, vault: &VaultId) -> Result<Vec<ItemId>, VaultError> {
        if self.keys.state() == LockState::Locked {
            return Err(VaultError::Locked);
        }
        self.store.list(vault)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crypto_engine::Argon2idParams;
    use key_manager::{SoftwareKeyManager, SECRET_KEY_LEN};

    const PW: &[u8] = b"correct horse";
    const SK: [u8; SECRET_KEY_LEN] = [9u8; SECRET_KEY_LEN];

    fn vid(s: &str) -> VaultId {
        VaultId::new(s).unwrap()
    }
    fn iid(s: &str) -> ItemId {
        ItemId::new(s).unwrap()
    }

    fn engine() -> SealedVaultEngine<SoftwareKeyManager, MemoryStore> {
        let mut km = SoftwareKeyManager::create(PW, &SK, Argon2idParams::minimum()).unwrap();
        km.unlock(PW).unwrap();
        km.create_vault(&vid("v1")).unwrap();
        km.create_vault(&vid("v2")).unwrap();
        SealedVaultEngine::new(km, MemoryStore::default())
    }

    #[test]
    fn put_get_roundtrip_and_ciphertext_is_opaque() {
        let mut e = engine();
        e.put_item(&vid("v1"), &iid("i1"), b"hunter2-secret")
            .unwrap();
        assert_eq!(
            &**e.get_item(&vid("v1"), &iid("i1")).unwrap(),
            b"hunter2-secret"
        );
        let blob = e.store().get(&vid("v1"), &iid("i1")).unwrap().unwrap();
        assert!(!blob.windows(7).any(|w| w == b"hunter2"));
    }

    #[test]
    fn same_plaintext_yields_distinct_ciphertexts() {
        let mut e = engine();
        e.put_item(&vid("v1"), &iid("a"), b"same").unwrap();
        e.put_item(&vid("v1"), &iid("b"), b"same").unwrap();
        let a = e.store().get(&vid("v1"), &iid("a")).unwrap().unwrap();
        let b = e.store().get(&vid("v1"), &iid("b")).unwrap().unwrap();
        assert_ne!(a, b);
    }

    #[test]
    fn blob_moved_to_other_item_or_vault_fails() {
        let mut e = engine();
        e.put_item(&vid("v1"), &iid("a"), b"secret").unwrap();
        let blob = e.store().get(&vid("v1"), &iid("a")).unwrap().unwrap();
        e.store_mut()
            .put(&vid("v1"), &iid("other"), blob.clone())
            .unwrap();
        e.store_mut().put(&vid("v2"), &iid("a"), blob).unwrap();
        assert_eq!(
            e.get_item(&vid("v1"), &iid("other")),
            Err(VaultError::Corrupt)
        );
        assert_eq!(e.get_item(&vid("v2"), &iid("a")), Err(VaultError::Corrupt));
    }

    #[test]
    fn tampered_blob_is_rejected() {
        let mut e = engine();
        e.put_item(&vid("v1"), &iid("a"), b"secret").unwrap();
        let mut blob = e.store().get(&vid("v1"), &iid("a")).unwrap().unwrap();
        let last = blob.len() - 1;
        blob[last] ^= 1;
        e.store_mut().put(&vid("v1"), &iid("a"), blob).unwrap();
        assert_eq!(e.get_item(&vid("v1"), &iid("a")), Err(VaultError::Corrupt));
    }
    #[test]
    fn locked_engine_refuses_everything() {
        let mut e = engine();
        e.put_item(&vid("v1"), &iid("a"), b"x").unwrap();
        e.keys_mut().lock();
        assert_eq!(e.get_item(&vid("v1"), &iid("a")), Err(VaultError::Locked));
        assert_eq!(
            e.put_item(&vid("v1"), &iid("a"), b"y"),
            Err(VaultError::Locked)
        );
        assert_eq!(e.list_items(&vid("v1")), Err(VaultError::Locked));
        assert_eq!(
            e.delete_item(&vid("v1"), &iid("a")),
            Err(VaultError::Locked)
        );
    }

    #[test]
    fn list_delete_and_not_found() {
        let mut e = engine();
        e.put_item(&vid("v1"), &iid("a"), b"1").unwrap();
        e.put_item(&vid("v1"), &iid("b"), b"2").unwrap();
        e.put_item(&vid("v2"), &iid("c"), b"3").unwrap();
        assert_eq!(e.list_items(&vid("v1")).unwrap(), vec![iid("a"), iid("b")]);
        e.delete_item(&vid("v1"), &iid("a")).unwrap();
        assert_eq!(e.get_item(&vid("v1"), &iid("a")), Err(VaultError::NotFound));
        assert_eq!(
            e.delete_item(&vid("v1"), &iid("a")),
            Err(VaultError::NotFound)
        );
    }

    #[test]
    fn rotation_keeps_old_items_readable_and_reseal_upgrades() {
        let mut e = engine();
        e.put_item(&vid("v1"), &iid("old"), b"old-data").unwrap();
        let v2 = e.keys_mut().rotate(&vid("v1")).unwrap();
        assert_eq!(&**e.get_item(&vid("v1"), &iid("old")).unwrap(), b"old-data");
        e.put_item(&vid("v1"), &iid("new"), b"new-data").unwrap();
        let ver = |e: &SealedVaultEngine<_, MemoryStore>, i: &str| {
            let b = e.store().get(&vid("v1"), &iid(i)).unwrap().unwrap();
            Sealed::from_wire(&b).unwrap().key_version
        };
        assert_ne!(ver(&e, "old"), v2);
        assert_eq!(ver(&e, "new"), v2);
        assert_eq!(e.reseal_vault(&vid("v1")).unwrap(), 1);
        assert_eq!(ver(&e, "old"), v2);
        assert_eq!(&**e.get_item(&vid("v1"), &iid("old")).unwrap(), b"old-data");
    }

    #[test]
    fn unknown_vault_is_an_error() {
        let mut e = engine();
        assert!(e.put_item(&vid("nope"), &iid("a"), b"x").is_err());
    }
}
