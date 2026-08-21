package api

import (
	"errors"

	"github.com/gofiber/fiber/v3"

	"github.com/mcagricaliskan/scrollary/backend/internal/config"
	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

// libraryKey is the request-local the middleware stores the resolved library
// under. Handlers read it through requestLibrary and never resolve on their
// own, so the boundary stays in exactly one place.
const libraryKey = "scrollary.library"

// requireLibrary resolves the development library namespace for every
// synchronisation endpoint (B11).
//
// The header authenticates nothing and the responses say so: a header sent to
// a server without SCROLLARY_DEV_MODE is 403 dev_mode_required, and a
// development server that cannot resolve any library name is 400
// library_unresolved. Production authentication replaces this middleware
// without changing any payload (V2_PRODUCTIZATION.md P1).
func (s *Server) requireLibrary(c fiber.Ctx) error {
	if !s.cfg.DevMode {
		return writeError(c, fiber.StatusForbidden, "dev_mode_required",
			"This server was not started with SCROLLARY_DEV_MODE.", nil)
	}
	name := c.Get(LibraryHeader)
	if name == "" {
		name = s.cfg.DevLibrary
	}
	if name == "" {
		return writeError(c, fiber.StatusBadRequest, "library_unresolved",
			"Development mode is on but no library name was resolved.", nil)
	}
	lib, err := s.store.Libraries().EnsureByName(c.Context(), name)
	if err != nil {
		if errors.Is(err, config.ErrDevHeaderWithoutDevMode) {
			return writeError(c, fiber.StatusForbidden, "dev_mode_required",
				"This server was not started with SCROLLARY_DEV_MODE.", nil)
		}
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"The library could not be resolved.", nil)
	}
	c.Locals(libraryKey, lib.ID)
	return c.Next()
}

// requestLibrary reads the library the middleware resolved.
func requestLibrary(c fiber.Ctx) domain.LibraryID {
	id, _ := c.Locals(libraryKey).(domain.LibraryID)
	return id
}
