// Command api runs the SecureVault backend (Phase 1 skeleton).
package main

import (
	"log"
	"net/http"
	"time"

	"github.com/itsnavin/securevault/backend/internal/config"
	"github.com/itsnavin/securevault/backend/internal/httpapi"
)

func main() {
	cfg, err := config.Load(nil)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           httpapi.NewRouter(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
	}
	log.Printf("securevault api listening on %s", cfg.ListenAddr)
	log.Fatal(srv.ListenAndServe())
}
