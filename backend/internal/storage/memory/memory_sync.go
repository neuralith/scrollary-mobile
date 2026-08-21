package memory

import (
	"context"
	"sort"
	"time"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage"
)

// stampClock gives a zero row clock the current time, so callers that never
// think about clocks keep today's behaviour while sync-applied writes, which
// carry the client's transaction time, get genuine last-write-wins.
func stampClock(t *time.Time, now func() time.Time) {
	if t.IsZero() {
		*t = now()
	}
}

// --- folder upsert ----------------------------------------------------------

// Upsert applies a synchronised folder write with the same cycle discipline as
// Move: a sync-applied parent change must not commit what an interactive move
// would refuse.
func (f *folders) Upsert(_ context.Context, fd *domain.Folder) error {
	if err := fd.Validate(); err != nil {
		return err
	}
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()

	if fd.ParentID != nil {
		p, ok := s.folders[*fd.ParentID]
		if !ok || p.LibraryID != fd.LibraryID {
			return domain.ErrNotFound
		}
		// I2: walk up from the proposed parent; meeting this folder is a cycle.
		for cur := *fd.ParentID; ; {
			if cur == fd.ID {
				return domain.ErrFolderCycle
			}
			p := s.folders[cur]
			if p == nil || p.ParentID == nil {
				break
			}
			cur = *p.ParentID
		}
	}
	if fd.IsRoot() {
		// One root per library: a second root is refused, as the partial
		// unique index refuses it on Postgres.
		for _, other := range s.folders {
			if other.LibraryID == fd.LibraryID && other.IsRoot() && other.ID != fd.ID {
				return domain.ErrRootMustNotHaveParent
			}
		}
	}
	stampClock(&fd.UpdatedAt, s.now)
	if existing, ok := s.folders[fd.ID]; ok && existing.UpdatedAt.After(fd.UpdatedAt) {
		return nil
	}
	s.folders[fd.ID] = fd
	return nil
}

// --- deletes ----------------------------------------------------------------
//
// Each delete mirrors the schema's ON DELETE actions, so the two stores agree
// about what a removal takes with it and what it leaves.

func (s *Store) deleteEntryLocked(id domain.ID) {
	for lid, l := range s.locations {
		if l.EntryID == id {
			delete(s.locations, lid)
		}
	}
	delete(s.reading, id)
	for key := range s.measurements {
		if key[0] == id {
			delete(s.measurements, key)
		}
	}
	for did, d := range s.downloads {
		if d.EntryID == id {
			delete(s.downloads, did)
		}
	}
	delete(s.entries, id)
}

func (s *Store) deleteSourceLocked(id domain.ID) {
	for lid, l := range s.locations {
		if l.SourceID != nil && *l.SourceID == id {
			delete(s.locations, lid)
		}
	}
	for key := range s.measurements {
		if key[1] == id {
			delete(s.measurements, key)
		}
	}
	for _, c := range s.collections {
		if c.PreferredSourceID != nil && *c.PreferredSourceID == id {
			c.PreferredSourceID = nil
		}
	}
	for _, other := range s.sources {
		if other.ResolvedIntoSourceID != nil && *other.ResolvedIntoSourceID == id {
			other.ResolvedIntoSourceID = nil
		}
	}
	delete(s.sources, id)
}

func (c *collections) Delete(_ context.Context, lib domain.LibraryID, id domain.ID) error {
	s := (*Store)(c)
	s.mu.Lock()
	defer s.mu.Unlock()
	col, ok := s.collections[id]
	if !ok || col.LibraryID != lib {
		return domain.ErrNotFound
	}
	for sid, src := range s.sources {
		if src.CollectionID == id {
			s.deleteSourceLocked(sid)
		}
	}
	for eid, e := range s.entries {
		if e.CollectionID != nil && *e.CollectionID == id {
			s.deleteEntryLocked(eid)
		}
	}
	delete(s.collections, id)
	return nil
}

func (x *sources) Delete(_ context.Context, lib domain.LibraryID, id domain.ID) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	src, ok := s.sources[id]
	if !ok || src.LibraryID != lib {
		return domain.ErrNotFound
	}
	s.deleteSourceLocked(id)
	return nil
}

func (x *entries) Delete(_ context.Context, lib domain.LibraryID, id domain.ID) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.entries[id]
	if !ok || e.LibraryID != lib {
		return domain.ErrNotFound
	}
	s.deleteEntryLocked(id)
	return nil
}

func (x *locations) Get(_ context.Context, lib domain.LibraryID, id domain.ID) (*domain.Location, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	l, ok := s.locations[id]
	if !ok || l.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	return l, nil
}

func (x *locations) Delete(_ context.Context, lib domain.LibraryID, id domain.ID) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	l, ok := s.locations[id]
	if !ok || l.LibraryID != lib {
		return domain.ErrNotFound
	}
	delete(s.locations, id)
	return nil
}

func (x *readingStates) Delete(_ context.Context, lib domain.LibraryID, entry domain.ID) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.reading[entry]
	if !ok || r.LibraryID != lib {
		return domain.ErrNotFound
	}
	delete(s.reading, entry)
	return nil
}

