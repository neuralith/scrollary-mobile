package postgres

// The conformance suite: the same behavioural cases the in-memory store
// passes, run against real PostgreSQL. A caller must not be able to tell the
// stores apart, so these tests are ports of memory_test.go, not new inventions.

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

// I1: the root exists from the first write, and there is exactly one.
func TestLibraryIsCreatedWithExactlyOneRoot(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	again, err := s.Libraries().EnsureByName(ctx, "TEST")
	if err != nil {
		t.Fatalf("ensure is idempotent by name: %v", err)
	}
	if again.ID != lib {
		t.Fatal("the same name must resolve to the same library, case-insensitively")
	}

	r2, err := s.Folders().Root(ctx, lib)
	if err != nil || r2.ID != root {
		t.Fatal("a second ensure must not create a second root")
	}
}

// I5 protects user data: tidying organisation must never destroy content.
func TestDeletingAFolderReparentsAndNeverDeletesContent(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	mid := &domain.Folder{ID: domain.NewID(), LibraryID: lib, ParentID: &root, Kind: domain.FolderUser, Name: "Weekly"}
	if err := s.Folders().Create(ctx, mid); err != nil {
		t.Fatalf("create folder: %v", err)
	}
	leaf := &domain.Folder{ID: domain.NewID(), LibraryID: lib, ParentID: &mid.ID, Kind: domain.FolderUser, Name: "Nested"}
	if err := s.Folders().Create(ctx, leaf); err != nil {
		t.Fatalf("create nested folder: %v", err)
	}

	col := &domain.Collection{
		ID: domain.NewID(), LibraryID: lib, FolderID: mid.ID, Name: "Work",
		OrderingBasis: domain.OrderExplicitNumericIndex, Lifecycle: domain.CollectionActive,
	}
	if err := s.Collections().Upsert(ctx, col); err != nil {
		t.Fatalf("upsert collection: %v", err)
	}
	standalone := &domain.Entry{
		ID: domain.NewID(), LibraryID: lib, FolderID: &mid.ID, Placement: domain.PlacementPlaced,
	}
	if err := s.Entries().Upsert(ctx, standalone); err != nil {
		t.Fatalf("upsert standalone entry: %v", err)
	}

	moved, err := s.Folders().Delete(ctx, lib, mid.ID)
	if err != nil {
		t.Fatalf("delete folder: %v", err)
	}
	if moved != 3 {
		t.Fatalf("expected the nested folder, the collection and the entry to reparent, got %d", moved)
	}

	if got, err := s.Collections().Get(ctx, lib, col.ID); err != nil || got.FolderID != root {
		t.Fatal("the collection must survive and move up, never be deleted")
	}
	if got, err := s.Entries().Get(ctx, lib, standalone.ID); err != nil || *got.FolderID != root {
		t.Fatal("the standalone entry must survive and move up")
	}
	if got, err := s.Folders().Get(ctx, lib, leaf.ID); err != nil || *got.ParentID != root {
		t.Fatal("the nested folder must survive and move up")
	}
}

// I2: a folder may not become its own ancestor.
func TestFolderMoveRefusesCycles(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	a := &domain.Folder{ID: domain.NewID(), LibraryID: lib, ParentID: &root, Kind: domain.FolderUser, Name: "A"}
	if err := s.Folders().Create(ctx, a); err != nil {
		t.Fatalf("create: %v", err)
	}
	b := &domain.Folder{ID: domain.NewID(), LibraryID: lib, ParentID: &a.ID, Kind: domain.FolderUser, Name: "B"}
	if err := s.Folders().Create(ctx, b); err != nil {
		t.Fatalf("create: %v", err)
	}

	if err := s.Folders().Move(ctx, lib, a.ID, b.ID); !errors.Is(err, domain.ErrFolderCycle) {
		t.Fatalf("moving a folder into its own descendant must be refused, got %v", err)
	}
	if err := s.Folders().Move(ctx, lib, b.ID, root); err != nil {
		t.Fatalf("an ordinary move must succeed: %v", err)
	}
}

