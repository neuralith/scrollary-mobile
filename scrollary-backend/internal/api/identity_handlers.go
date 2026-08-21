package api

// POST /identity/arbitrate (B8) and POST /entries/{entry_id}/placement (B9).

import (
	"encoding/json"
	"errors"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"

	"github.com/neuralith/scrollary-backend/internal/domain"
	"github.com/neuralith/scrollary-backend/internal/identity"
	"github.com/neuralith/scrollary-backend/internal/storage"
)

func revisionOf(v int64) domain.Revision { return domain.Revision(v) }

type evidenceBody struct {
	URL             string   `json:"url"`
	URLKey          string   `json:"url_key"`
	Host            string   `json:"host"`
	PathKey         *string  `json:"path_key"`
	PageTitle       *string  `json:"page_title"`
	CollectionTitle *string  `json:"collection_title"`
	SourceLabel     *string  `json:"source_label"`
	SourceNumber    *float64 `json:"source_number"`
	OrderingBasis   *string  `json:"ordering_basis"`
	Ordinal         *float64 `json:"ordinal"`
	Language        *string  `json:"language"`
	ObservedAt      string   `json:"observed_at"`
}

type provisionalBody struct {
	CollectionID *string `json:"collection_id"`
	SourceID     *string `json:"source_id"`
	EntryID      *string `json:"entry_id"`
	LocationID   *string `json:"location_id"`
}

type arbitrationBody struct {
	Evidence    *evidenceBody    `json:"evidence"`
	Provisional *provisionalBody `json:"provisional"`
}

type mappingDTO struct {
	Kind          string    `json:"kind"`
	ProvisionalID domain.ID `json:"provisional_id"`
	CanonicalID   domain.ID `json:"canonical_id"`
}

func parseOptionalUUID(raw *string, field string) (*uuid.UUID, *errorBody) {
	if raw == nil {
		return nil, nil
	}
	id, err := uuid.Parse(*raw)
	if err != nil {
		return nil, &errorBody{Code: "validation_failed",
			Message: field + " must be a uuid.", Details: map[string]any{"field": field}}
	}
	return &id, nil
}

func (s *Server) arbitrateIdentity(c fiber.Ctx) error {
	lib := requestLibrary(c)

	var body arbitrationBody
	if err := json.Unmarshal(c.Body(), &body); err != nil {
		return writeError(c, fiber.StatusBadRequest, "invalid_request",
			"The request body could not be parsed.", nil)
	}
	if body.Evidence == nil {
		return writeError(c, fiber.StatusBadRequest, "validation_failed",
			"evidence is required.", map[string]any{"field": "evidence"})
	}
	ev := body.Evidence
	for field, value := range map[string]string{
		"url": ev.URL, "url_key": ev.URLKey, "host": ev.Host, "observed_at": ev.ObservedAt,
	} {
		if value == "" {
			return writeError(c, fiber.StatusBadRequest, "validation_failed",
				field+" is required.", map[string]any{"field": field})
		}
	}
	observedAt, err := time.Parse(time.RFC3339, ev.ObservedAt)
	if err != nil {
		return writeError(c, fiber.StatusBadRequest, "validation_failed",
			"observed_at must be an RFC 3339 timestamp.", map[string]any{"field": "observed_at"})
	}

	var basis *domain.OrderingBasis
	if ev.OrderingBasis != nil {
		b := domain.OrderingBasis(*ev.OrderingBasis)
		switch b {
		case domain.OrderExplicitNumericIndex, domain.OrderPublicationDate,
			domain.OrderDetectedNextLink, domain.OrderDiscoveryOrder,
			domain.OrderUserDefinedManual:
			basis = &b
		default:
			return writeError(c, fiber.StatusBadRequest, "validation_failed",
				"ordering_basis is not a known basis.", map[string]any{"field": "ordering_basis"})
		}
	}
	// The contract's central evidence rule: an ordinal may only be submitted
	// with the explicit numeric index basis. Anything else is an invention.
	if ev.Ordinal != nil && (basis == nil || *basis != domain.OrderExplicitNumericIndex) {
		return writeError(c, fiber.StatusBadRequest, "validation_failed",
			"ordinal requires ordering_basis explicitNumericIndex.",
			map[string]any{"field": "ordinal"})
	}

	prov := identity.Provisional{}
	if body.Provisional != nil {
		for field, pair := range map[string]struct {
			raw *string
			dst **uuid.UUID
		}{
			"collection_id": {body.Provisional.CollectionID, &prov.CollectionID},
			"source_id":     {body.Provisional.SourceID, &prov.SourceID},
			"entry_id":      {body.Provisional.EntryID, &prov.EntryID},
			"location_id":   {body.Provisional.LocationID, &prov.LocationID},
		} {
			id, errBody := parseOptionalUUID(pair.raw, "provisional."+field)
			if errBody != nil {
				return c.Status(fiber.StatusBadRequest).JSON(errorResponse{Error: *errBody})
			}
			*pair.dst = id
		}
	}

	result, err := s.arbitrator.Arbitrate(c.Context(), lib, identity.Evidence{
		URL: ev.URL, URLKey: ev.URLKey, Host: ev.Host, PathKey: ev.PathKey,
		PageTitle: ev.PageTitle, CollectionTitle: ev.CollectionTitle,
		SourceLabel: ev.SourceLabel, SourceNumber: ev.SourceNumber,
		OrderingBasis: basis, Ordinal: ev.Ordinal, Language: ev.Language,
		ObservedAt: observedAt,
	}, prov)
	if err != nil {
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"Arbitration failed.", nil)
	}

	out := fiber.Map{"outcome": result.Outcome}
	if result.Outcome == "resolved" {
		mappings := make([]mappingDTO, 0, len(result.Mappings))
		for _, m := range result.Mappings {
			mappings = append(mappings, mappingDTO{
				Kind: m.Kind, ProvisionalID: m.ProvisionalID, CanonicalID: m.CanonicalID,
			})
		}
		out["mappings"] = mappings
	} else if result.Reason != "" {
		out["reason"] = result.Reason
	}
	return c.JSON(out)
}

