package domain

import (
	"errors"
	"testing"
	"time"
)

func TestFolderRootHasNoParent(t *testing.T) {
	root := Folder{ID: NewID(), Kind: FolderRoot}
	if err := root.Validate(); err != nil {
		t.Fatalf("a root with no parent must be valid: %v", err)
	}

	parent := NewID()
	bad := Folder{ID: NewID(), Kind: FolderRoot, ParentID: &parent}
	if !errors.Is(bad.Validate(), ErrRootMustNotHaveParent) {
		t.Fatal("I1: a root folder must not have a parent")
	}
}

func TestUserFolderMustHaveParent(t *testing.T) {
	orphan := Folder{ID: NewID(), Kind: FolderUser}
	if !errors.Is(orphan.Validate(), ErrFolderMustHaveParent) {
		t.Fatal("I1: a non-root folder must have a parent")
	}

	self := NewID()
	cyclic := Folder{ID: self, Kind: FolderUser, ParentID: &self}
	if !errors.Is(cyclic.Validate(), ErrFolderCycle) {
		t.Fatal("I2: a folder may not be its own parent")
	}
}

// I3 is the invariant that keeps a standalone Entry a first-class library item
// rather than something wrapped in a Collection of one to fit the model.
func TestEntryHasFolderIffStandalone(t *testing.T) {
	folder := NewID()
	collection := NewID()

	standalone := Entry{ID: NewID(), FolderID: &folder, Placement: PlacementPlaced}
	if err := standalone.Validate(); err != nil {
		t.Fatalf("a standalone entry in a folder must be valid: %v", err)
	}
	if !standalone.Standalone() {
		t.Fatal("an entry with no collection is standalone")
	}

	inCollection := Entry{ID: NewID(), CollectionID: &collection, Placement: PlacementPlaced}
	if err := inCollection.Validate(); err != nil {
		t.Fatalf("an entry in a collection needs no folder of its own: %v", err)
	}

	both := Entry{ID: NewID(), CollectionID: &collection, FolderID: &folder}
	if !errors.Is(both.Validate(), ErrEntryPlacement) {
		t.Fatal("I3: an entry must not have both a collection and a folder")
	}

	neither := Entry{ID: NewID()}
	if !errors.Is(neither.Validate(), ErrEntryPlacement) {
		t.Fatal("I3: an entry must have one of a collection or a folder")
	}
}

// I7: a Location belongs to a Source exactly when its Entry belongs to a
// Collection. A standalone Entry's Location has no Source to belong to.
func TestLocationSourcePairing(t *testing.T) {
	collection, folder, source := NewID(), NewID(), NewID()

	collected := Entry{ID: NewID(), CollectionID: &collection, Placement: PlacementPlaced}
	loc := Location{URLKey: "https://example.com/a", SourceID: &source}
	if err := loc.ValidateAgainstEntry(collected); err != nil {
		t.Fatalf("a collected entry's location may name a source: %v", err)
	}

	standalone := Entry{ID: NewID(), FolderID: &folder, Placement: PlacementPlaced}
	if !errors.Is(loc.ValidateAgainstEntry(standalone), ErrLocationSourcePairing) {
		t.Fatal("I7: a standalone entry's location must not name a source")
	}

	bare := Location{URLKey: "https://example.com/b"}
	if err := bare.ValidateAgainstEntry(standalone); err != nil {
		t.Fatalf("a standalone location without a source must be valid: %v", err)
	}
	if !errors.Is(bare.ValidateAgainstEntry(collected), ErrLocationSourcePairing) {
		t.Fatal("I7: a collected entry's location must name a source")
	}
}

// Cross-source merging is available only where the source numbers its content
// explicitly. Everywhere else, Sources coexist and Entries are not merged --
// Scrollary does not pretend every website can be normalised.
func TestOnlyNumericOrderingSupportsCrossSourceMerge(t *testing.T) {
	if !OrderExplicitNumericIndex.SupportsCrossSourceMerge() {
		t.Fatal("an explicit numeric index is what equivalence keys on")
	}
	for _, basis := range []OrderingBasis{
		OrderPublicationDate, OrderDetectedNextLink,
		OrderDiscoveryOrder, OrderUserDefinedManual,
	} {
		if basis.SupportsCrossSourceMerge() {
			t.Fatalf("%s has nothing reliable to match on", basis)
		}
	}
}

