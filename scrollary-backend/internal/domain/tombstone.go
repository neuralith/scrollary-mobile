package domain

import "time"

// EntityKind names what a tombstone or a change refers to.
type EntityKind string

const (
	KindFolder     EntityKind = "folder"
	KindCollection EntityKind = "collection"
	KindSource     EntityKind = "source"
	KindEntry      EntityKind = "entry"
	KindLocation   EntityKind = "location"
	KindReading    EntityKind = "readingState"
	KindMeasure    EntityKind = "measurement"
	KindDownload   EntityKind = "downloadRequest"
)

// Tombstone records a deliberate removal so a client that has been offline can
// learn about it.
//
// Only deliberate user removals produce one. A Location a Source stopped
// listing does NOT: that is source-scoped evidence which each device
// reconciles from its own reading, and propagating it would let a stale reading
// on one device remove a row on another.
//
// A tombstone never destroys bytes on any device (I14). A removal that arrives
// from elsewhere takes library rows and leaves the package on disk.
type Tombstone struct {
	LibraryID LibraryID
	Kind      EntityKind
	EntityID  ID
	Revision  Revision
	DeletedAt time.Time
}
