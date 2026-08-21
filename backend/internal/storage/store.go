// Package storage defines the persistence boundary for the Scrollary backend.
//
// Only synchronised concepts appear here. There is deliberately no OfflineCopy
// store, no history store, no capture state and no content: those are
// device-owned, and reproducing the mobile database on the server is the
// mistake this boundary exists to prevent.
package storage

import (
	"context"
	"time"

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
	// Upsert applies a synchronised folder write: create or last-write-wins
	// update on the row clock. A parent change is cycle-checked exactly as
	// Move is, because a sync-applied write must not commit what an
	// interactive one would refuse.
	Upsert(ctx context.Context, f *domain.Folder) error

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

	// Delete removes the collection; its sources, entries and their dependent
	// rows go with it, mirroring the schema's cascade.
	Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error
}

// Sources owns the set of sites a Collection is published on.
type Sources interface {
	Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Source, error)
	ForCollection(ctx context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Source, error)

	// ByIdentity resolves a Source from host and path key - what V1 computed
	// as collection_key, now at the level it actually identifies.
	ByIdentity(ctx context.Context, lib domain.LibraryID, host, pathKey string) (*domain.Source, error)
	Upsert(ctx context.Context, s *domain.Source) error

	// Delete removes the source and, per the schema's cascade, its locations.
	// Entries survive: they belong to the collection, not to the source.
	Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error
}

// Entries owns logical reading units.
type Entries interface {
	Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Entry, error)
	ForCollection(ctx context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Entry, error)
	ByOrdinal(ctx context.Context, lib domain.LibraryID, collection domain.ID, ordinal float64) (*domain.Entry, error)
	Upsert(ctx context.Context, e *domain.Entry) error

	// Delete removes the entry and its dependent rows per the schema cascade.
	Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error

	// Place is the serialised ordinal-placement arbitration (B9): it moves the
	// entry to userPlaced at the ordinal, stamping rev, if and only if no other
	// entry of the collection holds that ordinal. On conflict it returns the
	// current holder and domain.ErrDuplicateOrdinal; a collection whose
	// ordering basis does not support placement returns
	// domain.ErrPlacementUnsupported.
	Place(ctx context.Context, lib domain.LibraryID, id domain.ID, ordinal float64, rev domain.Revision) (*domain.Entry, *domain.Entry, error)
}

// Locations owns addresses, and is the recognition index.
//
// ByURLKey is the hot path: a URL the library already knows resolves through
// one indexed lookup, with no identity arbitration and no round trip.
type Locations interface {
	Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Location, error)
	ByURLKey(ctx context.Context, lib domain.LibraryID, urlKey string) (*domain.Location, error)
	ForEntry(ctx context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Location, error)
	Upsert(ctx context.Context, l *domain.Location) error
	Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error
}

// ReadingStates owns the portable reading fact.
type ReadingStates interface {
	Get(ctx context.Context, lib domain.LibraryID, entry domain.ID) (*domain.ReadingState, error)
	Put(ctx context.Context, r *domain.ReadingState) error
	Delete(ctx context.Context, lib domain.LibraryID, entry domain.ID) error
}

// Measurements owns scoped progress readings, keyed by (Entry, Source).
type Measurements interface {
	Get(ctx context.Context, lib domain.LibraryID, entry, source domain.ID) (*domain.Measurement, error)
	ForEntry(ctx context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Measurement, error)
	Put(ctx context.Context, m *domain.Measurement) error
	Delete(ctx context.Context, lib domain.LibraryID, entry, source domain.ID) error
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

// MutationRecord is one entry of the idempotency ledger: proof that a
// client-minted mutation id has been applied, and at which revision.
type MutationRecord struct {
	LibraryID  domain.LibraryID
	MutationID string
	Revision   domain.Revision
	AppliedAt  time.Time
}

// Mutations is the idempotency ledger. Recording an id that exists returns
// domain.ErrAlreadyExists, which is how a race between two identical retries
// resolves to one effect.
type Mutations interface {
	Get(ctx context.Context, lib domain.LibraryID, mutationID string) (*MutationRecord, error)
	Record(ctx context.Context, rec *MutationRecord) error
}

// FeedItem is one item of the change feed, in revision order. Exactly one of
// the entity pointers or Tombstone is set; Kind names which for entities.
type FeedItem struct {
	Revision domain.Revision
	Kind     domain.EntityKind

	Folder          *domain.Folder
	Collection      *domain.Collection
	Source          *domain.Source
	Entry           *domain.Entry
	Location        *domain.Location
	ReadingState    *domain.ReadingState
	Measurement     *domain.Measurement
	DownloadRequest *domain.DownloadRequest
	Tombstone       *domain.Tombstone
}

// ChangeFeed assembles the incremental pull: every row and tombstone with
// revision > after, in revision order, at most limit items. hasMore reports
// whether another page exists.
type ChangeFeed interface {
	Feed(ctx context.Context, lib domain.LibraryID, after domain.Revision, limit int) (items []FeedItem, hasMore bool, err error)
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
	Mutations() Mutations
	Changes() ChangeFeed
}
