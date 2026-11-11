// Command api runs the SecureVault backend .
package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"github.com/itsnavin/securevault/backend/internal/auth"
	"github.com/itsnavin/securevault/backend/internal/config"
	"github.com/itsnavin/securevault/backend/internal/httpapi"
	syncsvc "github.com/itsnavin/securevault/backend/internal/sync"
)

// router mounts the sync API only in explicit local-dev mode: an in-memory
// store with one static token. Production auth (OPAQUE sessions) and the
// Postgres store are not implemented, so nothing else is exposed.
func router() http.Handler {
	token := os.Getenv("SECUREVAULT_DEV_TOKEN")
	if os.Getenv("SECUREVAULT_DEV_SYNC") != "1" || len(token) < 32 {
		return httpapi.NewRouter()
	}
	log.Print("WARNING: dev sync enabled (in-memory, single static token); not for production")
	a := auth.NewMemoryAuthenticator()
	a.Add(token, "dev-user")
	s := syncsvc.NewMemoryStore()
	s.Grant("dev-user", "personal", syncsvc.RoleOwner)
	return httpapi.NewRouterWithSync(a, s)
}

func main() {
	cfg, err := config.Load(nil)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           router(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
	}
	log.Printf("securevault api listening on %s", cfg.ListenAddr)
	log.Fatal(srv.ListenAndServe())
}
