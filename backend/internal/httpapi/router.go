// Package httpapi wires the HTTP router: a health probe and, when an\n// authenticator and store are supplied, the encrypted-item sync API.
package httpapi

import (
	"encoding/json"
	"net/http"

	"github.com/itsnavin/securevault/backend/internal/auth"
	syncsvc "github.com/itsnavin/securevault/backend/internal/sync"
)

// NewRouter returns the API handler with only the health probe.
func NewRouter() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health)
	return mux
}

// NewRouterWithSync returns the API handler including authenticated sync.
func NewRouterWithSync(a auth.Authenticator, s syncsvc.Store) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health)
	(&syncsvc.Handler{Store: s}).Register(mux, a)
	return mux
}

func health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
