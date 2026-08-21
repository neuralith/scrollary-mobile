// Package identity is the canonical-identity arbitrator (B8).
//
// Clients see pages; this package sees evidence. It answers which Collection,
// Source, Entry and Location a piece of submitted evidence is about, or
// answers `unresolved` — a first-class outcome, not an error — and it is
// deliberately conservative: equal ordinals merge, different ordinals stay two
// Entries, and ambiguity is kept rather than repaired (DECISIONS.md V2-D16).
//
// This package makes NO outbound request of any kind. It imports no HTTP
// client and no network package; everything it knows arrived in the request
// body or already lives in the store. That property carries the product's
// whole position (V2-D24) and must survive every future edit.
package identity

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage"
)

// Evidence is what one client observed on one page, decoded from the contract
// schema. Absent optional fields are nil — never defaulted, because a default
// is an invention.
type Evidence struct {
	URL             string
	URLKey          string
	Host            string
	PathKey         *string
	PageTitle       *string
	CollectionTitle *string
	SourceLabel     *string
	SourceNumber    *float64
	OrderingBasis   *domain.OrderingBasis
	Ordinal         *float64
	Language        *string
	ObservedAt      time.Time
}

// Provisional carries the ids a client minted while offline or ahead of
// arbitration, so the response can map exactly what was submitted.
type Provisional struct {
	CollectionID *uuid.UUID
	SourceID     *uuid.UUID
	EntryID      *uuid.UUID
	LocationID   *uuid.UUID
}

// Mapping resolves one submitted provisional id to canonical identity.
type Mapping struct {
	Kind          string // collection | source | entry | location
	ProvisionalID uuid.UUID
	CanonicalID   uuid.UUID
}

// Result is the arbitration outcome. Unresolved carries a named reason from
// the shared error vocabulary.
type Result struct {
	Outcome  string // resolved | unresolved
	Mappings []Mapping
	Reason   string
}

// Arbitrator decides identity over evidence and existing library state.
type Arbitrator struct {
	store storage.Store
}

func New(store storage.Store) *Arbitrator { return &Arbitrator{store: store} }

func unresolved(reason string) Result { return Result{Outcome: "unresolved", Reason: reason} }

// Arbitrate implements the conservative resolution ladder:
//
//  1. An exact url_key match resolves the Location and everything above it.
//     A URL the library knows IS that place; this is the server-side twin of
//     the client's local hot path.
//  2. A (host, path_key) match resolves the Source and its Collection. The
//     Entry then resolves only when the evidence carries an ordinal whose
//     basis is explicitNumericIndex, the Collection's own ordering basis
//     agrees, and exactly one Entry holds that ordinal.
//  3. Anything else is unresolved, with the refusal named.
func (a *Arbitrator) Arbitrate(ctx context.Context, lib domain.LibraryID, ev Evidence, prov Provisional) (Result, error) {
	// Contradictory evidence is refused before any lookup: a printed number
	// that disagrees with the submitted ordinal is exactly the 100-vs-99.5
	// case, and it is kept, not repaired.
	if ev.Ordinal != nil && ev.SourceNumber != nil && *ev.Ordinal != *ev.SourceNumber {
		return unresolved("conflicting_ordinals"), nil
	}

	if loc, err := a.store.Locations().ByURLKey(ctx, lib, ev.URLKey); err == nil {
		return a.resolveFromLocation(ctx, lib, loc, prov)
	} else if !errors.Is(err, domain.ErrNotFound) {
		return Result{}, err
	}

	if ev.PathKey != nil {
		src, err := a.store.Sources().ByIdentity(ctx, lib, ev.Host, *ev.PathKey)
		if err == nil {
			return a.resolveFromSource(ctx, lib, src, ev, prov)
		}
		if !errors.Is(err, domain.ErrNotFound) {
			return Result{}, err
		}
	}

	return unresolved("insufficient_evidence"), nil
}

func (a *Arbitrator) resolveFromLocation(ctx context.Context, lib domain.LibraryID, loc *domain.Location, prov Provisional) (Result, error) {
	var mappings []Mapping
	appendMapping(&mappings, "location", prov.LocationID, loc.ID)

	entry, err := a.store.Entries().Get(ctx, lib, loc.EntryID)
	if err != nil {
		return Result{}, err
	}
	appendMapping(&mappings, "entry", prov.EntryID, entry.ID)

	if loc.SourceID != nil {
		appendMapping(&mappings, "source", prov.SourceID, *loc.SourceID)
	}
	if entry.CollectionID != nil {
		appendMapping(&mappings, "collection", prov.CollectionID, *entry.CollectionID)
	}
	return resolvedOr(mappings), nil
}

func (a *Arbitrator) resolveFromSource(ctx context.Context, lib domain.LibraryID, src *domain.Source, ev Evidence, prov Provisional) (Result, error) {
	var mappings []Mapping
	appendMapping(&mappings, "source", prov.SourceID, src.ID)
	appendMapping(&mappings, "collection", prov.CollectionID, src.CollectionID)

	// The Entry may resolve by ordinal — and only by ordinal, only where both
	// the evidence's basis and the Collection's basis are the explicit numeric
	// index (V2-D16). Everything else leaves the Entry to the client's
	// provisional identity.
	if ev.Ordinal != nil {
		if ev.OrderingBasis == nil || *ev.OrderingBasis != domain.OrderExplicitNumericIndex {
			return unresolved("ordering_basis_unsupported"), nil
		}
		col, err := a.store.Collections().Get(ctx, lib, src.CollectionID)
		if err != nil {
			return Result{}, err
		}
		if !col.OrderingBasis.SupportsCrossSourceMerge() {
			return unresolved("ordering_basis_unsupported"), nil
		}
		entry, err := a.store.Entries().ByOrdinal(ctx, lib, src.CollectionID, *ev.Ordinal)
		if err == nil {
			appendMapping(&mappings, "entry", prov.EntryID, entry.ID)
		} else if !errors.Is(err, domain.ErrNotFound) {
			return Result{}, err
		}
		// No Entry at that ordinal: the evidence describes a genuinely new
		// Entry. The client's provisional id becomes canonical when pushed;
		// there is nothing to map it to, and inventing one would be a guess.
	}

	return resolvedOr(mappings), nil
}

// appendMapping records a mapping only when the client actually submitted a
// provisional id, and only when the mapping says something (a provisional id
// that already equals the canonical one carries no information).
func appendMapping(mappings *[]Mapping, kind string, provisional *uuid.UUID, canonical uuid.UUID) {
	if provisional == nil || *provisional == canonical {
		return
	}
	*mappings = append(*mappings, Mapping{Kind: kind, ProvisionalID: *provisional, CanonicalID: canonical})
}

// resolvedOr reports resolved when at least one submitted provisional id was
// mapped; with nothing to say, the honest outcome is unresolved.
func resolvedOr(mappings []Mapping) Result {
	if len(mappings) == 0 {
		return unresolved("insufficient_evidence")
	}
	return Result{Outcome: "resolved", Mappings: mappings}
}
