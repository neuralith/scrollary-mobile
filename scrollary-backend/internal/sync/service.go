// Package sync applies client mutation batches and assembles the change feed.
//
// It is the write half and the read half of metadata synchronisation, and it
// speaks the frozen contract exactly: envelope shapes, outcome vocabulary and
// error codes all come from contracts/openapi.yaml. It never fetches anything:
// everything it knows arrived in a request body.
package sync

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/neuralith/scrollary-backend/internal/domain"
	"github.com/neuralith/scrollary-backend/internal/storage"
)

// Envelope is one intent from a client's outbox, decoded.
type Envelope struct {
	MutationID string
	EntityType string
	EntityID   uuid.UUID
	Op         string
	Fields     map[string]any
	ClientTime time.Time
}

// Rejection names why a mutation was not applied, using the shared error
// vocabulary. Details is code-specific context.
type Rejection struct {
	Code    string
	Message string
	Details map[string]any
}

// Result is one per-mutation outcome.
type Result struct {
	MutationID string
	Outcome    string // applied | duplicate | rejected
	Revision   domain.Revision
	Rejection  *Rejection
}

// Service applies mutations against the store under the library's merge rules.
type Service struct {
	store storage.Store
}

func New(store storage.Store) *Service { return &Service{store: store} }

var entityTypes = map[string]domain.EntityKind{
	"folder":       domain.KindFolder,
	"collection":   domain.KindCollection,
	"source":       domain.KindSource,
	"entry":        domain.KindEntry,
	"location":     domain.KindLocation,
	"readingState": domain.KindReading,
	"measurement":  domain.KindMeasure,
	// downloadRequest is deliberately absent: intents have their own
	// synchronous endpoints, because single-winner semantics cannot ride an
	// asynchronous outbox.
}

// Apply runs a batch in order. Each envelope is applied on its own: a rejected
// envelope never poisons the rest of the batch.
func (s *Service) Apply(ctx context.Context, lib domain.LibraryID, batch []Envelope) (domain.Revision, []Result, error) {
	results := make([]Result, 0, len(batch))
	for i := range batch {
		results = append(results, s.applyOne(ctx, lib, &batch[i]))
	}
	current, err := s.store.Revisions().Current(ctx, lib)
	if err != nil {
		return 0, nil, err
	}
	return current, results, nil
}

func reject(mutationID, code, message string, details map[string]any) Result {
	return Result{
		MutationID: mutationID,
		Outcome:    "rejected",
		Rejection:  &Rejection{Code: code, Message: message, Details: details},
	}
}

func (s *Service) applyOne(ctx context.Context, lib domain.LibraryID, env *Envelope) Result {
	kind, ok := entityTypes[env.EntityType]
	if !ok {
		return reject(env.MutationID, "invalid_mutation",
			fmt.Sprintf("unknown entity_type %q", env.EntityType), nil)
	}
	if env.Op != "upsert" && env.Op != "delete" {
		return reject(env.MutationID, "invalid_mutation",
			fmt.Sprintf("unknown op %q", env.Op), nil)
	}

	// Idempotency: a mutation id the ledger knows produces one effect and the
	// same reply, carrying the originally assigned revision.
	if rec, err := s.store.Mutations().Get(ctx, lib, env.MutationID); err == nil {
		return Result{MutationID: env.MutationID, Outcome: "duplicate", Revision: rec.Revision}
	} else if !errors.Is(err, domain.ErrNotFound) {
		return reject(env.MutationID, "internal", err.Error(), nil)
	}

	rev, err := s.store.Revisions().Next(ctx, lib)
	if err != nil {
		return reject(env.MutationID, "internal", err.Error(), nil)
	}

	var rejection *Rejection
	if env.Op == "delete" {
		rejection = s.applyDelete(ctx, lib, kind, env, rev)
	} else {
		rejection = s.applyUpsert(ctx, lib, kind, env, rev)
	}
	if rejection != nil {
		return Result{MutationID: env.MutationID, Outcome: "rejected", Rejection: rejection}
	}

	if err := s.store.Mutations().Record(ctx, &storage.MutationRecord{
		LibraryID:  lib,
		MutationID: env.MutationID,
		Revision:   rev,
	}); err != nil {
		if errors.Is(err, domain.ErrAlreadyExists) {
			// A concurrent identical retry won the ledger race. Both writes
			// were last-write-wins on the same clock, so the effect is one;
			// answer as the duplicate we now know this to be.
			if rec, gerr := s.store.Mutations().Get(ctx, lib, env.MutationID); gerr == nil {
				return Result{MutationID: env.MutationID, Outcome: "duplicate", Revision: rec.Revision}
			}
		}
		return reject(env.MutationID, "internal", err.Error(), nil)
	}
	return Result{MutationID: env.MutationID, Outcome: "applied", Revision: rev}
}

