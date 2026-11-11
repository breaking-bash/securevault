// Package syncsvc implements encrypted-item sync: optimistic-concurrency
// writes, tombstone deletes and cursor-based change feeds.
//
// The server only ever sees ciphertext and public metadata. Revisions follow
// the same rules as the Rust sync-engine: a write must name the revision it
// is based on (0 for a new item) and is rejected with a conflict otherwise,
// so concurrent edits are never silently overwritten.
package syncsvc

import (
	"context"
	"errors"
	"sort"
	"sync"
)

// Role is a user's role in a vault.
type Role string

// Vault roles.
const (
	RoleOwner  Role = "owner"
	RoleEditor Role = "editor"
	RoleViewer Role = "viewer"
)

// CanWrite reports whether the role may modify items.
func (r Role) CanWrite() bool { return r == RoleOwner || r == RoleEditor }

// Errors returned by stores.
var (
	ErrNotFound = errors.New("not found")
)

// ConflictError is returned when the base revision is stale.
type ConflictError struct{ Current uint64 }

func (e *ConflictError) Error() string { return "revision conflict" }

// Item is one encrypted item version.
type Item struct {
	ID            string `json:"item_id"`
	Revision      uint64 `json:"revision"`
	FormatVersion uint16 `json:"format_version"`
	KeyVersion    uint32 `json:"key_version"`
	Deleted       bool   `json:"deleted"`
	Ciphertext    []byte `json:"ciphertext,omitempty"`
}

// PutInput is a client write.
type PutInput struct {
	BaseRevision  uint64
	FormatVersion uint16
	KeyVersion    uint32
	Ciphertext    []byte
}

// Store persists items. Implementations must make Put/Delete atomic with
// respect to the revision check.
type Store interface {
	// Role returns the user's role in the vault, or ErrNotFound.
	Role(ctx context.Context, userID, vaultID string) (Role, error)
	Put(ctx context.Context, vaultID, itemID string, in PutInput) (Item, error)
	Delete(ctx context.Context, vaultID, itemID string, baseRevision uint64) (Item, error)
	// Changes returns items changed after cursor (latest state each), the new
	// cursor, and whether more remain.
	Changes(ctx context.Context, vaultID string, cursor uint64, limit int) ([]Item, uint64, bool, error)
}

type vaultState struct {
	items map[string]Item
	log   []string // item ID per operation; cursor = index+1
}

// MemoryStore is an in-memory Store for tests and local development.
type MemoryStore struct {
	mu     sync.Mutex
	roles  map[[2]string]Role
	vaults map[string]*vaultState
}

// NewMemoryStore returns an empty store.
func NewMemoryStore() *MemoryStore {
	return &MemoryStore{roles: map[[2]string]Role{}, vaults: map[string]*vaultState{}}
}

// Grant gives a user a role in a vault, creating the vault if needed.
func (m *MemoryStore) Grant(userID, vaultID string, role Role) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.roles[[2]string{userID, vaultID}] = role
	if m.vaults[vaultID] == nil {
		m.vaults[vaultID] = &vaultState{items: map[string]Item{}}
	}
}

// Role implements Store.
func (m *MemoryStore) Role(_ context.Context, userID, vaultID string) (Role, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r, ok := m.roles[[2]string{userID, vaultID}]; ok {
		return r, nil
	}
	return "", ErrNotFound
}

func (m *MemoryStore) vault(id string) (*vaultState, error) {
	v := m.vaults[id]
	if v == nil {
		return nil, ErrNotFound
	}
	return v, nil
}

// Put implements Store.
func (m *MemoryStore) Put(_ context.Context, vaultID, itemID string, in PutInput) (Item, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	v, err := m.vault(vaultID)
	if err != nil {
		return Item{}, err
	}
	cur := v.items[itemID]
	if in.BaseRevision != cur.Revision {
		return Item{}, &ConflictError{Current: cur.Revision}
	}
	next := Item{
		ID:            itemID,
		Revision:      cur.Revision + 1,
		FormatVersion: in.FormatVersion,
		KeyVersion:    in.KeyVersion,
		Ciphertext:    append([]byte(nil), in.Ciphertext...),
	}
	v.items[itemID] = next
	v.log = append(v.log, itemID)
	return next, nil
}

// Delete implements Store.
func (m *MemoryStore) Delete(_ context.Context, vaultID, itemID string, base uint64) (Item, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	v, err := m.vault(vaultID)
	if err != nil {
		return Item{}, err
	}
	cur, ok := v.items[itemID]
	if !ok || cur.Deleted && cur.Revision == base {
		return Item{}, ErrNotFound
	}
	if base != cur.Revision {
		return Item{}, &ConflictError{Current: cur.Revision}
	}
	next := Item{ID: itemID, Revision: cur.Revision + 1, FormatVersion: cur.FormatVersion, KeyVersion: cur.KeyVersion, Deleted: true}
	v.items[itemID] = next
	v.log = append(v.log, itemID)
	return next, nil
}

// Changes implements Store.
func (m *MemoryStore) Changes(_ context.Context, vaultID string, cursor uint64, limit int) ([]Item, uint64, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	v, err := m.vault(vaultID)
	if err != nil {
		return nil, 0, false, err
	}
	if cursor > uint64(len(v.log)) {
		cursor = uint64(len(v.log))
	}
	seen := map[string]bool{}
	var out []Item
	pos := cursor
	for pos < uint64(len(v.log)) {
		id := v.log[pos]
		if !seen[id] {
			if len(out) == limit {
				break
			}
			seen[id] = true
			out = append(out, v.items[id])
		}
		pos++
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, pos, pos < uint64(len(v.log)), nil
}
