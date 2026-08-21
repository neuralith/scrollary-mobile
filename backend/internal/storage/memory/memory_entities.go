package memory

import (
	"context"
	"sort"
	"strings"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

// --- collections ------------------------------------------------------------

type collections Store

func (c *collections) Get(_ context.Context, lib domain.LibraryID, id domain.ID) (*domain.Collection, error) {
	s := (*Store)(c)
	s.mu.Lock()
	defer s.mu.Unlock()
	col, ok := s.collections[id]
	if !ok || col.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	return col, nil
}

func (c *collections) InFolder(_ context.Context, lib domain.LibraryID, folder domain.ID) ([]*domain.Collection, error) {
	s := (*Store)(c)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*domain.Collection
	for _, col := range s.collections {
		if col.LibraryID == lib && col.FolderID == folder {
			out = append(out, col)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SortKey < out[j].SortKey })
	return out, nil
}

func (c *collections) Upsert(_ context.Context, col *domain.Collection) error {
	if err := col.Validate(); err != nil {
		return err
	}
	s := (*Store)(c)
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.folders[col.FolderID]; !ok {
		return domain.ErrNotFound
	}
	stampClock(&col.UpdatedAt, s.now)
	if existing, ok := s.collections[col.ID]; ok && existing.UpdatedAt.After(col.UpdatedAt) {
		return nil // last write wins on the row clock; an older write is dropped
	}
	s.collections[col.ID] = col
	return nil
}

// SetPreferredSource enforces I9: a preferred Source must belong to this
// Collection. Preference is a single pointer on the Collection rather than a
// flag on each Source, so there is exactly one place the answer lives.
func (c *collections) SetPreferredSource(_ context.Context, lib domain.LibraryID, id domain.ID, source *domain.ID) error {
	s := (*Store)(c)
	s.mu.Lock()
	defer s.mu.Unlock()
	col, ok := s.collections[id]
	if !ok || col.LibraryID != lib {
		return domain.ErrNotFound
	}
	if source != nil {
		src, ok := s.sources[*source]
		if !ok || src.CollectionID != id {
			return domain.ErrPreferredSourceForeign
		}
	}
	col.PreferredSourceID = source
	return nil
}

// --- sources ----------------------------------------------------------------

type sources Store

func (x *sources) Get(_ context.Context, lib domain.LibraryID, id domain.ID) (*domain.Source, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	src, ok := s.sources[id]
	if !ok || src.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	return src, nil
}

func (x *sources) ForCollection(_ context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Source, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*domain.Source
	for _, src := range s.sources {
		if src.LibraryID == lib && src.CollectionID == collection {
			out = append(out, src)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Host < out[j].Host })
	return out, nil
}

func (x *sources) ByIdentity(_ context.Context, lib domain.LibraryID, host, pathKey string) (*domain.Source, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	h, p := strings.ToLower(host), strings.ToLower(pathKey)
	for _, src := range s.sources {
		if src.LibraryID == lib && strings.ToLower(src.Host) == h && strings.ToLower(src.PathKey) == p {
			return src, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (x *sources) Upsert(_ context.Context, src *domain.Source) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.collections[src.CollectionID]; !ok {
		return domain.ErrNotFound
	}
	// (collection, host, path_key) is the source's identity, unique as the
	// schema's source_identity constraint enforces on Postgres.
	h, pk := strings.ToLower(src.Host), strings.ToLower(src.PathKey)
	for _, other := range s.sources {
		if other.ID != src.ID && other.CollectionID == src.CollectionID &&
			strings.ToLower(other.Host) == h && strings.ToLower(other.PathKey) == pk {
			return domain.ErrAlreadyExists
		}
	}
	stampClock(&src.UpdatedAt, s.now)
	if existing, ok := s.sources[src.ID]; ok && existing.UpdatedAt.After(src.UpdatedAt) {
		return nil
	}
	s.sources[src.ID] = src
	return nil
}

// --- entries ----------------------------------------------------------------

type entries Store

func (x *entries) Get(_ context.Context, lib domain.LibraryID, id domain.ID) (*domain.Entry, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.entries[id]
	if !ok || e.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	return e, nil
}

func (x *entries) ForCollection(_ context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Entry, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*domain.Entry
	for _, e := range s.entries {
		if e.LibraryID == lib && e.CollectionID != nil && *e.CollectionID == collection {
			out = append(out, e)
		}
	}
	// Unplaced entries sort after placed ones rather than being forced to zero,
	// which would drag them to the front of a collection they have no position in.
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i].Ordinal, out[j].Ordinal
		switch {
		case a != nil && b != nil:
			return *a < *b
		case a != nil:
			return true
		case b != nil:
			return false
		default:
			return out[i].SortKey < out[j].SortKey
		}
	})
	return out, nil
}

func (x *entries) ByOrdinal(_ context.Context, lib domain.LibraryID, collection domain.ID, ordinal float64) (*domain.Entry, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, e := range s.entries {
		if e.LibraryID == lib && e.CollectionID != nil && *e.CollectionID == collection &&
			e.Ordinal != nil && *e.Ordinal == ordinal {
			return e, nil
		}
	}
	return nil, domain.ErrNotFound
}

// Upsert enforces I3 through Entry.Validate and I8 here: an ordinal is unique
// within its collection, so two sources reporting the same position resolve to
// one logical Entry rather than to two.
func (x *entries) Upsert(_ context.Context, e *domain.Entry) error {
	if err := e.Validate(); err != nil {
		return err
	}
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	if e.CollectionID != nil && e.Ordinal != nil {
		for _, other := range s.entries {
			if other.ID == e.ID || other.LibraryID != e.LibraryID {
				continue
			}
			if other.CollectionID != nil && *other.CollectionID == *e.CollectionID &&
				other.Ordinal != nil && *other.Ordinal == *e.Ordinal {
				return domain.ErrDuplicateOrdinal
			}
		}
	}
	stampClock(&e.UpdatedAt, s.now)
	if existing, ok := s.entries[e.ID]; ok && existing.UpdatedAt.After(e.UpdatedAt) {
		return nil
	}
	s.entries[e.ID] = e
	return nil
}

// --- locations --------------------------------------------------------------

type locations Store

// ByURLKey is the recognition hot path: one indexed lookup, no arbitration.
func (x *locations) ByURLKey(_ context.Context, lib domain.LibraryID, urlKey string) (*domain.Location, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, l := range s.locations {
		if l.LibraryID == lib && l.URLKey == urlKey {
			return l, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (x *locations) ForEntry(_ context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Location, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*domain.Location
	for _, l := range s.locations {
		if l.LibraryID == lib && l.EntryID == entry {
			out = append(out, l)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].URLKey < out[j].URLKey })
	return out, nil
}

// Upsert enforces I6 (one URL is one place) and I7 (a Location has a Source iff
// its Entry has a Collection).
func (x *locations) Upsert(_ context.Context, l *domain.Location) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()

	e, ok := s.entries[l.EntryID]
	if !ok || e.LibraryID != l.LibraryID {
		return domain.ErrNotFound
	}
	if err := l.ValidateAgainstEntry(*e); err != nil {
		return err
	}
	for _, other := range s.locations {
		if other.ID != l.ID && other.LibraryID == l.LibraryID && other.URLKey == l.URLKey {
			return domain.ErrDuplicateURLKey
		}
	}
	stampClock(&l.UpdatedAt, s.now)
	if existing, ok := s.locations[l.ID]; ok && existing.UpdatedAt.After(l.UpdatedAt) {
		return nil
	}
	s.locations[l.ID] = l
	return nil
}