// I16: opening an Entry at its source is access, never completion. Completion
// is only ever reached automatically inside Scrollary's own reader, where
// position is measured.
func TestSourceAccessNeverCompletes(t *testing.T) {
	at := time.Date(2026, 8, 20, 10, 0, 0, 0, time.UTC)

	r := ReadingState{EntryID: NewID(), Status: Unread}
	r.RecordSourceAccess(at)

	if r.Status != Reading {
		t.Fatalf("source access moves unread to reading, got %s", r.Status)
	}
	if r.CompletedAt != nil {
		t.Fatal("I16: source access must never infer completion")
	}
	if r.FirstOpenedAt == nil || !r.FirstOpenedAt.Equal(at) {
		t.Fatal("source access records when the entry was first opened")
	}

	later := at.Add(time.Hour)
	r.RecordSourceAccess(later)
	if !r.FirstOpenedAt.Equal(at) {
		t.Fatal("first opened is not overwritten by a later visit")
	}
	if !r.LastReadAt.Equal(later) {
		t.Fatal("last read follows the most recent visit")
	}
}

// A completed Entry that is later marked unread must be expressible: completion
// is a value, not a floor.
func TestCompletionIsRevertible(t *testing.T) {
	at := time.Now()
	r := ReadingState{EntryID: NewID(), Status: Completed, CompletedAt: &at}
	r.Status = Unread
	r.CompletedAt = nil
	if r.Status != Unread || r.CompletedAt != nil {
		t.Fatal("marking unread must be able to undo completion")
	}
}

// I12: a measurement is meaningless without the rendering it was taken against.
func TestMeasurementRequiresScope(t *testing.T) {
	unscoped := Measurement{EntryID: NewID(), Fraction: 0.6}
	if !errors.Is(unscoped.Validate(), ErrMeasurementNeedsScope) {
		t.Fatal("I12: a measurement must name its source")
	}
	scoped := Measurement{EntryID: NewID(), SourceID: NewID(), Fraction: 0.6}
	if err := scoped.Validate(); err != nil {
		t.Fatalf("a scoped measurement is valid: %v", err)
	}
}

// The claim transition has exactly one winner, and the loser is told rather
// than silently proceeding.
func TestDownloadRequestClaimHasOneWinner(t *testing.T) {
	at := time.Now()
	d := DownloadRequest{ID: NewID(), State: DownloadPending}

	if err := d.Claim("phone", at); err != nil {
		t.Fatalf("the first claim wins: %v", err)
	}
	if d.State != DownloadClaimed || d.ClaimedByDevice != "phone" {
		t.Fatal("a claim records which device took it")
	}
	if !errors.Is(d.Claim("tablet", at), ErrRequestClaimed) {
		t.Fatal("a second claim must be refused, not silently accepted")
	}
}

func TestDownloadRequestResolvesOnlyToTerminalStates(t *testing.T) {
	d := DownloadRequest{ID: NewID(), State: DownloadClaimed}
	if err := d.Resolve(DownloadPending, "", time.Now()); err == nil {
		t.Fatal("resolving to a non-terminal state is not a resolution")
	}
	if err := d.Resolve(DownloadFailed, "restricted source", time.Now()); err != nil {
		t.Fatalf("a device may report failure: %v", err)
	}
	if d.FailureReason != "restricted source" {
		t.Fatal("the reason a capture refused is carried back")
	}
}

func TestCollectionFollowedMeansActive(t *testing.T) {
	c := Collection{ID: NewID(), FolderID: NewID(), Lifecycle: CollectionActive}
	if !c.Followed() {
		t.Fatal("a collection in the library is followed")
	}
	c.Lifecycle = CollectionArchived
	if c.Followed() {
		t.Fatal("archiving is how following stops")
	}
	if err := (Collection{ID: NewID()}).Validate(); !errors.Is(err, ErrCollectionNeedsFolder) {
		t.Fatal("I4: every collection has a folder")
	}
}

func TestDeadSourceIsNotReadable(t *testing.T) {
	if !(Source{Lifecycle: SourceActive}).Readable() {
		t.Fatal("an active source is readable")
	}
	if (Source{Lifecycle: SourceDead}).Readable() {
		t.Fatal("a dead source is not readable")
	}
	if (Source{Lifecycle: SourceResolvedInto}).Readable() {
		t.Fatal("a source that moved elsewhere is read through its successor")
	}
}
