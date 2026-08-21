package postgres

// PostgreSQL-specific behaviour: migration reversibility, constraint
// enforcement below the Go validators, and real concurrency. None of this can
// be proven against a mock, which is why these tests insist on the engine.

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

var domainTables = []string{
	"libraries", "folders", "collections", "sources", "entries", "locations",
	"reading_states", "measurements", "download_requests", "tombstones", "mutations",
}

func tableExists(t *testing.T, s *Store, name string) bool {
	t.Helper()
	var exists bool
	err := s.pool.QueryRow(context.Background(),
		`SELECT EXISTS (SELECT 1 FROM information_schema.tables
		 WHERE table_schema = 'public' AND table_name = $1)`, name).Scan(&exists)
	if err != nil {
		t.Fatalf("check table %s: %v", name, err)
	}
	return exists
}

// The up migration creates every domain table; the down migration removes
// every one of them and is the exact reverse, not an approximation.
func TestMigrationsApplyAndDownReverses(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()

	for _, table := range domainTables {
		if !tableExists(t, s, table) {
			t.Fatalf("migration must create table %q", table)
		}
	}

	// Applying again must be a no-op, not an error.
	if err := migrate(ctx, s.pool); err != nil {
		t.Fatalf("re-migrate must be idempotent: %v", err)
	}

	if err := migrateDown(ctx, s.pool); err != nil {
		t.Fatalf("down migration: %v", err)
	}
	for _, table := range domainTables {
		if tableExists(t, s, table) {
			t.Fatalf("down migration must drop table %q", table)
		}
	}

	// And up again from the emptied ledger restores everything.
	if err := migrate(ctx, s.pool); err != nil {
		t.Fatalf("re-apply after down: %v", err)
	}
	for _, table := range domainTables {
		if !tableExists(t, s, table) {
			t.Fatalf("re-applied migration must recreate table %q", table)
		}
	}
}

// The CHECK constraints hold at the SQL layer even when the Go validators are
// bypassed entirely.
func TestChecksHoldBelowTheValidators(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	// I3: an entry with both a collection and a folder, written raw.
	col := &domain.Collection{
		ID: domain.NewID(), LibraryID: lib, FolderID: root, Name: "W",
		OrderingBasis: domain.OrderExplicitNumericIndex, Lifecycle: domain.CollectionActive,
	}
	if err := s.Collections().Upsert(ctx, col); err != nil {
		t.Fatalf("upsert collection: %v", err)
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO entries (id, library_id, collection_id, folder_id, placement, revision)
		VALUES ($1, $2, $3, $4, 'placed', 1)`,
		domain.NewID(), lib, col.ID, root)
	if !errors.Is(translate(err), domain.ErrEntryPlacement) {
		t.Fatalf("I3 must hold at the SQL layer, got %v", err)
	}

	// An unplaced entry carrying an ordinal, written raw.
	_, err = s.pool.Exec(ctx, `
		INSERT INTO entries (id, library_id, collection_id, ordinal, placement, revision)
		VALUES ($1, $2, $3, 7, 'unplaced', 1)`,
		domain.NewID(), lib, col.ID)
	if !errors.Is(translate(err), domain.ErrDuplicateOrdinal) {
		t.Fatalf("unplaced_entry_has_no_ordinal must hold at the SQL layer, got %v", err)
	}

	// A second root folder for the same library.
	_, err = s.pool.Exec(ctx, `
		INSERT INTO folders (id, library_id, parent_id, kind, name, revision)
		VALUES ($1, $2, NULL, 'root', 'again', 1)`,
		domain.NewID(), lib)
	if !errors.Is(translate(err), domain.ErrRootMustNotHaveParent) {
		t.Fatalf("one_root_per_library must hold at the SQL layer, got %v", err)
	}

	// A second open download request for the same entry, written raw past the
	// Create guard.
	n := 1.0
	e := &domain.Entry{ID: domain.NewID(), LibraryID: lib, CollectionID: &col.ID, Ordinal: &n, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, e); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}
	if _, err := s.pool.Exec(ctx, `
		INSERT INTO download_requests (id, library_id, entry_id, state, revision)
		VALUES ($1, $2, $3, 'pending', 1)`, domain.NewID(), lib, e.ID); err != nil {
		t.Fatalf("first open request: %v", err)
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO download_requests (id, library_id, entry_id, state, revision)
		VALUES ($1, $2, $3, 'pending', 1)`, domain.NewID(), lib, e.ID)
	if !errors.Is(translate(err), domain.ErrAlreadyExists) {
		t.Fatalf("one_open_request_per_entry must hold at the SQL layer, got %v", err)
	}
}