type placementBody struct {
	Ordinal    *float64 `json:"ordinal"`
	MutationID *string  `json:"mutation_id"`
}

func (s *Server) placeEntry(c fiber.Ctx) error {
	lib := requestLibrary(c)

	entryID, err := uuid.Parse(c.Params("entry_id"))
	if err != nil {
		return writeError(c, fiber.StatusBadRequest, "validation_failed",
			"entry_id must be a uuid.", map[string]any{"field": "entry_id"})
	}
	var body placementBody
	if err := json.Unmarshal(c.Body(), &body); err != nil {
		return writeError(c, fiber.StatusBadRequest, "invalid_request",
			"The request body could not be parsed.", nil)
	}
	if body.Ordinal == nil {
		return writeError(c, fiber.StatusBadRequest, "validation_failed",
			"ordinal is required.", map[string]any{"field": "ordinal"})
	}

	// A retried placement is idempotent through the same ledger mutations use.
	var mutationID string
	if body.MutationID != nil {
		mid, err := uuid.Parse(*body.MutationID)
		if err != nil {
			return writeError(c, fiber.StatusBadRequest, "validation_failed",
				"mutation_id must be a uuid.", map[string]any{"field": "mutation_id"})
		}
		mutationID = mid.String()
		if _, lerr := s.store.Mutations().Get(c.Context(), lib, mutationID); lerr == nil {
			entry, gerr := s.store.Entries().Get(c.Context(), lib, entryID)
			if gerr != nil {
				return writeError(c, fiber.StatusNotFound, "unknown_entity",
					"No such entry in this library.", nil)
			}
			latest, rerr := s.store.Revisions().Current(c.Context(), lib)
			if rerr != nil {
				return writeError(c, fiber.StatusInternalServerError, "internal",
					"The library revision could not be read.", nil)
			}
			return c.JSON(fiber.Map{
				"entry":            toEntryDTO(entry),
				"library_revision": int64(latest),
			})
		}
	}

	rev, err := s.store.Revisions().Next(c.Context(), lib)
	if err != nil {
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"A revision could not be assigned.", nil)
	}

	placed, holder, err := s.store.Entries().Place(c.Context(), lib, entryID, *body.Ordinal, rev)
	switch {
	case err == nil:
		// fallthrough to the success reply below
	case errors.Is(err, domain.ErrNotFound):
		return writeError(c, fiber.StatusNotFound, "unknown_entity",
			"No such entry in this library.", nil)
	case errors.Is(err, domain.ErrPlacementUnsupported):
		return writeError(c, fiber.StatusConflict, "invalid_placement",
			"This collection's ordering basis does not support ordinal placement.", nil)
	case errors.Is(err, domain.ErrDuplicateOrdinal):
		details := map[string]any{}
		if holder != nil {
			details["current_entry_id"] = holder.ID.String()
			if holder.Ordinal != nil {
				details["current_ordinal"] = *holder.Ordinal
			}
		}
		return writeError(c, fiber.StatusConflict, "placement_conflict",
			"Another device already placed an Entry at this position.", details)
	default:
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"Placement failed.", nil)
	}

	if mutationID != "" {
		if lerr := s.store.Mutations().Record(c.Context(), &storage.MutationRecord{
			LibraryID: lib, MutationID: mutationID, Revision: rev,
		}); lerr != nil && !errors.Is(lerr, domain.ErrAlreadyExists) {
			return writeError(c, fiber.StatusInternalServerError, "internal",
				"The placement ledger entry could not be recorded.", nil)
		}
	}

	latest, err := s.store.Revisions().Current(c.Context(), lib)
	if err != nil {
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"The library revision could not be read.", nil)
	}
	return c.JSON(fiber.Map{
		"entry":            toEntryDTO(placed),
		"library_revision": int64(latest),
	})
}
