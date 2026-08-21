package api

// POST /mutations (B7) and GET /changes (B6), speaking the frozen contract.

import (
	"encoding/json"
	"strconv"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"

	syncsvc "github.com/mcagricaliskan/scrollary/backend/internal/sync"
)

type mutationEnvelopeBody struct {
	MutationID string          `json:"mutation_id"`
	EntityType string          `json:"entity_type"`
	EntityID   string          `json:"entity_id"`
	Op         string          `json:"op"`
	Fields     map[string]any  `json:"fields"`
	ClientTime string          `json:"client_time"`
	Extra      json.RawMessage `json:"-"`
}

type mutationsBody struct {
	Mutations []mutationEnvelopeBody `json:"mutations"`
}

type mutationResultDTO struct {
	MutationID string     `json:"mutation_id"`
	Outcome    string     `json:"outcome"`
	Revision   *int64     `json:"revision,omitempty"`
	Error      *errorBody `json:"error,omitempty"`
}

func (s *Server) pushMutations(c fiber.Ctx) error {
	lib := requestLibrary(c)

	var body mutationsBody
	if err := json.Unmarshal(c.Body(), &body); err != nil {
		return writeError(c, fiber.StatusBadRequest, "invalid_request",
			"The request body could not be parsed.", nil)
	}
	if body.Mutations == nil {
		return writeError(c, fiber.StatusBadRequest, "validation_failed",
			"mutations is required.", map[string]any{"field": "mutations"})
	}

	batch := make([]syncsvc.Envelope, 0, len(body.Mutations))
	for i, m := range body.Mutations {
		mid, err := uuid.Parse(m.MutationID)
		if err != nil {
			return writeError(c, fiber.StatusBadRequest, "validation_failed",
				"mutation_id must be a uuid.",
				map[string]any{"field": "mutation_id", "index": i})
		}
		eid, err := uuid.Parse(m.EntityID)
		if err != nil {
			return writeError(c, fiber.StatusBadRequest, "validation_failed",
				"entity_id must be a uuid.",
				map[string]any{"field": "entity_id", "index": i})
		}
		ct, err := time.Parse(time.RFC3339, m.ClientTime)
		if err != nil {
			return writeError(c, fiber.StatusBadRequest, "validation_failed",
				"client_time must be an RFC 3339 timestamp.",
				map[string]any{"field": "client_time", "index": i})
		}
		batch = append(batch, syncsvc.Envelope{
			MutationID: mid.String(),
			EntityType: m.EntityType,
			EntityID:   eid,
			Op:         m.Op,
			Fields:     m.Fields,
			ClientTime: ct,
		})
	}

	revision, results, err := s.sync.Apply(c.Context(), lib, batch)
	if err != nil {
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"The batch could not be applied.", nil)
	}

	out := make([]mutationResultDTO, 0, len(results))
	for _, r := range results {
		dto := mutationResultDTO{MutationID: r.MutationID, Outcome: r.Outcome}
		if r.Outcome != "rejected" {
			rev := int64(r.Revision)
			dto.Revision = &rev
		}
		if r.Rejection != nil {
			dto.Error = &errorBody{
				Code:    r.Rejection.Code,
				Message: r.Rejection.Message,
				Details: r.Rejection.Details,
			}
		}
		out = append(out, dto)
	}
	return c.JSON(fiber.Map{
		"library_revision": int64(revision),
		"results":          out,
	})
}

func (s *Server) pullChanges(c fiber.Ctx) error {
	lib := requestLibrary(c)

	cursorRaw := c.Query("cursor")
	if cursorRaw == "" {
		return writeError(c, fiber.StatusBadRequest, "invalid_cursor",
			"cursor is required; pass 0 for a full bootstrap.", nil)
	}
	cursor, err := strconv.ParseInt(cursorRaw, 10, 64)
	if err != nil || cursor < 0 {
		return writeError(c, fiber.StatusBadRequest, "invalid_cursor",
			"cursor must be a non-negative integer.", nil)
	}

	limit := 200
	if limitRaw := c.Query("limit"); limitRaw != "" {
		l, err := strconv.Atoi(limitRaw)
		if err != nil || l < 1 || l > 1000 {
			return writeError(c, fiber.StatusBadRequest, "validation_failed",
				"limit must be between 1 and 1000.", map[string]any{"field": "limit"})
		}
		limit = l
	}

	items, hasMore, err := s.store.Changes().Feed(c.Context(), lib, revisionOf(cursor), limit)
	if err != nil {
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"The change feed could not be read.", nil)
	}
	latest, err := s.store.Revisions().Current(c.Context(), lib)
	if err != nil {
		return writeError(c, fiber.StatusInternalServerError, "internal",
			"The library revision could not be read.", nil)
	}

	changes := make([]changeDTO, 0, len(items))
	nextCursor := cursor
	for _, item := range items {
		changes = append(changes, toChangeDTO(item))
		nextCursor = int64(item.Revision)
	}
	return c.JSON(fiber.Map{
		"changes":         changes,
		"next_cursor":     nextCursor,
		"latest_revision": int64(latest),
		"has_more":        hasMore,
	})
}