// I6: one URL is one place. This is also the recognition hot path.
func TestURLKeyIsUniqueAndResolvesInOneLookup(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	e := &domain.Entry{ID: domain.NewID(), LibraryID: lib, FolderID: &root, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, e); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}

	first := &domain.Location{
		ID: domain.NewID(), LibraryID: lib, EntryID: e.ID,
		URL: "https://example.com/a", URLKey: "https://example.com/a", Lifecycle: domain.LocationActive,
	}
	if err := s.Locations().Upsert(ctx, first); err != nil {
		t.Fatalf("upsert location: %v", err)
	}

	found, err := s.Locations().ByURLKey(ctx, lib, "https://example.com/a")
	if err != nil || found.EntryID != e.ID {
		t.Fatal("a known url must resolve to its entry without arbitration")
	}

	other := &domain.Entry{ID: domain.NewID(), LibraryID: lib, FolderID: &root, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, other); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}
	dup := &domain.Location{
		ID: domain.NewID(), LibraryID: lib, EntryID: other.ID,
		URL: "https://example.com/a", URLKey: "https://example.com/a", Lifecycle: domain.LocationActive,
	}
	if err := s.Locations().Upsert(ctx, dup); !errors.Is(err, domain.ErrDuplicateURLKey) {
		t.Fatalf("I6: the same url must not belong to two entries, got %v", err)
	}
}

// I8 makes two Sources reporting position 101 resolve to one logical Entry.
func TestOrdinalIsUniqueWithinACollection(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	col := &domain.Collection{
		ID: domain.NewID(), LibraryID: lib, FolderID: root, Name: "Work",
		OrderingBasis: domain.OrderExplicitNumericIndex, Lifecycle: domain.CollectionActive,
	}
	if err := s.Collections().Upsert(ctx, col); err != nil {
		t.Fatalf("upsert collection: %v", err)
	}

	n := 101.0
	first := &domain.Entry{ID: domain.NewID(), LibraryID: lib, CollectionID: &col.ID, Ordinal: &n, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, first); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}

	m := 101.0
	clash := &domain.Entry{ID: domain.NewID(), LibraryID: lib, CollectionID: &col.ID, Ordinal: &m, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, clash); !errors.Is(err, domain.ErrDuplicateOrdinal) {
		t.Fatalf("I8: two entries must not share an ordinal, got %v", err)
	}

	// 99.5 against 100 is the case the app must never resolve by guessing:
	// they stay two Entries.
	half := 99.5
	near := &domain.Entry{ID: domain.NewID(), LibraryID: lib, CollectionID: &col.ID, Ordinal: &half, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, near); err != nil {
		t.Fatalf("a distinct ordinal is a distinct entry: %v", err)
	}

	// An unplaced entry carries no ordinal and never collides with one.
	unplaced := &domain.Entry{ID: domain.NewID(), LibraryID: lib, CollectionID: &col.ID, Placement: domain.PlacementUnplaced}
	if err := s.Entries().Upsert(ctx, unplaced); err != nil {
		t.Fatalf("an unplaced entry must be storable: %v", err)
	}

	all, err := s.Entries().ForCollection(ctx, lib, col.ID)
	if err != nil {
		t.Fatalf("list entries: %v", err)
	}
	if len(all) != 3 {
		t.Fatalf("expected three entries, got %d", len(all))
	}
	if all[len(all)-1].Placement != domain.PlacementUnplaced {
		t.Fatal("unplaced entries sort after placed ones, not to the front")
	}
}

// I9: preference is a single pointer, and it must point inside the Collection.
func TestPreferredSourceMustBelongToItsCollection(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	mk := func(name string) *domain.Collection {
		c := &domain.Collection{
			ID: domain.NewID(), LibraryID: lib, FolderID: root, Name: name,
			OrderingBasis: domain.OrderExplicitNumericIndex, Lifecycle: domain.CollectionActive,
		}
		if err := s.Collections().Upsert(ctx, c); err != nil {
			t.Fatalf("upsert collection: %v", err)
		}
		return c
	}
	a, b := mk("A"), mk("B")

	src := &domain.Source{
		ID: domain.NewID(), LibraryID: lib, CollectionID: a.ID,
		Host: "example.com", PathKey: "/work", Language: "tr", Lifecycle: domain.SourceActive,
	}
	if err := s.Sources().Upsert(ctx, src); err != nil {
		t.Fatalf("upsert source: %v", err)
	}

	if err := s.Collections().SetPreferredSource(ctx, lib, a.ID, &src.ID); err != nil {
		t.Fatalf("a collection may prefer its own source: %v", err)
	}
	if err := s.Collections().SetPreferredSource(ctx, lib, b.ID, &src.ID); !errors.Is(err, domain.ErrPreferredSourceForeign) {
		t.Fatalf("I9: a foreign source must be refused, got %v", err)
	}

	found, err := s.Sources().ByIdentity(ctx, lib, "EXAMPLE.COM", "/WORK")
	if err != nil || found.ID != src.ID {
		t.Fatal("source identity is host plus path key, case-insensitively")
	}
}

