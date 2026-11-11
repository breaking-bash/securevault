// Package config loads backend configuration from the environment.
package config

import (
	"errors"
	"os"
	"strings"
)

// Config holds runtime settings. Secrets must come from the environment and
// are never logged.
type Config struct {
	ListenAddr  string
	DatabaseURL string
}

// Load reads configuration from environment variables.
// DATABASE_URL is optional in Phase 1 (no DB access is implemented yet).
func Load(getenv func(string) string) (Config, error) {
	if getenv == nil {
		getenv = os.Getenv
	}
	addr := strings.TrimSpace(getenv("SECUREVAULT_ADDR"))
	if addr == "" {
		addr = "127.0.0.1:8080"
	}
	if !strings.Contains(addr, ":") {
		return Config{}, errors.New("SECUREVAULT_ADDR must be host:port")
	}
	return Config{ListenAddr: addr, DatabaseURL: getenv("DATABASE_URL")}, nil
}
