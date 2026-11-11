package syncsvc

import (
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"strconv"

	"github.com/itsnavin/securevault/backend/internal/auth"
)

const (
	maxCiphertext  = 1 << 20
	maxBody        = maxCiphertext*4/3 + 4096 // base64 overhead + JSON envelope
	defaultPage    = 100
	maxPage        = 500
	maxFormatValue = 1<<16 - 1
)

// IDs share the Rust core's grammar, which also rules out path tricks.
var idPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)

// Handler serves the sync endpoints. Wrap it with auth.Require.
type Handler struct{ Store Store }

// Register adds routes to mux; every route requires an authenticated user.
func (h *Handler) Register(mux *http.ServeMux, a auth.Authenticator) {
	wrap := func(f http.HandlerFunc) http.Handler { return auth.Require(a, f) }
	mux.Handle("GET /v1/vaults/{vault}/items", wrap(h.changes))
	mux.Handle("PUT /v1/vaults/{vault}/items/{item}", wrap(h.put))
	mux.Handle("DELETE /v1/vaults/{vault}/items/{item}", wrap(h.delete))
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func fail(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// authorize returns the vault ID if the caller may access it. Non-members get
// 404, not 403, so vault IDs cannot be enumerated.
func (h *Handler) authorize(w http.ResponseWriter, r *http.Request, write bool) (string, bool) {
	vault := r.PathValue("vault")
	user, ok := auth.UserID(r.Context())
	if !ok || !idPattern.MatchString(vault) {
		fail(w, http.StatusNotFound, "not found")
		return "", false
	}
	role, err := h.Store.Role(r.Context(), user, vault)
	if err != nil {
		fail(w, http.StatusNotFound, "not found")
		return "", false
	}
	if write && !role.CanWrite() {
		fail(w, http.StatusForbidden, "read-only")
		return "", false
	}
	return vault, true
}

func (h *Handler) storeError(w http.ResponseWriter, err error) {
	var c *ConflictError
	switch {
	case errors.As(err, &c):
		writeJSON(w, http.StatusConflict, map[string]any{"error": "revision conflict", "current_revision": c.Current})
	case errors.Is(err, ErrNotFound):
		fail(w, http.StatusNotFound, "not found")
	default:
		fail(w, http.StatusInternalServerError, "internal error")
	}
}

func (h *Handler) changes(w http.ResponseWriter, r *http.Request) {
	vault, ok := h.authorize(w, r, false)
	if !ok {
		return
	}
	cursor, limit := uint64(0), defaultPage
	if s := r.URL.Query().Get("cursor"); s != "" {
		v, err := strconv.ParseUint(s, 10, 64)
		if err != nil {
			fail(w, http.StatusBadRequest, "invalid cursor")
			return
		}
		cursor = v
	}
	if s := r.URL.Query().Get("limit"); s != "" {
		v, err := strconv.Atoi(s)
		if err != nil || v < 1 || v > maxPage {
			fail(w, http.StatusBadRequest, "invalid limit")
			return
		}
		limit = v
	}
	items, next, more, err := h.Store.Changes(r.Context(), vault, cursor, limit)
	if err != nil {
		h.storeError(w, err)
		return
	}
	if items == nil {
		items = []Item{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items, "cursor": next, "more": more})
}

type putRequest struct {
	BaseRevision  uint64 `json:"base_revision"`
	FormatVersion uint32 `json:"format_version"`
	KeyVersion    uint32 `json:"key_version"`
	Ciphertext    []byte `json:"ciphertext"`
}

func (h *Handler) put(w http.ResponseWriter, r *http.Request) {
	vault, ok := h.authorize(w, r, true)
	if !ok {
		return
	}
	item := r.PathValue("item")
	if !idPattern.MatchString(item) {
		fail(w, http.StatusBadRequest, "invalid item id")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	var req putRequest
	if err := dec.Decode(&req); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			fail(w, http.StatusRequestEntityTooLarge, "payload too large")
			return
		}
		fail(w, http.StatusBadRequest, "invalid json")
		return
	}
	switch {
	case len(req.Ciphertext) == 0 || len(req.Ciphertext) > maxCiphertext:
		fail(w, http.StatusBadRequest, "ciphertext size out of range")
		return
	case req.FormatVersion == 0 || req.FormatVersion > maxFormatValue:
		fail(w, http.StatusBadRequest, "invalid format_version")
		return
	case req.KeyVersion == 0:
		fail(w, http.StatusBadRequest, "invalid key_version")
		return
	}
	saved, err := h.Store.Put(r.Context(), vault, item, PutInput{
		BaseRevision:  req.BaseRevision,
		FormatVersion: uint16(req.FormatVersion),
		KeyVersion:    req.KeyVersion,
		Ciphertext:    req.Ciphertext,
	})
	if err != nil {
		h.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"item_id": saved.ID, "revision": saved.Revision})
}

func (h *Handler) delete(w http.ResponseWriter, r *http.Request) {
	vault, ok := h.authorize(w, r, true)
	if !ok {
		return
	}
	item := r.PathValue("item")
	base, err := strconv.ParseUint(r.URL.Query().Get("base_revision"), 10, 64)
	if !idPattern.MatchString(item) || err != nil {
		fail(w, http.StatusBadRequest, "invalid item id or base_revision")
		return
	}
	saved, err := h.Store.Delete(r.Context(), vault, item, base)
	if err != nil {
		h.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"item_id": saved.ID, "revision": saved.Revision})
}
