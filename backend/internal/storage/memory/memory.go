// Package memory is an in-memory Store used by tests and local development.
//
// It exists so the domain, the API surface and the invariants can be exercised
// with no database and no network. The Postgres implementation replaces it
// behind the same interfaces.
package memory

import (
	"context"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage"
)

type Store struct {
	mu sync.Mutex

	libsByName map[string]domain.LibraryID
	libs       map[domain.LibraryID]*domain.Library

	folders      map[domain.ID]*domain.Folder
	collections  map[domain.ID]*domain.Collection
	sources      map[domain.ID]*domain.Source
	entries      map[domain.ID]*domain.Entry
	locations    map[domain.ID]*domain.Location
	reading      map[domain.ID]*domain.ReadingState
	measurements map[[2]domain.ID]*domain.Measurement
	downloads    map[domain.ID]*domain.DownloadRequest
	tombstones   []domain.Tombstone

	now func() time.Time
}

func New() *Store {
	return &Store{
		libsByName:   map[string]domain.LibraryID{},
		libs:         map[domain.LibraryID]*domain.Library{},
		folders:      map[domain.ID]*domain.Folder{},
		collections:  map[domain.ID]*domain.Collection{},
		sources:      map[domain.ID]*domain.Source{},
		entries:      map[domain.ID]*domain.Entry{},
		locations:    map[domain.ID]*domain.Location{},
		reading:      map[domain.ID]*domain.ReadingState{},
		measurements: map[[2]domain.ID]*domain.Measurement{},
		downloads:    map[domain.ID]*domain.DownloadRequest{},
		now:          time.Now,
	}
}

func (s *Store) Revisions() storage.Revisions               { return (*revisions)(s) }
func (s *Store) Libraries() storage.Libraries               { return (*libraries)(s) }
func (s *Store) Folders() storage.Folders                   { return (*folders)(s) }
func (s *Store) Collections() storage.Collections           { return (*collections)(s) }
func (s *Store) Sources() storage.Sources                   { return (*sources)(s) }
func (s *Store) Entries() storage.Entries                   { return (*entries)(s) }
func (s *Store) Locations() storage.Locations               { return (*locations)(s) }
func (s *Store) ReadingStates() storage.ReadingStates       { return (*readingStates)(s) }
func (s *Store) Measurements() storage.Measurements         { return (*measurements)(s) }
func (s *Store) DownloadRequests() storage.DownloadRequests { return (*downloadRequests)(s) }
func (s *Store) Tombstones() storage.Tombstones             { return (*tombstones)(s) }

// --- revisions --------------------------------------------------------------

type revisions Store

func (r *revisions) Next(_ context.Context, lib domain.LibraryID) (domain.Revision, error) {
	s := (*Store)(r)
	s.mu.Lock()
	defer s.mu.Unlock()
	l, ok := s.libs[lib]
	if !ok {
		return 0, domain.ErrNotFound
	}
	l.Revision++
	return l.Revision, nil
}

func (r *revisions) Current(_ context.Context, lib domain.LibraryID) (domain.Revision, error) {
	s := (*Store)(r)
	s.mu.Lock()
	defer s.mu.Unlock()
	l, ok := s.libs[lib]
	if !ok {
		return 0, domain.ErrNotFound
	}
	return l.Revision, nil
}

// --- libraries --------------------------------------------------------------

type libraries Store

// EnsureByName creates the library and its single system root Folder together,
// so I1 holds from the very first write rather than being established later.
func (l *libraries) EnsureByName(_ context.Context, name string) (*domain.Library, error) {
	s := (*Store)(l)
	s.mu.Lock()
	defer s.mu.Unlock()

	key := strings.ToLower(strings.TrimSpace(name))
	if id, ok := s.libsByName[key]; ok {
		return s.libs[id], nil
	}

	lib := &domain.Library{ID: domain.NewID(), Name: name, CreatedAt: s.now()}
	s.libs[lib.ID] = lib
	s.libsByName[key] = lib.ID

	lib.Revision++
	root := &domain.Folder{
		ID:        domain.NewID(),
		LibraryID: lib.ID,
		Kind:      domain.FolderRoot,
		Name:      "Library",
		Revision:  lib.Revision,
		UpdatedAt: s.now(),
	}
	if err := root.Validate(); err != nil {
		return nil, err
	}
	s.folders[root.ID] = root
	return lib, nil
}

