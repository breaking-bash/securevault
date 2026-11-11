//! Vault engine interface.
//!
//! Defines how vault items are stored and retrieved. **No implementation
//! exists yet**; items are opaque plaintext bytes at this boundary and the
//! caller must not log them.

use shared_types::{ItemId, VaultId};

/// Errors returned by vault-engine implementations.
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum VaultError {
    /// The vault is locked.
    #[error("vault is locked")]
    Locked,
    /// Item not found.
    #[error("item not found")]
    NotFound,
    /// No implementation is available.
    #[error("vault engine not implemented")]
    NotImplemented,
    /// Key manager failure.
    #[error(transparent)]
    Key(#[from] key_manager::KeyError),
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

    /// Retrieves an item.
    fn get_item(&self, vault: &VaultId, item: &ItemId) -> Result<Vec<u8>, VaultError>;

    /// Deletes an item.
    fn delete_item(&mut self, vault: &VaultId, item: &ItemId) -> Result<(), VaultError>;

    /// Lists item identifiers in a vault.
    fn list_items(&self, vault: &VaultId) -> Result<Vec<ItemId>, VaultError>;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Fail-closed stub; stores nothing.
    struct Unavailable;

    impl VaultEngine for Unavailable {
        fn put_item(&mut self, _: &VaultId, _: &ItemId, _: &[u8]) -> Result<(), VaultError> {
            Err(VaultError::NotImplemented)
        }
        fn get_item(&self, _: &VaultId, _: &ItemId) -> Result<Vec<u8>, VaultError> {
            Err(VaultError::Locked)
        }
        fn delete_item(&mut self, _: &VaultId, _: &ItemId) -> Result<(), VaultError> {
            Err(VaultError::Locked)
        }
        fn list_items(&self, _: &VaultId) -> Result<Vec<ItemId>, VaultError> {
            Err(VaultError::Locked)
        }
    }

    #[test]
    fn stub_fails_closed() {
        let mut e: Box<dyn VaultEngine> = Box::new(Unavailable);
        let v = VaultId::new("v1").unwrap();
        let i = ItemId::new("i1").unwrap();
        assert_eq!(e.put_item(&v, &i, b"x"), Err(VaultError::NotImplemented));
        assert_eq!(e.get_item(&v, &i), Err(VaultError::Locked));
    }
}
