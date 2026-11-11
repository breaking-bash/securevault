package syncsvc

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/itsnavin/securevault/backend/internal/auth"
)

type env struct {
	srv   http.Handler
	store *MemoryStore
}

func setup() env {
	a := auth.NewMemoryAuthenticator()
	a.Add("alice-token", "alice")
	a.Add("bob-token", "bob")
	a.Add("eve-token", "eve")
	s := NewMemoryStore()
	s.Grant("alice", "v1", RoleOwner)
	s.Grant("bob", "v1", RoleViewer)
	s.Grant("alice", "v2", RoleOwner)
	mux := http.NewServeMux()
	(&Handler{Store: s}).Register(mux, a)
	return env{mux, s}
}

func (e env) do(method, path, token, body string) (int, map[string]any) {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	e.srv.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec.Code, out
}

func putBody(base int, ct string) string {
	return `{"base_revision":` + itoa(base) + `,"format_version":1,"key_version":1,"ciphertext":"` +
		base64.StdEncoding.EncodeToString([]byte(ct)) + `"}`
}

func itoa(n int) string { b, _ := json.Marshal(n); return string(b) }

func TestRequiresAuth(t *testing.T) {
	e := setup()
	for _, tc := range [][2]string{
		{"GET", "/v1/vaults/v1/items"},
		{"PUT", "/v1/vaults/v1/items/a"},
		{"DELETE", "/v1/vaults/v1/items/a?base_revision=1"},
	} {
		if code, _ := e.do(tc[0], tc[1], "", putBody(0, "x")); code != 401 {
			t.Errorf("%v without token: %d", tc, code)
		}
		if code, _ := e.do(tc[0], tc[1], "wrong", putBody(0, "x")); code != 401 {
			t.Errorf("%v bad token: %d", tc, code)
		}
	}
}

func TestPutAndFeedRoundtrip(t *testing.T) {
	e := setup()
	code, out := e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", putBody(0, "cipher-1"))
	if code != 200 || out["revision"] != float64(1) {
		t.Fatalf("put: %d %v", code, out)
	}
	code, out = e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", putBody(1, "cipher-2"))
	if code != 200 || out["revision"] != float64(2) {
		t.Fatalf("update: %d %v", code, out)
	}
	code, out = e.do("GET", "/v1/vaults/v1/items", "bob-token", "")
	if code != 200 {
		t.Fatalf("viewer read: %d", code)
	}
	items := out["items"].([]any)
	if len(items) != 1 {
		t.Fatalf("items: %v", items)
	}
	it := items[0].(map[string]any)
	ct, _ := base64.StdEncoding.DecodeString(it["ciphertext"].(string))
	if string(ct) != "cipher-2" || it["revision"] != float64(2) {
		t.Fatalf("latest state not returned: %v", it)
	}
	if out["cursor"] != float64(2) || out["more"] != false {
		t.Fatalf("cursor/more: %v", out)
	}
}

func TestStaleWriteConflicts(t *testing.T) {
	e := setup()
	e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", putBody(0, "x"))
	code, out := e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", putBody(0, "overwrite"))
	if code != 409 || out["current_revision"] != float64(1) {
		t.Fatalf("stale put: %d %v", code, out)
	}
	if code, _ := e.do("PUT", "/v1/vaults/v1/items/new", "alice-token", putBody(5, "x")); code != 409 {
		t.Fatalf("future base revision accepted: %d", code)
	}
}

func TestDeleteTombstoneAndConflict(t *testing.T) {
	e := setup()
	e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", putBody(0, "x"))
	if code, _ := e.do("DELETE", "/v1/vaults/v1/items/a?base_revision=9", "alice-token", ""); code != 409 {
		t.Fatalf("stale delete: %d", code)
	}
	if code, out := e.do("DELETE", "/v1/vaults/v1/items/a?base_revision=1", "alice-token", ""); code != 200 || out["revision"] != float64(2) {
		t.Fatalf("delete: %d %v", code, out)
	}
	if code, _ := e.do("DELETE", "/v1/vaults/v1/items/a?base_revision=2", "alice-token", ""); code != 404 {
		t.Fatalf("double delete: %d", code)
	}
	_, out := e.do("GET", "/v1/vaults/v1/items", "alice-token", "")
	it := out["items"].([]any)[0].(map[string]any)
	if it["deleted"] != true || it["ciphertext"] != nil {
		t.Fatalf("tombstone should carry no ciphertext: %v", it)
	}
	if code, _ := e.do("DELETE", "/v1/vaults/v1/items/a", "alice-token", ""); code != 400 {
		t.Fatalf("missing base_revision: %d", code)
	}
}