func (x *measurements) Delete(_ context.Context, lib domain.LibraryID, entry, source domain.ID) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	key := [2]domain.ID{entry, source}
	m, ok := s.measurements[key]
	if !ok || m.LibraryID != lib {
		return domain.ErrNotFound
	}
	delete(s.measurements, key)
	return nil
}

// --- placement --------------------------------------------------------------

// Place is the serialised ordinal-placement arbitration (B9). The store mutex
// is the serialisation, exactly as the library row lock is on Postgres.
func (x *entries) Place(_ context.Context, lib domain.LibraryID, id domain.ID, ordinal float64, rev domain.Revision) (*domain.Entry, *domain.Entry, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()

	e, ok := s.entries[id]
	if !ok || e.LibraryID != lib {
		return nil, nil, domain.ErrNotFound
	}
	if e.CollectionID == nil {
		return nil, nil, domain.ErrPlacementUnsupported
	}
	col, ok := s.collections[*e.CollectionID]
	if !ok || !col.OrderingBasis.SupportsCrossSourceMerge() {
		return nil, nil, domain.ErrPlacementUnsupported
	}
	for _, other := range s.entries {
		if other.ID != e.ID && other.LibraryID == lib &&
			other.CollectionID != nil && *other.CollectionID == *e.CollectionID &&
			other.Ordinal != nil && *other.Ordinal == ordinal {
			return nil, other, domain.ErrDuplicateOrdinal
		}
	}
	o := ordinal
	e.Ordinal = &o
	e.Placement = domain.PlacementUser
	e.Revision = rev
	e.UpdatedAt = s.now()
	return e, nil, nil
}

// --- mutation ledger --------------------------------------------------------

type mutationsLedger Store

func (m *mutationsLedger) Get(_ context.Context, lib domain.LibraryID, mutationID string) (*storage.MutationRecord, error) {
	s := (*Store)(m)
	s.mu.Lock()
	defer s.mu.Unlock()
	byID, ok := s.mutations[lib]
	if !ok {
		return nil, domain.ErrNotFound
	}
	rec, ok := byID[mutationID]
	if !ok {
		return nil, domain.ErrNotFound
	}
	return rec, nil
}

func (m *mutationsLedger) Record(_ context.Context, rec *storage.MutationRecord) error {
	s := (*Store)(m)
	s.mu.Lock()
	defer s.mu.Unlock()
	byID, ok := s.mutations[rec.LibraryID]
	if !ok {
		byID = map[string]*storage.MutationRecord{}
		s.mutations[rec.LibraryID] = byID
	}
	if _, exists := byID[rec.MutationID]; exists {
		return domain.ErrAlreadyExists
	}
	if rec.AppliedAt.IsZero() {
		rec.AppliedAt = s.now()
	}
	byID[rec.MutationID] = rec
	return nil
}

// --- change feed ------------------------------------------------------------

type changeFeed Store

func (c *changeFeed) Feed(_ context.Context, lib domain.LibraryID, after domain.Revision, limit int) ([]storage.FeedItem, bool, error) {
	s := (*Store)(c)
	s.mu.Lock()
	defer s.mu.Unlock()

	var items []storage.FeedItem
	for _, f := range s.folders {
		if f.LibraryID == lib && f.Revision > after {
			items = append(items, storage.FeedItem{Revision: f.Revision, Kind: domain.KindFolder, Folder: f})
		}
	}
	for _, col := range s.collections {
		if col.LibraryID == lib && col.Revision > after {
			items = append(items, storage.FeedItem{Revision: col.Revision, Kind: domain.KindCollection, Collection: col})
		}
	}
	for _, src := range s.sources {
		if src.LibraryID == lib && src.Revision > after {
			items = append(items, storage.FeedItem{Revision: src.Revision, Kind: domain.KindSource, Source: src})
		}
	}
	for _, e := range s.entries {
		if e.LibraryID == lib && e.Revision > after {
			items = append(items, storage.FeedItem{Revision: e.Revision, Kind: domain.KindEntry, Entry: e})
		}
	}
	for _, l := range s.locations {
		if l.LibraryID == lib && l.Revision > after {
			items = append(items, storage.FeedItem{Revision: l.Revision, Kind: domain.KindLocation, Location: l})
		}
	}
	for _, r := range s.reading {
		if r.LibraryID == lib && r.Revision > after {
			items = append(items, storage.FeedItem{Revision: r.Revision, Kind: domain.KindReading, ReadingState: r})
		}
	}
	for _, m := range s.measurements {
		if m.LibraryID == lib && m.Revision > after {
			items = append(items, storage.FeedItem{Revision: m.Revision, Kind: domain.KindMeasure, Measurement: m})
		}
	}
	for _, d := range s.downloads {
		if d.LibraryID == lib && d.Revision > after {
			items = append(items, storage.FeedItem{Revision: d.Revision, Kind: domain.KindDownload, DownloadRequest: d})
		}
	}
	for i := range s.tombstones {
		t := s.tombstones[i]
		if t.LibraryID == lib && t.Revision > after {
			items = append(items, storage.FeedItem{Revision: t.Revision, Kind: t.Kind, Tombstone: &t})
		}
	}

	sort.Slice(items, func(i, j int) bool { return items[i].Revision < items[j].Revision })
	hasMore := false
	if limit > 0 && len(items) > limit {
		items = items[:limit]
		hasMore = true
	}
	return items, hasMore, nil
}
