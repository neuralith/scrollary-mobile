// Package api is the HTTP surface.
//
// The foundation exposes liveness and the development library namespace only.
// The synchronisation endpoints - evidence, mutations, changes, download
// requests - are Lane B work and are added against the frozen contract in
// contracts/openapi.yaml.
package api

import (
	"github.com/gofiber/fiber/v3"

	"github.com/neuralith/scrollary-backend/internal/config"
	"github.com/neuralith/scrollary-backend/internal/identity"
	"github.com/neuralith/scrollary-backend/internal/storage"
	syncsvc "github.com/neuralith/scrollary-backend/internal/sync"
)

// Version is stamped at build time; the default is what a local build reports.
var Version = "0.0.0-dev"

// Server holds everything a handler is allowed to reach.
type Server struct {
	cfg        config.Config
	store      storage.Store
	sync       *syncsvc.Service
	arbitrator *identity.Arbitrator
	app        *fiber.App
}

// New builds the Fiber application and registers routes.
func New(cfg config.Config, store storage.Store) *Server {
	s := &Server{
		cfg:        cfg,
		store:      store,
		sync:       syncsvc.New(store),
		arbitrator: identity.New(store),
		app:        fiber.New(fiber.Config{AppName: "scrollaryd"}),
	}
	s.routes()
	return s
}

// App exposes the Fiber application, for tests and for the entry point.
func (s *Server) App() *fiber.App { return s.app }

func (s *Server) routes() {
	s.app.Get("/healthz", s.health)
	s.app.Get("/version", s.version)

	// Everything below is scoped to one library (B11). The middleware is
	// attached per route - never globally - so system endpoints and anything a
	// test registers stay outside the namespace. Production authentication
	// replaces this middleware without changing any payload.
	s.app.Post("/identity/arbitrate", s.requireLibrary, s.arbitrateIdentity)
	s.app.Post("/mutations", s.requireLibrary, s.pushMutations)
	s.app.Get("/changes", s.requireLibrary, s.pullChanges)
	s.app.Post("/entries/:entry_id/placement", s.requireLibrary, s.placeEntry)
}

// health answers liveness. It deliberately does not touch the store: a
// liveness probe that fails because a dependency is slow tells the operator the
// wrong thing.
func (s *Server) health(c fiber.Ctx) error {
	return c.JSON(fiber.Map{"status": "ok"})
}

func (s *Server) version(c fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"version": Version,
		"devMode": s.cfg.DevMode,
	})
}
