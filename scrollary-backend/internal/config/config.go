// Package config is the configuration boundary.
//
// Everything the service reads from its environment is resolved here and
// nowhere else, so no handler reaches for an environment variable on its own.
package config

import (
	"errors"
	"os"
	"strconv"
	"strings"
)

// Config is the resolved runtime configuration.
type Config struct {
	// Addr is the listen address, e.g. ":8080".
	Addr string

	// DatabaseURL is the PostgreSQL connection string. Empty selects the
	// in-memory store, which is what the foundation and the tests run on.
	DatabaseURL string

	// DevMode enables the development library namespace.
	//
	// It is not authentication and does not pretend to be. Production
	// authentication is a separate programme (V2_PRODUCTIZATION.md P1); this
	// exists only so several development clients can address the same test
	// library. The server refuses the namespace header unless this is on.
	DevMode bool

	// DevLibrary is the library name used when a request carries no
	// X-Scrollary-Library header while DevMode is on.
	DevLibrary string
}

// ErrDevHeaderWithoutDevMode is returned when a request tries to select a
// library namespace on a server that was not started in development mode.
var ErrDevHeaderWithoutDevMode = errors.New("library namespace header requires SCROLLARY_DEV_MODE")

// Load resolves configuration from the environment, applying defaults.
func Load() Config {
	return Config{
		Addr:        env("SCROLLARY_ADDR", ":8080"),
		DatabaseURL: env("SCROLLARY_DATABASE_URL", ""),
		DevMode:     boolEnv("SCROLLARY_DEV_MODE", false),
		DevLibrary:  env("SCROLLARY_DEV_LIBRARY", "development"),
	}
}

func env(key, fallback string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return fallback
}

func boolEnv(key string, fallback bool) bool {
	v := strings.TrimSpace(os.Getenv(key))
	if v == "" {
		return fallback
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return fallback
	}
	return b
}