// Exactly one of N concurrent devices wins a claim against the real database.
func TestConcurrentClaimHasExactlyOneWinner(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	e := &domain.Entry{ID: domain.NewID(), LibraryID: lib, FolderID: &root, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, e); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}
	req, err := s.DownloadRequests().Create(ctx, &domain.DownloadRequest{
		ID: domain.NewID(), LibraryID: lib, EntryID: e.ID,
		State: domain.DownloadPending, CreatedAt: time.Now(),
	})
	if err != nil {
		t.Fatalf("create request: %v", err)
	}

	const devices = 16
	var wg sync.WaitGroup
	wins := make(chan string, devices)
	losses := make(chan error, devices)
	for i := 0; i < devices; i++ {
		wg.Add(1)
		go func(n int) {
			defer wg.Done()
			d, err := s.DownloadRequests().Claim(ctx, lib, req.ID, string(rune('a'+n)))
			if err != nil {
				losses <- err
				return
			}
			wins <- d.ClaimedByDevice
		}(i)
	}
	wg.Wait()
	close(wins)
	close(losses)

	if got := len(wins); got != 1 {
		t.Fatalf("exactly one device must win the claim, got %d", got)
	}
	for err := range losses {
		if !errors.Is(err, domain.ErrRequestClaimed) {
			t.Fatalf("every loser must be told with ErrRequestClaimed, got %v", err)
		}
	}
}

// Concurrent revision allocation never duplicates and never skips backwards.
func TestConcurrentRevisionsNeverDuplicate(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	lib, err := s.Libraries().EnsureByName(ctx, "concurrent")
	if err != nil {
		t.Fatalf("ensure: %v", err)
	}

	const workers, each = 8, 25
	var wg sync.WaitGroup
	got := make(chan domain.Revision, workers*each)
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < each; j++ {
				r, err := s.Revisions().Next(ctx, lib.ID)
				if err != nil {
					t.Errorf("next: %v", err)
					return
				}
				got <- r
			}
		}()
	}
	wg.Wait()
	close(got)

	seen := map[domain.Revision]bool{}
	var max domain.Revision
	for r := range got {
		if seen[r] {
			t.Fatalf("revision %d allocated twice", r)
		}
		seen[r] = true
		if r > max {
			max = r
		}
	}
	// EnsureByName consumed revision 1 for the root folder.
	if len(seen) != workers*each || max != domain.Revision(workers*each)+1 {
		t.Fatalf("expected %d unique revisions ending at %d, got %d ending at %d",
			workers*each, workers*each+1, len(seen), max)
	}
	cur, err := s.Revisions().Current(ctx, lib.ID)
	if err != nil || cur != max {
		t.Fatalf("current must equal the highest allocated revision")
	}
}

// Concurrent creates for the same entry converge on one open request instead
// of racing past a read-then-write check.
func TestConcurrentCreateConvergesOnOneOpenRequest(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	e := &domain.Entry{ID: domain.NewID(), LibraryID: lib, FolderID: &root, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, e); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}

	const creators = 12
	var wg sync.WaitGroup
	ids := make(chan domain.ID, creators)
	for i := 0; i < creators; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			d, err := s.DownloadRequests().Create(ctx, &domain.DownloadRequest{
				ID: domain.NewID(), LibraryID: lib, EntryID: e.ID,
				State: domain.DownloadPending, CreatedAt: time.Now(),
			})
			if err != nil {
				t.Errorf("create: %v", err)
				return
			}
			ids <- d.ID
		}()
	}
	wg.Wait()
	close(ids)

	unique := map[domain.ID]bool{}
	for id := range ids {
		unique[id] = true
	}
	if len(unique) != 1 {
		t.Fatalf("every concurrent create must converge on one open request, got %d distinct", len(unique))
	}
	pending, err := s.DownloadRequests().Pending(ctx, lib)
	if err != nil || len(pending) != 1 {
		t.Fatalf("exactly one pending request must exist, got %d (%v)", len(pending), err)
	}
}

// Two concurrent moves that would form a cycle together cannot both commit.
func TestConcurrentFolderMovesCannotCommitACycle(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	a := &domain.Folder{ID: domain.NewID(), LibraryID: lib, ParentID: &root, Kind: domain.FolderUser, Name: "A"}
	b := &domain.Folder{ID: domain.NewID(), LibraryID: lib, ParentID: &root, Kind: domain.FolderUser, Name: "B"}
	if err := s.Folders().Create(ctx, a); err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := s.Folders().Create(ctx, b); err != nil {
		t.Fatalf("create: %v", err)
	}

	var wg sync.WaitGroup
	errs := make([]error, 2)
	wg.Add(2)
	go func() { defer wg.Done(); errs[0] = s.Folders().Move(ctx, lib, a.ID, b.ID) }()
	go func() { defer wg.Done(); errs[1] = s.Folders().Move(ctx, lib, b.ID, a.ID) }()
	wg.Wait()

	// Whatever the interleaving, the tree must still be acyclic: walking up
	// from either folder must terminate at the root.
	for _, start := range []domain.ID{a.ID, b.ID} {
		seen := map[domain.ID]bool{}
		cur := start
		for {
			if seen[cur] {
				t.Fatalf("cycle committed: moves returned %v and %v", errs[0], errs[1])
			}
			seen[cur] = true
			f, err := s.Folders().Get(ctx, lib, cur)
			if err != nil {
				t.Fatalf("get: %v", err)
			}
			if f.ParentID == nil {
				break
			}
			cur = *f.ParentID
		}
	}
}
