//! Sync planning over item metadata.
//!
//! Operates only on non-secret metadata (IDs, revisions, device, tombstone
//! flag, ciphertext digest-free). The server and this crate never see
//! plaintext. Conflict rule: the higher revision wins; equal revisions with
//! different content hashes are reported as conflicts and never silently
//! overwritten. Transport authentication (OPAQUE session) is out of scope here.

use std::collections::BTreeMap;

use shared_types::{DeviceId, ItemId, VaultId};

/// Metadata describing one version of an item.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ItemMeta {
    /// Vault the item belongs to.
    pub vault: VaultId,
    /// Item identifier.
    pub item: ItemId,
    /// Monotonic revision, incremented on every change.
    pub revision: u64,
    /// Device that produced this revision.
    pub device: DeviceId,
    /// True if the item was deleted (tombstone).
    pub deleted: bool,
    /// Fingerprint of the sealed blob, used to detect divergent equal revisions.
    pub fingerprint: [u8; 32],
}

type Key = (String, String);

fn key(m: &ItemMeta) -> Key {
    (m.vault.to_string(), m.item.to_string())
}

/// Outcome of comparing two replicas.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct SyncPlan {
    /// Items to upload to the remote (local is newer or remote is missing).
    pub push: Vec<(VaultId, ItemId)>,
    /// Items to download (remote is newer or local is missing).
    pub pull: Vec<(VaultId, ItemId)>,
    /// Same revision but different content; needs user/merge resolution.
    pub conflicts: Vec<(VaultId, ItemId)>,
}

/// Computes what must move in each direction to converge `local` and `remote`.
pub fn plan(local: &[ItemMeta], remote: &[ItemMeta]) -> SyncPlan {
    let l: BTreeMap<Key, &ItemMeta> = local.iter().map(|m| (key(m), m)).collect();
    let r: BTreeMap<Key, &ItemMeta> = remote.iter().map(|m| (key(m), m)).collect();
    let mut out = SyncPlan::default();

    for (k, lm) in &l {
        let id = (lm.vault.clone(), lm.item.clone());
        match r.get(k) {
            None => out.push.push(id),
            Some(rm) if lm.revision > rm.revision => out.push.push(id),
            Some(rm) if lm.revision < rm.revision => out.pull.push(id),
            Some(rm) if lm.fingerprint != rm.fingerprint || lm.deleted != rm.deleted => {
                out.conflicts.push(id)
            }
            Some(_) => {}
        }
    }
    for (k, rm) in &r {
        if !l.contains_key(k) {
            out.pull.push((rm.vault.clone(), rm.item.clone()));
        }
    }
    out
}

/// Returns the next revision for a local edit based on the previous one.
pub fn next_revision(previous: Option<u64>) -> u64 {
    previous.map_or(1, |r| r.saturating_add(1))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(item: &str, rev: u64, fp: u8) -> ItemMeta {
        ItemMeta {
            vault: VaultId::new("v").unwrap(),
            item: ItemId::new(item).unwrap(),
            revision: rev,
            device: DeviceId::new("d1").unwrap(),
            deleted: false,
            fingerprint: [fp; 32],
        }
    }
    fn id(item: &str) -> (VaultId, ItemId) {
        (VaultId::new("v").unwrap(), ItemId::new(item).unwrap())
    }

    #[test]
    fn identical_replicas_need_nothing() {
        let a = vec![m("a", 2, 1)];
        assert_eq!(plan(&a, &a.clone()), SyncPlan::default());
    }

    #[test]
    fn missing_and_newer_items_move_in_the_right_direction() {
        let local = vec![
            m("only-local", 1, 1),
            m("newer-local", 3, 1),
            m("older", 1, 1),
        ];
        let remote = vec![
            m("only-remote", 1, 2),
            m("newer-local", 2, 1),
            m("older", 4, 9),
        ];
        let p = plan(&local, &remote);
        assert_eq!(p.push, vec![id("newer-local"), id("only-local")]);
        assert_eq!(p.pull, vec![id("older"), id("only-remote")]);
        assert!(p.conflicts.is_empty());
    }

    #[test]
    fn same_revision_different_content_is_a_conflict() {
        let p = plan(&[m("a", 2, 1)], &[m("a", 2, 2)]);
        assert_eq!(p.conflicts, vec![id("a")]);
        assert!(p.push.is_empty() && p.pull.is_empty());
    }

    #[test]
    fn tombstone_mismatch_at_same_revision_conflicts() {
        let mut deleted = m("a", 2, 1);
        deleted.deleted = true;
        assert_eq!(plan(&[deleted], &[m("a", 2, 1)]).conflicts, vec![id("a")]);
    }

    #[test]
    fn revisions_increment_and_saturate() {
        assert_eq!(next_revision(None), 1);
        assert_eq!(next_revision(Some(4)), 5);
        assert_eq!(next_revision(Some(u64::MAX)), u64::MAX);
    }
}