// Pressing "download on mobile" twice must not queue two saves.
func TestDownloadRequestIsIdempotentAndSingleWinner(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	e := &domain.Entry{ID: domain.NewID(), LibraryID: lib, FolderID: &root, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, e); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}

	mk := func(key string) *domain.DownloadRequest {
		return &domain.DownloadRequest{
			ID: domain.NewID(), LibraryID: lib, EntryID: e.ID,
			State: domain.DownloadPending, IdempotencyKey: key, CreatedAt: time.Now(),
		}
	}

	first, err := s.DownloadRequests().Create(ctx, mk("k1"))
	if err != nil {
		t.Fatalf("create request: %v", err)
	}
	same, err := s.DownloadRequests().Create(ctx, mk("k1"))
	if err != nil || same.ID != first.ID {
		t.Fatal("the same idempotency key must return the same request")
	}
	other, err := s.DownloadRequests().Create(ctx, mk("k2"))
	if err != nil || other.ID != first.ID {
		t.Fatal("at most one non-terminal request per entry")
	}

	claimed, err := s.DownloadRequests().Claim(ctx, lib, first.ID, "phone")
	if err != nil || claimed.ClaimedByDevice != "phone" {
		t.Fatalf("the first device to claim wins: %v", err)
	}
	if _, err := s.DownloadRequests().Claim(ctx, lib, first.ID, "tablet"); !errors.Is(err, domain.ErrRequestClaimed) {
		t.Fatal("a losing claim must be told, not silently accepted")
	}

	// A capture the device refuses is a terminal state, and it changes nothing
	// about library membership.
	resolved, err := s.DownloadRequests().Resolve(ctx, lib, first.ID, domain.DownloadFailed, "restricted source")
	if err != nil || resolved.State != domain.DownloadFailed {
		t.Fatalf("resolve: %v", err)
	}
	if _, err := s.Entries().Get(ctx, lib, e.ID); err != nil {
		t.Fatal("I17: a failed download must not change library membership")
	}
}

// Reading state is last-write-wins on its own clock, so a stale write cannot
// clobber a newer one.
func TestReadingStateLastWriteWins(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	e := &domain.Entry{ID: domain.NewID(), LibraryID: lib, FolderID: &root, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, e); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}

	t0 := time.Date(2026, 8, 20, 10, 0, 0, 0, time.UTC)
	newer := &domain.ReadingState{EntryID: e.ID, LibraryID: lib, Status: domain.Unread, UpdatedAt: t0.Add(time.Hour)}
	if err := s.ReadingStates().Put(ctx, newer); err != nil {
		t.Fatalf("put: %v", err)
	}

	stale := &domain.ReadingState{EntryID: e.ID, LibraryID: lib, Status: domain.Completed, UpdatedAt: t0}
	if err := s.ReadingStates().Put(ctx, stale); err != nil {
		t.Fatalf("stale put must be a quiet no-op: %v", err)
	}

	got, err := s.ReadingStates().Get(ctx, lib, e.ID)
	if err != nil || got.Status != domain.Unread {
		t.Fatal("an older completion must not overwrite a newer mark-as-unread")
	}
}

