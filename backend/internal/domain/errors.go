package domain

import "errors"

// Invariant violations, named rather than free text so a client can group and
// explain them and so a new one cannot be introduced by writing a new sentence.
// The numbering matches docs/V2_ARCHITECTURE.md section 3.
var (
	ErrRootMustNotHaveParent  = errors.New("I1: the root folder must not have a parent")
	ErrFolderMustHaveParent   = errors.New("I1: a non-root folder must have a parent")
	ErrFolderCycle            = errors.New("I2: a folder may not contain itself")
	ErrEntryPlacement         = errors.New("I3: an entry has a folder iff it has no collection")
	ErrCollectionNeedsFolder  = errors.New("I4: every collection has a folder")
	ErrDuplicateURLKey        = errors.New("I6: url_key is unique within a library")
	ErrLocationSourcePairing  = errors.New("I7: a location has a source iff its entry has a collection")
	ErrDuplicateOrdinal       = errors.New("I8: an ordinal is unique within its collection")
	ErrPreferredSourceForeign = errors.New("I9: a preferred source must belong to its collection")
	ErrMeasurementNeedsScope  = errors.New("I12: a measurement must name the source it was measured against")

	ErrNotFound       = errors.New("not found")
	ErrAlreadyExists  = errors.New("already exists")
	ErrRequestClaimed = errors.New("download request already claimed")
)
