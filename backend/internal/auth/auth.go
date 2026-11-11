// Package auth authenticates API requests with bearer session tokens.
//
// Only SHA-256 hashes of tokens are looked up or stored (matching the
// `sessions.token_hash` column), so a leaked store does not reveal usable
// tokens. Issuing sessions (OPAQUE login) is not implemented yet; this
// package only validates tokens that already exist.
package auth

import (
	"context"
	"crypto/sha256"
	"errors"
	"net/http"
	"strings"
	"sync"
)

// TokenHash is the SHA-256 of a bearer token.
type TokenHash [sha256.Size]byte

// HashToken hashes a raw bearer token.
func HashToken(token string) TokenHash { return sha256.Sum256([]byte(token)) }

// ErrUnauthenticated means the token is unknown, expired or revoked.
var ErrUnauthenticated = errors.New("unauthenticated")

// Authenticator resolves a token hash to a user ID.
type Authenticator interface {
	Authenticate(ctx context.Context, h TokenHash) (userID string, err error)
}

// MemoryAuthenticator is an in-memory Authenticator for tests and local dev.
type MemoryAuthenticator struct {
	mu     sync.RWMutex
	tokens map[TokenHash]string
}

// NewMemoryAuthenticator returns an empty authenticator.
func NewMemoryAuthenticator() *MemoryAuthenticator {
	return &MemoryAuthenticator{tokens: map[TokenHash]string{}}
}

// Add registers a raw token for a user.
func (m *MemoryAuthenticator) Add(token, userID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.tokens[HashToken(token)] = userID
}

// Revoke removes a raw token.
func (m *MemoryAuthenticator) Revoke(token string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.tokens, HashToken(token))
}

// Authenticate implements Authenticator.
func (m *MemoryAuthenticator) Authenticate(_ context.Context, h TokenHash) (string, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if u, ok := m.tokens[h]; ok {
		return u, nil
	}
	return "", ErrUnauthenticated
}

type ctxKey struct{}

// UserID returns the authenticated user from the request context.
func UserID(ctx context.Context) (string, bool) {
	u, ok := ctx.Value(ctxKey{}).(string)
	return u, ok && u != ""
}

// Require rejects requests without a valid bearer token with 401.
func Require(a Authenticator, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		const prefix = "Bearer "
		h := r.Header.Get("Authorization")
		if !strings.HasPrefix(h, prefix) || len(h) == len(prefix) {
			deny(w)
			return
		}
		user, err := a.Authenticate(r.Context(), HashToken(h[len(prefix):]))
		if err != nil {
			deny(w)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, user)))
	})
}

func deny(w http.ResponseWriter) {
	w.Header().Set("WWW-Authenticate", "Bearer")
	http.Error(w, "unauthorized", http.StatusUnauthorized)
}
