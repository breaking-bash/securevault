// Package httpapi wires the HTTP router. Phase 1 exposes only a health probe.
package httpapi

import (
	"encoding/json"
	"net/http"
)

// NewRouter returns the API handler.
func NewRouter() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", health)
	return mux
}

func health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
