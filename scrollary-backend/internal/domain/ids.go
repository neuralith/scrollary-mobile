package domain

import "github.com/google/uuid"

// ID is a canonical server-assigned identifier.
//
// Clients keep their own permanent local identifiers and record one of these
// beside them; a canonical ID is never written over a local one. Local file
// paths and manifests depend on local identifiers, so rewriting them would
// orphan bytes already on a device.
type ID = uuid.UUID

// LibraryID scopes every synchronised row to one user's library.
//
// During the functionality build the value comes from the development library
// namespace (see V2_SYNC.md section 9). The production account model populates the
// same column, so nothing about the domain changes when authentication arrives.
type LibraryID = uuid.UUID

// NewID mints a canonical identifier.
func NewID() ID { return uuid.New() }

// Revision is a per-library monotonic counter. Every synchronised row and every
// tombstone carries the revision at which it last changed, and a client's sync
// cursor is the highest revision it has seen.
type Revision int64
