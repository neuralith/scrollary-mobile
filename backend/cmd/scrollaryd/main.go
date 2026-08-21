// Command scrollaryd is the Scrollary V2 synchronisation service.
//
// It owns canonical identity, library organisation, reading state and download
// intents. It deliberately does not fetch third-party pages, store content, or
// know what any device holds offline - see docs/V2_SYNC.md section 6.
package main

import (
	"context"
	"log"

	"github.com/mcagricaliskan/scrollary/backend/internal/api"
	"github.com/mcagricaliskan/scrollary/backend/internal/config"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage/memory"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage/postgres"
)

func main() {
	cfg := config.Load()

	var store storage.Store = memory.New()
	if cfg.DatabaseURL != "" {
		pg, err := postgres.Open(context.Background(), cfg.DatabaseURL)
		if err != nil {
			// Failing loudly is better than starting on an in-memory store the
			// operator did not ask for and silently losing every write.
			log.Fatalf("open postgres store: %v", err)
		}
		defer pg.Close()
		store = pg
	}

	srv := api.New(cfg, store)
	log.Printf("scrollaryd listening on %s (devMode=%v)", cfg.Addr, cfg.DevMode)
	if err := srv.App().Listen(cfg.Addr); err != nil {
		log.Fatal(err)
	}
}
