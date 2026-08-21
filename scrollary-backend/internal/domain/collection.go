package domain

import "time"

// CollectionLifecycle records whether the user is following this Collection.
//
// A Collection in the library IS followed: that is the authorisation which
// lets Scrollary keep it current from the user's reading. Archiving is how
// following stops, and it preserves everything.
type CollectionLifecycle string

const (
	CollectionActive   CollectionLifecycle = "active"
	CollectionArchived CollectionLifecycle = "archived"
)

// OrderingBasis decides whether cross-source Entry merging is available at all.
//
// Only an explicit numeric index gives equivalence something to key on. The
// model states which mode a Collection is in rather than degrading silently:
// Scrollary does not pretend every website can be normalised.
type OrderingBasis string

const (
	OrderExplicitNumericIndex OrderingBasis = "explicitNumericIndex"
	OrderPublicationDate      OrderingBasis = "publicationDate"
	OrderDetectedNextLink     OrderingBasis = "detectedNextLink"
	OrderDiscoveryOrder       OrderingBasis = "discoveryOrder"
	OrderUserDefinedManual    OrderingBasis = "userDefinedManualOrder"
)

// SupportsCrossSourceMerge reports whether Entries from different Sources of
// this Collection may be merged automatically.
func (o OrderingBasis) SupportsCrossSourceMerge() bool {
	return o == OrderExplicitNumericIndex
}

// Collection is a logical work: a group of related Entries.
//
// It has no URL and no host. Those belong to its Sources, which is what lets a
// Collection outlive the site that published it.
type Collection struct {
	ID                ID
	LibraryID         LibraryID
	FolderID          ID
	Name              string
	DetectedTitle     string
	OrderingBasis     OrderingBasis
	Lifecycle         CollectionLifecycle
	PreferredSourceID *ID
	SortKey           int64
	Revision          Revision
	UpdatedAt         time.Time
}

// Validate enforces I4: every Collection has a Folder.
func (c Collection) Validate() error {
	if c.FolderID == (ID{}) {
		return ErrCollectionNeedsFolder
	}
	return nil
}

// Followed reports whether Scrollary may keep this Collection current from the
// user's reading.
func (c Collection) Followed() bool { return c.Lifecycle == CollectionActive }
