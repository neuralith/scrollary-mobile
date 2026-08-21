package domain

import "time"

// Library is one user's synchronised library and the scope of every other
// entity here. Nothing crosses a library boundary: Scrollary has no sharing,
// no collaboration and no cross-user signal.
type Library struct {
	ID        LibraryID
	Name      string
	Revision  Revision
	CreatedAt time.Time
}
