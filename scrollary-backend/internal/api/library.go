package api

import (
	"github.com/gofiber/fiber/v3"

	"github.com/neuralith/scrollary-backend/internal/config"
	"github.com/neuralith/scrollary-backend/internal/domain"
)

// LibraryHeader names the development library a request addresses.
const LibraryHeader = "X-Scrollary-Library"

// resolveLibrary is the whole of the development access mechanism.
//
// It authenticates nothing, and that is stated rather than implied. Production
// authentication is deferred to V2_PRODUCTIZATION.md P1; what the functionality
// build needs is only that several development clients can address the same
// test library. When real authentication arrives, this function is deleted and
// the library id comes from the account instead - the domain does not change,
// because library_id is already a real column on every synchronised row.
func (s *Server) resolveLibrary(c fiber.Ctx) (domain.LibraryID, error) {
	name := c.Get(LibraryHeader)

	if !s.cfg.DevMode {
		if name != "" {
			return domain.LibraryID{}, config.ErrDevHeaderWithoutDevMode
		}
		// Without development mode there is no way to name a library yet.
		// That is correct: the production path is authentication, not a header.
		return domain.LibraryID{}, config.ErrDevHeaderWithoutDevMode
	}

	if name == "" {
		name = s.cfg.DevLibrary
	}
	lib, err := s.store.Libraries().EnsureByName(c.Context(), name)
	if err != nil {
		return domain.LibraryID{}, err
	}
	return lib.ID, nil
}
