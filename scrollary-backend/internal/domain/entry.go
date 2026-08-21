package domain

import "time"

// Placement distinguishes a position the app derived from one the user chose,
// and marks the honest third case where neither could be established.
type Placement string

const (
	// PlacementPlaced: the ordinal was read unambiguously from a Source.
	PlacementPlaced Placement = "placed"
	// PlacementUnplaced: no ordinal could be established. A real, visible
	// state - the Entry is still readable, and the user may place it.
	PlacementUnplaced Placement = "unplaced"
	// PlacementUser: the user placed it by hand.
	PlacementUser Placement = "userPlaced"
)

// Entry is one logical unit of reading, and the thing reading state belongs to.
//
// An Entry is NOT a URL. That was V1's axiom and it is what stopped an Entry
// from existing in more than one place. Where an Entry can be read is a
// Location; how far through it the reader got is a Measurement scoped to a
// rendering; whether this device holds the bytes is an OfflineCopy, which the
// server never sees.
//
// CollectionID is nil for a standalone Entry, which is a first-class library
// item that owns its Locations directly and lives in a Folder. It is never
// wrapped in a Collection of one to make the model tidy.
type Entry struct {
	ID           ID
	LibraryID    LibraryID
	CollectionID *ID
	FolderID     *ID
	Ordinal      *float64
	Placement    Placement
	Title        string
	SortKey      int64
	Revision     Revision
	UpdatedAt    time.Time
}

// Standalone reports whether this Entry belongs to no Collection.
func (e Entry) Standalone() bool { return e.CollectionID == nil }

// Validate enforces I3: an Entry has a Folder if and only if it has no
// Collection. An Entry inside a Collection is where its Collection is.
func (e Entry) Validate() error {
	if (e.CollectionID == nil) != (e.FolderID != nil) {
		return ErrEntryPlacement
	}
	if e.Placement == PlacementUnplaced && e.Ordinal != nil {
		return ErrDuplicateOrdinal
	}
	return nil
}
