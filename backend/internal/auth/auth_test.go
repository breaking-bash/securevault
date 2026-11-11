package auth

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func serve(a Authenticator, header string) (int, string) {
	var got string
	h := Require(a, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got, _ = UserID(r.Context())
	}))
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	if header != "" {
		req.Header.Set("Authorization", header)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec.Code, got
}

func TestRequire(t *testing.T) {
	a := NewMemoryAuthenticator()
	a.Add("good-token", "user-1")

	if code, user := serve(a, "Bearer good-token"); code != 200 || user != "user-1" {
		t.Fatalf("valid token: %d %q", code, user)
	}
	for _, h := range []string{"", "Bearer ", "Bearer nope", "Basic good-token", "good-token", "bearer good-token"} {
		if code, _ := serve(a, h); code != http.StatusUnauthorized {
			t.Errorf("header %q: got %d, want 401", h, code)
		}
	}
	a.Revoke("good-token")
	if code, _ := serve(a, "Bearer good-token"); code != http.StatusUnauthorized {
		t.Fatalf("revoked token accepted: %d", code)
	}
}

func TestUnauthorizedSetsChallenge(t *testing.T) {
	h := Require(NewMemoryAuthenticator(), http.NotFoundHandler())
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if rec.Header().Get("WWW-Authenticate") != "Bearer" {
		t.Fatal("missing WWW-Authenticate")
	}
}
