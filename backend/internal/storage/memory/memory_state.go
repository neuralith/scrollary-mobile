package memory

import (
	"context"
	"sort"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

// --- reading state ----------------------------------------------------------

type readingStates Store

func (x *readingStates) Get(_ context.Context, lib domain.LibraryID, entry domain.ID) (*domain.ReadingState, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	r, ok := s.reading[entry]
	if !ok || r.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	return r, nil
}

// Put applies last-write-wins on the reading clock.
//
// Completion is treated as a value rather than a floor: an older completion
// does not beat a newer "mark as unread", which exists precisely to lower
// progress.
func (x *readingStates) Put(_ context.Context, r *domain.ReadingState) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	if existing, ok := s.reading[r.EntryID]; ok && existing.UpdatedAt.After(r.UpdatedAt) {
		return nil
	}
	s.reading[r.EntryID] = r
	return nil
}

// --- measurements -----------------------------------------------------------

type measurements Store

func (x *measurements) Get(_ context.Context, lib domain.LibraryID, entry, source domain.ID) (*domain.Measurement, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	m, ok := s.measurements[[2]domain.ID{entry, source}]
	if !ok || m.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	return m, nil
}

func (x *measurements) ForEntry(_ context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Measurement, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*domain.Measurement
	for key, m := range s.measurements {
		if key[0] == entry && m.LibraryID == lib {
			out = append(out, m)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ObservedAt.Before(out[j].ObservedAt) })
	return out, nil
}

// Put stores a measurement against the rendering it was taken on. The scope is
// part of the key, so a reading of one Source can never be silently read as a
// claim about another.
func (x *measurements) Put(_ context.Context, m *domain.Measurement) error {
	if err := m.Validate(); err != nil {
		return err
	}
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	key := [2]domain.ID{m.EntryID, m.SourceID}
	if existing, ok := s.measurements[key]; ok && existing.ObservedAt.After(m.ObservedAt) {
		return nil
	}
	s.measurements[key] = m
	return nil
}

// --- download requests ------------------------------------------------------

type downloadRequests Store

// Create is idempotent by construction: at most one non-terminal request per
// (library, entry), so pressing "download on mobile" twice does not queue two
// saves. An identical idempotency key returns the existing record.
func (x *downloadRequests) Create(_ context.Context, d *domain.DownloadRequest) (*domain.DownloadRequest, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, existing := range s.downloads {
		if existing.LibraryID != d.LibraryID {
			continue
		}
		if d.IdempotencyKey != "" && existing.IdempotencyKey == d.IdempotencyKey {
			return existing, nil
		}
		if existing.EntryID == d.EntryID && !existing.State.Terminal() {
			return existing, nil
		}
	}
	s.downloads[d.ID] = d
	return d, nil
}

func (x *downloadRequests) Pending(_ context.Context, lib domain.LibraryID) ([]*domain.DownloadRequest, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []*domain.DownloadRequest
	for _, d := range s.downloads {
		if d.LibraryID == lib && d.State == domain.DownloadPending {
			out = append(out, d)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt.Before(out[j].CreatedAt) })
	return out, nil
}

// Claim is the single-winner transition: exactly one device moves a request
// from pending to claimed, and every loser is told rather than silently
// proceeding.
func (x *downloadRequests) Claim(_ context.Context, lib domain.LibraryID, id domain.ID, device string) (*domain.DownloadRequest, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.downloads[id]
	if !ok || d.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	if err := d.Claim(device, s.now()); err != nil {
		return nil, err
	}
	return d, nil
}

func (x *downloadRequests) Resolve(_ context.Context, lib domain.LibraryID, id domain.ID, state domain.DownloadRequestState, reason string) (*domain.DownloadRequest, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.downloads[id]
	if !ok || d.LibraryID != lib {
		return nil, domain.ErrNotFound
	}
	if err := d.Resolve(state, reason, s.now()); err != nil {
		return nil, err
	}
	return d, nil
}

// --- tombstones -------------------------------------------------------------

type tombstones Store

func (x *tombstones) Add(_ context.Context, t domain.Tombstone) error {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tombstones = append(s.tombstones, t)
	return nil
}

func (x *tombstones) Since(_ context.Context, lib domain.LibraryID, since domain.Revision) ([]domain.Tombstone, error) {
	s := (*Store)(x)
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []domain.Tombstone
	for _, t := range s.tombstones {
		if t.LibraryID == lib && t.Revision > since {
			out = append(out, t)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Revision < out[j].Revision })
	return out, nil
}