// Measurements keep their (entry, source) scope and their own clock.
func TestMeasurementIsScopedAndKeepsNewestObservation(t *testing.T) {
	s, lib, root := newLibrary(t)
	ctx := context.Background()

	col := &domain.Collection{
		ID: domain.NewID(), LibraryID: lib, FolderID: root, Name: "Work",
		OrderingBasis: domain.OrderExplicitNumericIndex, Lifecycle: domain.CollectionActive,
	}
	if err := s.Collections().Upsert(ctx, col); err != nil {
		t.Fatalf("upsert collection: %v", err)
	}
	n := 1.0
	e := &domain.Entry{ID: domain.NewID(), LibraryID: lib, CollectionID: &col.ID, Ordinal: &n, Placement: domain.PlacementPlaced}
	if err := s.Entries().Upsert(ctx, e); err != nil {
		t.Fatalf("upsert entry: %v", err)
	}
	src := &domain.Source{
		ID: domain.NewID(), LibraryID: lib, CollectionID: col.ID,
		Host: "example.com", PathKey: "/work", Lifecycle: domain.SourceActive,
	}
	if err := s.Sources().Upsert(ctx, src); err != nil {
		t.Fatalf("upsert source: %v", err)
	}

	t0 := time.Date(2026, 8, 20, 10, 0, 0, 0, time.UTC)
	if err := s.Measurements().Put(ctx, &domain.Measurement{
		EntryID: e.ID, SourceID: src.ID, LibraryID: lib, Fraction: 0.6, ObservedAt: t0.Add(time.Hour),
	}); err != nil {
		t.Fatalf("put: %v", err)
	}
	if err := s.Measurements().Put(ctx, &domain.Measurement{
		EntryID: e.ID, SourceID: src.ID, LibraryID: lib, Fraction: 0.1, ObservedAt: t0,
	}); err != nil {
		t.Fatalf("stale put must be a quiet no-op: %v", err)
	}
	got, err := s.Measurements().Get(ctx, lib, e.ID, src.ID)
	if err != nil || got.Fraction != 0.6 {
		t.Fatal("an older observation must not overwrite a newer one")
	}

	// I12 at the API boundary: a measurement without a source is refused.
	if err := s.Measurements().Put(ctx, &domain.Measurement{
		EntryID: e.ID, LibraryID: lib, Fraction: 0.5, ObservedAt: t0,
	}); !errors.Is(err, domain.ErrMeasurementNeedsScope) {
		t.Fatalf("I12: a measurement must name its source, got %v", err)
	}
}

// Revisions are monotonic per library and are what a sync cursor points into.
func TestRevisionsAreMonotonicPerLibrary(t *testing.T) {
	s := newTestStore(t)
	ctx := context.Background()
	a, err := s.Libraries().EnsureByName(ctx, "a")
	if err != nil {
		t.Fatalf("ensure: %v", err)
	}
	b, err := s.Libraries().EnsureByName(ctx, "b")
	if err != nil {
		t.Fatalf("ensure: %v", err)
	}

	r1, err := s.Revisions().Next(ctx, a.ID)
	if err != nil {
		t.Fatalf("next: %v", err)
	}
	r2, err := s.Revisions().Next(ctx, a.ID)
	if err != nil {
		t.Fatalf("next: %v", err)
	}
	if r2 <= r1 {
		t.Fatal("revisions must advance")
	}
	rb, err := s.Revisions().Current(ctx, b.ID)
	if err != nil {
		t.Fatalf("current: %v", err)
	}
	if rb >= r2 {
		t.Fatal("revisions are per library, not global")
	}
}

// Tombstones answer "what was deliberately removed since my cursor".
func TestTombstonesSinceCursor(t *testing.T) {
	s, lib, _ := newLibrary(t)
	ctx := context.Background()

	e1, e2 := domain.NewID(), domain.NewID()
	if err := s.Tombstones().Add(ctx, domain.Tombstone{LibraryID: lib, Kind: domain.KindEntry, EntityID: e1, Revision: 5}); err != nil {
		t.Fatalf("add: %v", err)
	}
	if err := s.Tombstones().Add(ctx, domain.Tombstone{LibraryID: lib, Kind: domain.KindEntry, EntityID: e2, Revision: 9}); err != nil {
		t.Fatalf("add: %v", err)
	}

	got, err := s.Tombstones().Since(ctx, lib, 5)
	if err != nil {
		t.Fatalf("since: %v", err)
	}
	if len(got) != 1 || got[0].EntityID != e2 {
		t.Fatalf("a cursor at 5 must see only the revision-9 tombstone, got %d", len(got))
	}

	// Re-deleting the same entity keeps one tombstone at the newer revision.
	if err := s.Tombstones().Add(ctx, domain.Tombstone{LibraryID: lib, Kind: domain.KindEntry, EntityID: e1, Revision: 12}); err != nil {
		t.Fatalf("re-add: %v", err)
	}
	got, err = s.Tombstones().Since(ctx, lib, 0)
	if err != nil {
		t.Fatalf("since: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("one entity is one tombstone, got %d", len(got))
	}
}
