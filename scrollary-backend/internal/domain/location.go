package domain

import "time"

// LocationLifecycle records whether a Source still lists this address.
//
// Retraction is source-scoped: a reading of Source A may retract Source A's
// Locations and never Source B's (I15). It is evidence about one site, not a
// statement about the Entry.
type LocationLifecycle string

const (
	LocationActive    LocationLifecycle = "active"
	LocationRetracted LocationLifecycle = "retracted"
)

// Location is one Entry, at one URL, on one Source.
//
// URLKey is the normalised URL and is unique within a library: one URL is one
// place. This is what makes recognition - the hot path, asked on every page
// load - a single indexed lookup that works offline.
//
// SourceID is nil for a standalone Entry's Location. SourceLabel and
// SourceNumber are what the site printed, kept as evidence and never as
// identity.
type Location struct {
	ID             ID
	LibraryID      LibraryID
	EntryID        ID
	SourceID       *ID
	URL            string
	URLKey         string
	SourceLabel    string
	SourceNumber   *float64
	DiscoveredAt   time.Time
	DiscoveryBasis string
	Lifecycle      LocationLifecycle
	Revision       Revision
	UpdatedAt      time.Time
}

// ValidateAgainstEntry enforces I7: a Location belongs to a Source if and only
// if its Entry belongs to a Collection.
func (l Location) ValidateAgainstEntry(e Entry) error {
	if (l.SourceID != nil) != (e.CollectionID != nil) {
		return ErrLocationSourcePairing
	}
	if l.URLKey == "" {
		return ErrDuplicateURLKey
	}
	return nil
}
