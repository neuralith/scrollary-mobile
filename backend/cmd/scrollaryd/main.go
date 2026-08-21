// Command scrollaryd is the Scrollary V2 synchronisation service.
//
// It owns canonical identity, library organisation, reading state and download
// intents. It deliberately does not fetch third-party pages, store content, or
// know what any device holds offline - see docs/V2_SYNC.md section 6.
package main

import (
	"log"

	"github.com/mcagricaliskan/scrollary/backend/internal/api"
	"github.com/mcagricaliskan/scrollary/backend/internal/config"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage/memory"
)

func main() {
	cfg := config.Load()

	var store storage.Store = memory.New()
	if cfg.DatabaseURL != "" {
		// The PostgreSQL implementation is Lane B task B5. Failing loudly is
		// better than starting on an in-memory store the operator did not ask
		// for and silently losing every write.
		log.Fatal("SCROLLARY_DATABASE_URL is set but the PostgreSQL store is not implemented yet (roadmap task B5)")
	}

	srv := api.New(cfg, store)
	log.Printf("scrollaryd listening on %s (devMode=%v)", cfg.Addr, cfg.DevMode)
	if err := srv.App().Listen(cfg.Addr); err != nil {
		log.Fatal(err)
	}
}
