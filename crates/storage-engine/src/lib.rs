//! Durable on-disk [`ItemStore`].
//!
//! Stores one file per item at `<root>/<vault>/<item>.svi`. Blobs are
//! persisted exactly as given (they are already sealed by the vault engine);
//! this crate never sees plaintext. Writes are atomic: data goes to a
//! temporary file, is flushed to disk, then renamed over the target, so a
//! crash leaves either the old or the new blob, never a partial one.
//!
//! Identifiers are validated (`[A-Za-z0-9_-]`) by `shared-types`, which rules
//! out path traversal.

use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};

use shared_types::{ItemId, VaultId};
use vault_engine::{ItemStore, VaultError};

const EXT: &str = "svi";
const TMP_EXT: &str = "tmp";

fn io_err(e: std::io::Error) -> VaultError {
    VaultError::Storage(e.kind().to_string())
}

/// File-backed item store.
#[derive(Debug, Clone)]
pub struct FileStore {
    root: PathBuf,
}

impl FileStore {
    /// Opens (creating if necessary) a store rooted at `root`.
    pub fn open(root: impl Into<PathBuf>) -> Result<Self, VaultError> {
        let root = root.into();
        fs::create_dir_all(&root).map_err(io_err)?;
        Ok(Self { root })
    }

    /// Root directory of the store.
    pub fn root(&self) -> &Path {
        &self.root
    }

    fn vault_dir(&self, vault: &VaultId) -> PathBuf {
        self.root.join(vault.as_str())
    }

    fn item_path(&self, vault: &VaultId, item: &ItemId) -> PathBuf {
        self.vault_dir(vault)
            .join(format!("{}.{EXT}", item.as_str()))
    }
}

impl ItemStore for FileStore {
    fn put(&mut self, vault: &VaultId, item: &ItemId, blob: Vec<u8>) -> Result<(), VaultError> {
        let dir = self.vault_dir(vault);
        fs::create_dir_all(&dir).map_err(io_err)?;
        let target = self.item_path(vault, item);
        let tmp = target.with_extension(TMP_EXT);
        {
            let mut f = File::create(&tmp).map_err(io_err)?;
            f.write_all(&blob).map_err(io_err)?;
            f.sync_all().map_err(io_err)?;
        }
        fs::rename(&tmp, &target).map_err(|e| {
            let _ = fs::remove_file(&tmp);
            io_err(e)
        })
    }

    fn get(&self, vault: &VaultId, item: &ItemId) -> Result<Option<Vec<u8>>, VaultError> {
        match fs::read(self.item_path(vault, item)) {
            Ok(b) => Ok(Some(b)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(io_err(e)),
        }
    }

    fn delete(&mut self, vault: &VaultId, item: &ItemId) -> Result<bool, VaultError> {
        match fs::remove_file(self.item_path(vault, item)) {
            Ok(()) => Ok(true),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(io_err(e)),
        }
    }

    fn list(&self, vault: &VaultId) -> Result<Vec<ItemId>, VaultError> {
        let entries = match fs::read_dir(self.vault_dir(vault)) {
            Ok(r) => r,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(io_err(e)),
        };
        let mut ids = Vec::new();
        for entry in entries {
            let path = entry.map_err(io_err)?.path();
            if path.extension().and_then(|e| e.to_str()) != Some(EXT) {
                continue;
            }
            if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                ids.push(ItemId::new(stem).map_err(|_| VaultError::Corrupt)?);
            }
        }
        ids.sort_by(|a, b| a.as_str().cmp(b.as_str()));
        Ok(ids)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vid(s: &str) -> VaultId {
        VaultId::new(s).unwrap()
    }
    fn iid(s: &str) -> ItemId {
        ItemId::new(s).unwrap()
    }

    #[test]
    fn put_get_delete_list() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = FileStore::open(dir.path()).unwrap();
        assert_eq!(s.get(&vid("v"), &iid("a")).unwrap(), None);
        assert!(s.list(&vid("v")).unwrap().is_empty());
        s.put(&vid("v"), &iid("b"), vec![2]).unwrap();
        s.put(&vid("v"), &iid("a"), vec![1]).unwrap();
        s.put(&vid("w"), &iid("z"), vec![9]).unwrap();
        assert_eq!(s.get(&vid("v"), &iid("a")).unwrap(), Some(vec![1]));
        assert_eq!(s.list(&vid("v")).unwrap(), vec![iid("a"), iid("b")]);
        assert!(s.delete(&vid("v"), &iid("a")).unwrap());
        assert!(!s.delete(&vid("v"), &iid("a")).unwrap());
        assert_eq!(s.list(&vid("v")).unwrap(), vec![iid("b")]);
    }

    #[test]
    fn overwrite_is_atomic_and_leaves_no_temp_files() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = FileStore::open(dir.path()).unwrap();
        s.put(&vid("v"), &iid("a"), vec![1; 1000]).unwrap();
        s.put(&vid("v"), &iid("a"), vec![2; 10]).unwrap();
        assert_eq!(s.get(&vid("v"), &iid("a")).unwrap(), Some(vec![2; 10]));
        let leftovers = fs::read_dir(dir.path().join("v"))
            .unwrap()
            .filter(|e| {
                e.as_ref()
                    .unwrap()
                    .path()
                    .extension()
                    .and_then(|x| x.to_str())
                    == Some(TMP_EXT)
            })
            .count();
        assert_eq!(leftovers, 0);
    }

    #[test]
    fn persists_across_reopen() {
        let dir = tempfile::tempdir().unwrap();
        FileStore::open(dir.path())
            .unwrap()
            .put(&vid("v"), &iid("a"), vec![7])
            .unwrap();
        let s = FileStore::open(dir.path()).unwrap();
        assert_eq!(s.get(&vid("v"), &iid("a")).unwrap(), Some(vec![7]));
    }

    #[test]
    fn stray_files_are_ignored_and_ids_cannot_escape_root() {
        let dir = tempfile::tempdir().unwrap();
        let mut s = FileStore::open(dir.path()).unwrap();
        s.put(&vid("v"), &iid("a"), vec![1]).unwrap();
        fs::write(dir.path().join("v").join("junk.txt"), b"x").unwrap();
        assert_eq!(s.list(&vid("v")).unwrap(), vec![iid("a")]);
        assert!(ItemId::new("../evil").is_err());
        assert!(VaultId::new("..").is_err());
    }
}
