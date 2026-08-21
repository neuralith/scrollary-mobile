package domain

import "time"

// ReadStatus is the portable, language-agnostic fact about an Entry.
type ReadStatus string

const (
	Unread    ReadStatus = "unread"
	Reading   ReadStatus = "reading"
	Completed ReadStatus = "completed"
)

// ReadingState belongs to the logical Entry - not to a file, a URL, a Source
// or a language. You read the work once.
//
// It is a separate record from Entry for a concrete reason rather than a
// stylistic one: reading updates are by far the most frequent mutation, and a
// separate row means a separate revision, so marking something read does not
// bump the Entry's metadata revision and force every other client to re-pull
// metadata that did not change.
//
// UpdatedAt is the merge clock. Last write wins, and completion is a value
// rather than a floor - highest-progress-wins looks safer and breaks "mark as
// unread", which exists precisely to lower progress.
type ReadingState struct {
	EntryID       ID
	LibraryID     LibraryID
	Status        ReadStatus
	FirstOpenedAt *time.Time
	LastReadAt    *time.Time
	CompletedAt   *time.Time
	Revision      Revision
	UpdatedAt     time.Time
}

// RecordSourceAccess applies the rule that opening an Entry at its source
// counts as access and never as completion (I16).
//
// Completion is only ever reached automatically inside Scrollary's own reader,
// where position is measured and the dwell policy applies. On a source we
// cannot observe position, so nothing is inferred and no progress figure is
// invented.
func (r *ReadingState) RecordSourceAccess(at time.Time) {
	if r.FirstOpenedAt == nil {
		r.FirstOpenedAt = &at
	}
	r.LastReadAt = &at
	if r.Status == Unread {
		r.Status = Reading
	}
	r.UpdatedAt = at
}

// Measurement is a progress reading scoped to the rendering it was taken
// against, keyed by (Entry, Source).
//
// A fraction measured against one Source's rendering is not an approximation
// of another's - it is a fact about a different thing. That is why scope
// replaces any notion of progress "confidence", and why the app never invents
// a number for a Source it has not measured.
//
// The reading ANCHOR is deliberately absent: an index and offset inside a
// specific artifact is meaningless without the bytes it indexes, so it lives on
// the device's OfflineCopy and never leaves it.
type Measurement struct {
	EntryID    ID
	SourceID   ID
	LibraryID  LibraryID
	Fraction   float64
	ObservedAt time.Time
	Revision   Revision
}

// Validate enforces I12: a Measurement must name the Source it was measured
// against.
func (m Measurement) Validate() error {
	if m.SourceID == (ID{}) {
		return ErrMeasurementNeedsScope
	}
	return nil
}
