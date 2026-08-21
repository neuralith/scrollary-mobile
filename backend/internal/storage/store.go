// Package storage defines the persistence boundary for the Scrollary backend.
//
// Only synchronised concepts appear here. There is deliberately no OfflineCopy
// store, no history store, no capture state and no content: those are
// device-owned, and reproducing the mobile database on the server is the
// mistake this boundary exists to prevent.
package storage

import (
	"context"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

// Revisions allocates the per-library monotonic counter that every
// synchronised row and every tombstone carries, and that a client's sync
// cursor points into.
type Revisions interface {
	Next(ctx context.Context, lib domain.LibraryID) (domain.Revision, error)
	Current(ctx context.Context, lib domain.LibraryID) (domain.Revision, error)
}

// Libraries resolves the scope every other operation runs inside.
//
// EnsureByName exists for the development library namespace and is the only
// concession to deferred authentication; it creates the library and its single
// system root Folder together, so I1 holds from the first write.
type Libraries interface {
	EnsureByName(ctx context.Context, name string) (*domain.Library, error)
	Get(ctx context.Context, id domain.LibraryID) (*domain.Library, error)
}

// Folders owns the user's organisation tree.
type Folders interface {
	Root(ctx context.Context, lib domain.LibraryID) (*domain.Folder, error)
	Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Folder, error)
	Children(ctx context.Context, lib domain.LibraryID, parent domain.ID) ([]*domain.Folder, error)
	Create(ctx context.Context, f *domain.Folder) error
	Rename(ctx context.Context, lib domain.LibraryID, id domain.ID, name string) error
	Move(ctx context.Context, lib domain.LibraryID, id, newParent domain.ID) error

	// Delete reparents this folder's children to its parent and removes it.
	//
	// Deletion is conservative by construction: it never cascades into
	// Collections or Entries, so tidying can never destroy content. Returns
	// how many children were reparented.
	Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) (int, error)
}

// Collections owns logical works and their following state.
type Collections interface {
	Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Collection, error)
	InFolder(ctx context.Context, lib domain.LibraryID, folder domain.ID) ([]*domain.Collection, error)
	Upsert(ctx context.Context, c *domain.Collection) error
	SetPreferredSource(ctx context.Context, lib domain.LibraryID, id domain.ID, source *domain.ID) error
}

// Sources owns the set of sites a Collection is published on.
type Sources interface {
	Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Source, error)
	ForCollection(ctx context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Source, error)

	// ByIdentity resolves a Source from host and path key - what V1 computed
	// as collection_key, now at the level it actually identifies.
	ByIdentity(ctx context.Context, lib domain.LibraryID, host, pathKey string) (*domain.Source, error)
	Upsert(ctx context.Context, s *domain.Source) error
}

// Entries owns logical reading units.
type Entries interface {
	Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Entry, error)
	ForCollection(ctx context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Entry, error)
	ByOrdinal(ctx context.Context, lib domain.LibraryID, collection domain.ID, ordinal float64) (*domain.Entry, error)
	Upsert(ctx context.Context, e *domain.Entry) error
}

// Locations owns addresses, and is the recognition index.
//
// ByURLKey is the hot path: a URL the library already knows resolves through
// one indexed lookup, with no identity arbitration and no round trip.
type Locations interface {
	ByURLKey(ctx context.Context, lib domain.LibraryID, urlKey string) (*domain.Location, error)
	ForEntry(ctx context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Location, error)
	Upsert(ctx context.Context, l *domain.Location) error
}

// ReadingStates owns the portable reading fact.
type ReadingStates interface {
	Get(ctx context.Context, lib domain.LibraryID, entry domain.ID) (*domain.ReadingState, error)
	Put(ctx context.Context, r *domain.ReadingState) error
}

// Measurements owns scoped progress readings, keyed by (Entry, Source).
type Measurements interface {
	Get(ctx context.Context, lib domain.LibraryID, entry, source domain.ID) (*domain.Measurement, error)
	ForEntry(ctx context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Measurement, error)
	Put(ctx context.Context, m *domain.Measurement) error
}

// DownloadRequests owns remote download intents.
type DownloadRequests interface {
	Create(ctx context.Context, d *domain.DownloadRequest) (*domain.DownloadRequest, error)
	Pending(ctx context.Context, lib domain.LibraryID) ([]*domain.DownloadRequest, error)
	Claim(ctx context.Context, lib domain.LibraryID, id domain.ID, device string) (*domain.DownloadRequest, error)
	Resolve(ctx context.Context, lib domain.LibraryID, id domain.ID, state domain.DownloadRequestState, reason string) (*domain.DownloadRequest, error)
}

// Tombstones records deliberate removals for clients that were offline.
type Tombstones interface {
	Add(ctx context.Context, t domain.Tombstone) error
	Since(ctx context.Context, lib domain.LibraryID, since domain.Revision) ([]domain.Tombstone, error)
}

// Store is the whole persistence boundary. A Postgres implementation replaces
// the in-memory one without any caller changing.
type Store interface {
	Revisions() Revisions
	Libraries() Libraries
	Folders() Folders
	Collections() Collections
	Sources() Sources
	Entries() Entries
	Locations() Locations
	ReadingStates() ReadingStates
	Measurements() Measurements
	DownloadRequests() DownloadRequests
	Tombstones() Tombstones
}