// rejectionFor translates a named domain error into the contract vocabulary.
func rejectionFor(err error) *Rejection {
	switch {
	case errors.Is(err, domain.ErrNotFound):
		return &Rejection{Code: "unknown_entity", Message: "a referenced entity does not exist in this library"}
	case errors.Is(err, domain.ErrRootMustNotHaveParent),
		errors.Is(err, domain.ErrFolderMustHaveParent):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I1"}}
	case errors.Is(err, domain.ErrFolderCycle):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I2"}}
	case errors.Is(err, domain.ErrEntryPlacement):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I3"}}
	case errors.Is(err, domain.ErrCollectionNeedsFolder):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I4"}}
	case errors.Is(err, domain.ErrDuplicateURLKey):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I6"}}
	case errors.Is(err, domain.ErrLocationSourcePairing):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I7"}}
	case errors.Is(err, domain.ErrDuplicateOrdinal):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I8"}}
	case errors.Is(err, domain.ErrPreferredSourceForeign):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I9"}}
	case errors.Is(err, domain.ErrMeasurementNeedsScope):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I12"}}
	case errors.Is(err, domain.ErrAlreadyExists):
		return &Rejection{Code: "invariant_violation", Message: err.Error(), Details: map[string]any{"invariant": "I10"}}
	default:
		return &Rejection{Code: "internal", Message: err.Error()}
	}
}

// applyDelete removes the row and records the tombstone. A row that is already
// gone converges: the tombstone is (re)announced and the delete reports
// applied, because two devices removing the same thing agree.
func (s *Service) applyDelete(ctx context.Context, lib domain.LibraryID, kind domain.EntityKind, env *Envelope, rev domain.Revision) *Rejection {
	var err error
	switch kind {
	case domain.KindFolder:
		// A folder delete via sync uses the same conservative semantics as an
		// interactive one: children reparent, content survives (I5).
		_, err = s.store.Folders().Delete(ctx, lib, env.EntityID)
	case domain.KindCollection:
		err = s.store.Collections().Delete(ctx, lib, env.EntityID)
	case domain.KindSource:
		err = s.store.Sources().Delete(ctx, lib, env.EntityID)
	case domain.KindEntry:
		err = s.store.Entries().Delete(ctx, lib, env.EntityID)
	case domain.KindLocation:
		err = s.store.Locations().Delete(ctx, lib, env.EntityID)
	case domain.KindReading:
		err = s.store.ReadingStates().Delete(ctx, lib, env.EntityID)
	case domain.KindMeasure:
		source, rej := fieldUUID(env.Fields, "source_id", true)
		if rej != nil {
			return rej
		}
		err = s.store.Measurements().Delete(ctx, lib, env.EntityID, *source)
	}
	if err != nil && !errors.Is(err, domain.ErrNotFound) {
		return rejectionFor(err)
	}
	if terr := s.store.Tombstones().Add(ctx, domain.Tombstone{
		LibraryID: lib,
		Kind:      kind,
		EntityID:  env.EntityID,
		Revision:  rev,
		DeletedAt: env.ClientTime,
	}); terr != nil {
		return rejectionFor(terr)
	}
	return nil
}
