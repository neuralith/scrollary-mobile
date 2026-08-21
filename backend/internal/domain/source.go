package domain

import "time"

// SourceLifecycle carries a Source through its whole life in one structure.
//
// Active alternatives and dead predecessors are the same thing observed at
// different times, so they are the same row: a site coming back is a state
// change, not a row moved between tables. There is no separate source-history
// table.
type SourceLifecycle string

const (
	SourceActive       SourceLifecycle = "active"
	SourceDormant      SourceLifecycle = "dormant"
	SourceDead         SourceLifecycle = "dead"
	SourceResolvedInto SourceLifecycle = "resolvedInto"
)

// Source is one Collection as published on one site.
//
// Host and PathKey together are the Source's identity, and they are what V1
// called collection_key: the same algorithm, one level down from where it used
// to sit. Language belongs here rather than on the Collection, because a
// translation is a Source of the same work: you read the work once.
type Source struct {
	ID                   ID
	LibraryID            LibraryID
	CollectionID         ID
	Host                 string
	PathKey              string
	Language             string
	Lifecycle            SourceLifecycle
	ResolvedIntoSourceID *ID
	FirstSeenAt          time.Time
	LastSeenAt           time.Time
	Revision             Revision
	UpdatedAt            time.Time
}

// Readable reports whether this Source may currently be read from.
func (s Source) Readable() bool {
	return s.Lifecycle == SourceActive || s.Lifecycle == SourceDormant
}