func (l *libraries) Get(_ context.Context, id domain.LibraryID) (*domain.Library, error) {
	s := (*Store)(l)
	s.mu.Lock()
	defer s.mu.Unlock()
	lib, ok := s.libs[id]
	if !ok {
		return nil, domain.ErrNotFound
	}
	return lib, nil
}

// --- folders ----------------------------------------------------------------

type folders Store

func (f *folders) Root(_ context.Context, lib domain.LibraryID) (*domain.Folder, error) {
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, fd := range s.folders {
		if fd.LibraryID == lib && fd.IsRoot() {
			return fd, nil
		}
	}
	return nil, domain.ErrNotFound
}

func (f *folders) Get(_ context.Context, lib domain.LibraryID, id domain.ID) (*domain.Folder, error) {
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()
	fd, ok := s.folders[id]
	if !ok || fd.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	return fd, nil
}

func (f *folders) Children(_ context.Context, lib domain.LibraryID, parent domain.ID) ([]*domain.Folder, error) {
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*domain.Folder
	for _, fd := range s.folders {
		if fd.LibraryID == lib && fd.ParentID != nil && *fd.ParentID == parent {
			out = append(out, fd)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].SortKey < out[j].SortKey })
	return out, nil
}

func (f *folders) Create(_ context.Context, fd *domain.Folder) error {
	if err := fd.Validate(); err != nil {
		return err
	}
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.folders[fd.ID]; exists {
		return domain.ErrAlreadyExists
	}
	s.folders[fd.ID] = fd
	return nil
}

func (f *folders) Rename(_ context.Context, lib domain.LibraryID, id domain.ID, name string) error {
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()
	fd, ok := s.folders[id]
	if !ok || fd.LibraryID != lib {
		return domain.ErrNotFound
	}
	fd.Name = name
	fd.UpdatedAt = s.now()
	return nil
}

// Move reparents a folder, refusing a move that would make it its own ancestor.
func (f *folders) Move(_ context.Context, lib domain.LibraryID, id, newParent domain.ID) error {
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()
	fd, ok := s.folders[id]
	if !ok || fd.LibraryID != lib {
		return domain.ErrNotFound
	}
	if fd.IsRoot() {
		return domain.ErrRootMustNotHaveParent
	}
	if _, ok := s.folders[newParent]; !ok {
		return domain.ErrNotFound
	}
	// I2: walk up from the proposed parent; meeting this folder is a cycle.
	for cur := newParent; ; {
		if cur == id {
			return domain.ErrFolderCycle
		}
		p := s.folders[cur]
		if p == nil || p.ParentID == nil {
			break
		}
		cur = *p.ParentID
	}
	fd.ParentID = &newParent
	fd.UpdatedAt = s.now()
	return nil
}

// Delete reparents children to this folder's parent and removes it.
//
// It never touches Collections or Entries: tidying organisation must not be a
// way to destroy content (I5).
func (f *folders) Delete(_ context.Context, lib domain.LibraryID, id domain.ID) (int, error) {
	s := (*Store)(f)
	s.mu.Lock()
	defer s.mu.Unlock()
	fd, ok := s.folders[id]
	if !ok || fd.LibraryID != lib {
		return 0, domain.ErrNotFound
	}
	if fd.IsRoot() {
		return 0, domain.ErrRootMustNotHaveParent
	}
	parent := *fd.ParentID

	moved := 0
	for _, child := range s.folders {
		if child.LibraryID == lib && child.ParentID != nil && *child.ParentID == id {
			p := parent
			child.ParentID = &p
			moved++
		}
	}
	for _, c := range s.collections {
		if c.LibraryID == lib && c.FolderID == id {
			c.FolderID = parent
			moved++
		}
	}
	for _, e := range s.entries {
		if e.LibraryID == lib && e.FolderID != nil && *e.FolderID == id {
			p := parent
			e.FolderID = &p
			moved++
		}
	}
	delete(s.folders, id)
	return moved, nil
}