func TestAuthorizationBoundaries(t *testing.T) {
	e := setup()
	if code, _ := e.do("PUT", "/v1/vaults/v1/items/a", "bob-token", putBody(0, "x")); code != 403 {
		t.Fatalf("viewer write: %d", code)
	}
	if code, _ := e.do("DELETE", "/v1/vaults/v1/items/a?base_revision=0", "bob-token", ""); code != 403 {
		t.Fatalf("viewer delete: %d", code)
	}
	// Non-members and unknown vaults are indistinguishable.
	for _, p := range []string{"/v1/vaults/v1/items", "/v1/vaults/nope/items"} {
		if code, _ := e.do("GET", p, "eve-token", ""); code != 404 {
			t.Fatalf("non-member %s: %d", p, code)
		}
	}
	if code, _ := e.do("PUT", "/v1/vaults/v1/items/a", "eve-token", putBody(0, "x")); code != 404 {
		t.Fatalf("non-member write: %d", code)
	}
	e.do("PUT", "/v1/vaults/v2/items/secret", "alice-token", putBody(0, "x"))
	_, out := e.do("GET", "/v1/vaults/v1/items", "alice-token", "")
	if len(out["items"].([]any)) != 0 {
		t.Fatal("items leaked across vaults")
	}
}

func TestInputValidation(t *testing.T) {
	e := setup()
	cases := map[string]string{
		"empty ct":     `{"base_revision":0,"format_version":1,"key_version":1,"ciphertext":""}`,
		"zero format":  `{"base_revision":0,"format_version":0,"key_version":1,"ciphertext":"eA=="}`,
		"big format":   `{"base_revision":0,"format_version":70000,"key_version":1,"ciphertext":"eA=="}`,
		"zero key":     `{"base_revision":0,"format_version":1,"key_version":0,"ciphertext":"eA=="}`,
		"unknown":      `{"base_revision":0,"format_version":1,"key_version":1,"ciphertext":"eA==","admin":true}`,
		"not json":     `nope`,
		"bad base64":   `{"base_revision":0,"format_version":1,"key_version":1,"ciphertext":"!!!"}`,
		"negative rev": `{"base_revision":-1,"format_version":1,"key_version":1,"ciphertext":"eA=="}`,
	}
	for name, body := range cases {
		if code, _ := e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", body); code != 400 {
			t.Errorf("%s: got %d, want 400", name, code)
		}
	}
	if code, _ := e.do("PUT", "/v1/vaults/v1/items/bad.id", "alice-token", putBody(0, "x")); code != 400 {
		t.Errorf("bad item id: %d", code)
	}
	if code, _ := e.do("GET", "/v1/vaults/v1/items?limit=0", "alice-token", ""); code != 400 {
		t.Errorf("limit 0: %d", code)
	}
	if code, _ := e.do("GET", "/v1/vaults/v1/items?cursor=abc", "alice-token", ""); code != 400 {
		t.Errorf("bad cursor: %d", code)
	}
}

func TestOversizedBodyRejected(t *testing.T) {
	e := setup()
	big := bytes.Repeat([]byte("a"), 2<<20)
	body := `{"base_revision":0,"format_version":1,"key_version":1,"ciphertext":"` +
		base64.StdEncoding.EncodeToString(big) + `"}`
	if code, _ := e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", body); code != 413 {
		t.Fatalf("oversized: %d", code)
	}
}

func TestPaginationAndIncrementalCursor(t *testing.T) {
	e := setup()
	for _, id := range []string{"a", "b", "c"} {
		e.do("PUT", "/v1/vaults/v1/items/"+id, "alice-token", putBody(0, id))
	}
	_, p1 := e.do("GET", "/v1/vaults/v1/items?limit=2", "alice-token", "")
	if len(p1["items"].([]any)) != 2 || p1["more"] != true {
		t.Fatalf("page1: %v", p1)
	}
	_, p2 := e.do("GET", "/v1/vaults/v1/items?limit=2&cursor=2", "alice-token", "")
	if len(p2["items"].([]any)) != 1 || p2["more"] != false || p2["cursor"] != float64(3) {
		t.Fatalf("page2: %v", p2)
	}
	e.do("PUT", "/v1/vaults/v1/items/a", "alice-token", putBody(1, "a2"))
	_, p3 := e.do("GET", "/v1/vaults/v1/items?cursor=3", "alice-token", "")
	items := p3["items"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["item_id"] != "a" {
		t.Fatalf("incremental: %v", p3)
	}
	_, p4 := e.do("GET", "/v1/vaults/v1/items?cursor=999", "alice-token", "")
	if len(p4["items"].([]any)) != 0 {
		t.Fatalf("future cursor: %v", p4)
	}
}
