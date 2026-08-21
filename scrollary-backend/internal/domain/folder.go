package domain

import "time"

// FolderKind separates the single system root from folders the user made.
type FolderKind string

const (
	FolderRoot FolderKind = "root"
	FolderUser FolderKind = "user"
)

// Folder is user organisation and nothing else.
//
// It carries no source identity and no content relationship, and Sources are
// never attached to it. It holds Collections and standalone Entries; an Entry
// inside a Collection lives where its Collection lives and has no folder
// membership of its own.
//
// There is exactly one system root per library, chosen over a nullable
// placement or a separate "unfiled" folder so that every item has exactly one
// parent, "move to folder" is always the same operation, and every placement
// synchronises as a value rather than sometimes as a null.
type Folder struct {
	ID        ID
	LibraryID LibraryID
	ParentID  *ID
	Kind      FolderKind
	Name      string
	SortKey   int64
	Revision  Revision
	UpdatedAt time.Time
}

// Validate enforces I1: ParentID is nil if and only if this is the root.
func (f Folder) Validate() error {
	switch f.Kind {
	case FolderRoot:
		if f.ParentID != nil {
			return ErrRootMustNotHaveParent
		}
	case FolderUser:
		if f.ParentID == nil {
			return ErrFolderMustHaveParent
		}
		if *f.ParentID == f.ID {
			return ErrFolderCycle
		}
	}
	return nil
}

func (f Folder) IsRoot() bool { return f.Kind == FolderRoot }
