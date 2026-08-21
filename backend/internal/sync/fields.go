package sync

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

// The sparse-upsert appliers.
//
// `fields` carries only what changed (full row on create), with the vocabulary
// of the entity's contract schema minus id, revision and updated_at, which the
// server owns. Three states matter per key: absent (keep), null (clear), value
// (set). Unknown keys are rejected rather than ignored - silently dropping a
// field is how two clients drift apart without anyone noticing.

func rejectField(key, why string) *Rejection {
	return &Rejection{
		Code:    "validation_failed",
		Message: fmt.Sprintf("field %q %s", key, why),
		Details: map[string]any{"field": key},
	}
}

func fieldString(fields map[string]any, key string) (*string, *Rejection) {
	v, ok := fields[key]
	if !ok {
		return nil, nil
	}
	s, ok := v.(string)
	if !ok {
		return nil, rejectField(key, "must be a string")
	}
	return &s, nil
}

func fieldNumber(fields map[string]any, key string) (*float64, bool, *Rejection) {
	v, ok := fields[key]
	if !ok {
		return nil, false, nil
	}
	if v == nil {
		return nil, true, nil
	}
	f, ok := v.(float64)
	if !ok {
		return nil, false, rejectField(key, "must be a number")
	}
	return &f, true, nil
}

func fieldInt(fields map[string]any, key string) (*int64, *Rejection) {
	f, present, rej := fieldNumber(fields, key)
	if rej != nil || !present {
		return nil, rej
	}
	if f == nil {
		return nil, rejectField(key, "must not be null")
	}
	i := int64(*f)
	return &i, nil
}

// fieldUUID reads a uuid-valued key. present reports whether the key appeared;
// a null value returns (nil, true). required makes both absence and null a
// rejection.
func fieldUUID(fields map[string]any, key string, required bool) (*uuid.UUID, *Rejection) {
	v, ok := fields[key]
	if !ok || v == nil {
		if required {
			return nil, rejectField(key, "is required")
		}
		return nil, nil
	}
	s, ok := v.(string)
	if !ok {
		return nil, rejectField(key, "must be a uuid string")
	}
	id, err := uuid.Parse(s)
	if err != nil {
		return nil, rejectField(key, "must be a uuid")
	}
	return &id, nil
}

func fieldTime(fields map[string]any, key string) (*time.Time, bool, *Rejection) {
	v, ok := fields[key]
	if !ok {
		return nil, false, nil
	}
	if v == nil {
		return nil, true, nil
	}
	s, ok := v.(string)
	if !ok {
		return nil, false, rejectField(key, "must be an RFC 3339 timestamp")
	}
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return nil, false, rejectField(key, "must be an RFC 3339 timestamp")
	}
	return &t, true, nil
}

func unknownKeys(fields map[string]any, allowed ...string) *Rejection {
	set := map[string]bool{}
	for _, k := range allowed {
		set[k] = true
	}
	for k := range fields {
		if !set[k] {
			return rejectField(k, "is not part of this entity's vocabulary")
		}
	}
	return nil
}

// applyUpsert loads the current row (or starts a fresh one), merges the sparse
// fields, validates, stamps the client clock and the assigned revision, and
// writes through the store, whose last-write-wins gate does the merging.
func (s *Service) applyUpsert(ctx context.Context, lib domain.LibraryID, kind domain.EntityKind, env *Envelope, rev domain.Revision) *Rejection {
	switch kind {
	case domain.KindFolder:
		return s.upsertFolder(ctx, lib, env, rev)
	case domain.KindCollection:
		return s.upsertCollection(ctx, lib, env, rev)
	case domain.KindSource:
		return s.upsertSource(ctx, lib, env, rev)
	case domain.KindEntry:
		return s.upsertEntry(ctx, lib, env, rev)
	case domain.KindLocation:
		return s.upsertLocation(ctx, lib, env, rev)
	case domain.KindReading:
		return s.upsertReadingState(ctx, lib, env, rev)
	case domain.KindMeasure:
		return s.upsertMeasurement(ctx, lib, env, rev)
	}
	return &Rejection{Code: "invalid_mutation", Message: "unhandled entity type"}
}

func (s *Service) upsertFolder(ctx context.Context, lib domain.LibraryID, env *Envelope, rev domain.Revision) *Rejection {
	if rej := unknownKeys(env.Fields, "parent_id", "kind", "name", "sort_key"); rej != nil {
		return rej
	}
	row := &domain.Folder{ID: env.EntityID, LibraryID: lib, Kind: domain.FolderUser}
	if existing, err := s.store.Folders().Get(ctx, lib, env.EntityID); err == nil {
		copied := *existing
		row = &copied
	} else if !errors.Is(err, domain.ErrNotFound) {
		return rejectionFor(err)
	}

	if v, rej := fieldString(env.Fields, "kind"); rej != nil {
		return rej
	} else if v != nil {
		k := domain.FolderKind(*v)
		if k != domain.FolderRoot && k != domain.FolderUser {
			return rejectField("kind", "must be root or user")
		}
		row.Kind = k
	}
	if v, ok := env.Fields["parent_id"]; ok {
		if v == nil {
			row.ParentID = nil
		} else {
			id, rej := fieldUUID(env.Fields, "parent_id", false)
			if rej != nil {
				return rej
			}
			row.ParentID = id
		}
	}
	if v, rej := fieldString(env.Fields, "name"); rej != nil {
		return rej
	} else if v != nil {
		row.Name = *v
	}
	if v, rej := fieldInt(env.Fields, "sort_key"); rej != nil {
		return rej
	} else if v != nil {
		row.SortKey = *v
	}

	row.Revision = rev
	row.UpdatedAt = env.ClientTime
	if err := s.store.Folders().Upsert(ctx, row); err != nil {
		return rejectionFor(err)
	}
	return nil
}

func (s *Service) upsertCollection(ctx context.Context, lib domain.LibraryID, env *Envelope, rev domain.Revision) *Rejection {
	if rej := unknownKeys(env.Fields, "folder_id", "name", "detected_title",
		"ordering_basis", "lifecycle", "preferred_source_id", "sort_key"); rej != nil {
		return rej
	}
	created := false
	row := &domain.Collection{ID: env.EntityID, LibraryID: lib, Lifecycle: domain.CollectionActive}
	if existing, err := s.store.Collections().Get(ctx, lib, env.EntityID); err == nil {
		copied := *existing
		row = &copied
	} else if errors.Is(err, domain.ErrNotFound) {
		created = true
	} else {
		return rejectionFor(err)
	}

	if id, rej := fieldUUID(env.Fields, "folder_id", created); rej != nil {
		return rej
	} else if id != nil {
		row.FolderID = *id
	}
	if v, rej := fieldString(env.Fields, "name"); rej != nil {
		return rej
	} else if v != nil {
		row.Name = *v
	}
	if v, rej := fieldString(env.Fields, "detected_title"); rej != nil {
		return rej
	} else if v != nil {
		row.DetectedTitle = *v
	}
	if v, rej := fieldString(env.Fields, "ordering_basis"); rej != nil {
		return rej
	} else if v != nil {
		basis := domain.OrderingBasis(*v)
		switch basis {
		case domain.OrderExplicitNumericIndex, domain.OrderPublicationDate,
			domain.OrderDetectedNextLink, domain.OrderDiscoveryOrder,
			domain.OrderUserDefinedManual:
			row.OrderingBasis = basis
		default:
			return rejectField("ordering_basis", "is not a known basis")
		}
	} else if created {
		return rejectField("ordering_basis", "is required")
	}
	if v, rej := fieldString(env.Fields, "lifecycle"); rej != nil {
		return rej
	} else if v != nil {
		lc := domain.CollectionLifecycle(*v)
		if lc != domain.CollectionActive && lc != domain.CollectionArchived {
			return rejectField("lifecycle", "must be active or archived")
		}
		row.Lifecycle = lc
	}
	if v, ok := env.Fields["preferred_source_id"]; ok {
		if v == nil {
			row.PreferredSourceID = nil
		} else {
			id, rej := fieldUUID(env.Fields, "preferred_source_id", false)
			if rej != nil {
				return rej
			}
			// I9: the preferred source must belong to this collection. The
			// schema's composite foreign key enforces it on Postgres; checking
			// here keeps both stores identical and the error named.
			src, err := s.store.Sources().Get(ctx, lib, *id)
			if err != nil || src.CollectionID != row.ID {
				return rejectionFor(domain.ErrPreferredSourceForeign)
			}
			row.PreferredSourceID = id
		}
	}
	if v, rej := fieldInt(env.Fields, "sort_key"); rej != nil {
		return rej
	} else if v != nil {
		row.SortKey = *v
	}

	row.Revision = rev
	row.UpdatedAt = env.ClientTime
	if err := s.store.Collections().Upsert(ctx, row); err != nil {
		return rejectionFor(err)
	}
	return nil
}

func (s *Service) upsertSource(ctx context.Context, lib domain.LibraryID, env *Envelope, rev domain.Revision) *Rejection {
	if rej := unknownKeys(env.Fields, "collection_id", "host", "path_key", "language",
		"lifecycle", "resolved_into_source_id", "first_seen_at", "last_seen_at"); rej != nil {
		return rej
	}
	created := false
	row := &domain.Source{ID: env.EntityID, LibraryID: lib, Lifecycle: domain.SourceActive}
	if existing, err := s.store.Sources().Get(ctx, lib, env.EntityID); err == nil {
		copied := *existing
		row = &copied
	} else if errors.Is(err, domain.ErrNotFound) {
		created = true
	} else {
		return rejectionFor(err)
	}

	if id, rej := fieldUUID(env.Fields, "collection_id", created); rej != nil {
		return rej
	} else if id != nil {
		row.CollectionID = *id
	}
	for key, dst := range map[string]*string{
		"host": &row.Host, "path_key": &row.PathKey, "language": &row.Language,
	} {
		if v, rej := fieldString(env.Fields, key); rej != nil {
			return rej
		} else if v != nil {
			*dst = *v
		}
	}
	if created && (row.Host == "" || row.PathKey == "") {
		return rejectField("host", "and path_key are required to create a source")
	}
	if v, rej := fieldString(env.Fields, "lifecycle"); rej != nil {
		return rej
	} else if v != nil {
		lc := domain.SourceLifecycle(*v)
		switch lc {
		case domain.SourceActive, domain.SourceDormant, domain.SourceDead, domain.SourceResolvedInto:
			row.Lifecycle = lc
		default:
			return rejectField("lifecycle", "is not a known lifecycle")
		}
	}
	if v, ok := env.Fields["resolved_into_source_id"]; ok {
		if v == nil {
			row.ResolvedIntoSourceID = nil
		} else {
			id, rej := fieldUUID(env.Fields, "resolved_into_source_id", false)
			if rej != nil {
				return rej
			}
			row.ResolvedIntoSourceID = id
		}
	}
	if t, present, rej := fieldTime(env.Fields, "first_seen_at"); rej != nil {
		return rej
	} else if present && t != nil {
		row.FirstSeenAt = *t
	}
	if t, present, rej := fieldTime(env.Fields, "last_seen_at"); rej != nil {
		return rej
	} else if present && t != nil {
		row.LastSeenAt = *t
	}
	if created {
		if row.FirstSeenAt.IsZero() {
			row.FirstSeenAt = env.ClientTime
		}
		if row.LastSeenAt.IsZero() {
			row.LastSeenAt = env.ClientTime
		}
	}

	row.Revision = rev
	row.UpdatedAt = env.ClientTime
	if err := s.store.Sources().Upsert(ctx, row); err != nil {
		return rejectionFor(err)
	}
	return nil
}

func (s *Service) upsertEntry(ctx context.Context, lib domain.LibraryID, env *Envelope, rev domain.Revision) *Rejection {
	if rej := unknownKeys(env.Fields, "collection_id", "folder_id", "ordinal",
		"placement", "title", "sort_key"); rej != nil {
		return rej
	}
	created := false
	row := &domain.Entry{ID: env.EntityID, LibraryID: lib}
	if existing, err := s.store.Entries().Get(ctx, lib, env.EntityID); err == nil {
		copied := *existing
		row = &copied
	} else if errors.Is(err, domain.ErrNotFound) {
		created = true
	} else {
		return rejectionFor(err)
	}

	if v, ok := env.Fields["collection_id"]; ok {
		if v == nil {
			row.CollectionID = nil
		} else {
			id, rej := fieldUUID(env.Fields, "collection_id", false)
			if rej != nil {
				return rej
			}
			row.CollectionID = id
		}
	}
	if v, ok := env.Fields["folder_id"]; ok {
		if v == nil {
			row.FolderID = nil
		} else {
			id, rej := fieldUUID(env.Fields, "folder_id", false)
			if rej != nil {
				return rej
			}
			row.FolderID = id
		}
	}
	if f, present, rej := fieldNumber(env.Fields, "ordinal"); rej != nil {
		return rej
	} else if present {
		row.Ordinal = f
	}
	if v, rej := fieldString(env.Fields, "placement"); rej != nil {
		return rej
	} else if v != nil {
		p := domain.Placement(*v)
		switch p {
		case domain.PlacementPlaced, domain.PlacementUnplaced, domain.PlacementUser:
			row.Placement = p
		default:
			return rejectField("placement", "is not a known placement")
		}
	} else if created {
		return rejectField("placement", "is required")
	}
	if v, rej := fieldString(env.Fields, "title"); rej != nil {
		return rej
	} else if v != nil {
		row.Title = *v
	}
	if v, rej := fieldInt(env.Fields, "sort_key"); rej != nil {
		return rej
	} else if v != nil {
		row.SortKey = *v
	}

	row.Revision = rev
	row.UpdatedAt = env.ClientTime
	if err := s.store.Entries().Upsert(ctx, row); err != nil {
		return rejectionFor(err)
	}
	return nil
}

func (s *Service) upsertLocation(ctx context.Context, lib domain.LibraryID, env *Envelope, rev domain.Revision) *Rejection {
	if rej := unknownKeys(env.Fields, "entry_id", "source_id", "url", "url_key",
		"source_label", "source_number", "discovered_at", "discovery_basis", "lifecycle"); rej != nil {
		return rej
	}
	created := false
	row := &domain.Location{ID: env.EntityID, LibraryID: lib, Lifecycle: domain.LocationActive}
	if existing, err := s.store.Locations().Get(ctx, lib, env.EntityID); err == nil {
		copied := *existing
		row = &copied
	} else if errors.Is(err, domain.ErrNotFound) {
		created = true
	} else {
		return rejectionFor(err)
	}

	if id, rej := fieldUUID(env.Fields, "entry_id", created); rej != nil {
		return rej
	} else if id != nil {
		row.EntryID = *id
	}
	if v, ok := env.Fields["source_id"]; ok {
		if v == nil {
			row.SourceID = nil
		} else {
			id, rej := fieldUUID(env.Fields, "source_id", false)
			if rej != nil {
				return rej
			}
			row.SourceID = id
		}
	}
	for key, dst := range map[string]*string{
		"url": &row.URL, "url_key": &row.URLKey,
		"source_label": &row.SourceLabel, "discovery_basis": &row.DiscoveryBasis,
	} {
		if v, rej := fieldString(env.Fields, key); rej != nil {
			return rej
		} else if v != nil {
			*dst = *v
		}
	}
	if created && (row.URL == "" || row.URLKey == "") {
		return rejectField("url", "and url_key are required to create a location")
	}
	if f, present, rej := fieldNumber(env.Fields, "source_number"); rej != nil {
		return rej
	} else if present {
		row.SourceNumber = f
	}
	if t, present, rej := fieldTime(env.Fields, "discovered_at"); rej != nil {
		return rej
	} else if present && t != nil {
		row.DiscoveredAt = *t
	}
	if v, rej := fieldString(env.Fields, "lifecycle"); rej != nil {
		return rej
	} else if v != nil {
		lc := domain.LocationLifecycle(*v)
		if lc != domain.LocationActive && lc != domain.LocationRetracted {
			return rejectField("lifecycle", "must be active or retracted")
		}
		row.Lifecycle = lc
	}
	if created && row.DiscoveredAt.IsZero() {
		row.DiscoveredAt = env.ClientTime
	}

	row.Revision = rev
	row.UpdatedAt = env.ClientTime
	if err := s.store.Locations().Upsert(ctx, row); err != nil {
		return rejectionFor(err)
	}
	return nil
}

func (s *Service) upsertReadingState(ctx context.Context, lib domain.LibraryID, env *Envelope, rev domain.Revision) *Rejection {
	if rej := unknownKeys(env.Fields, "status", "first_opened_at", "last_read_at", "completed_at"); rej != nil {
		return rej
	}
	row := &domain.ReadingState{EntryID: env.EntityID, LibraryID: lib, Status: domain.Unread}
	if existing, err := s.store.ReadingStates().Get(ctx, lib, env.EntityID); err == nil {
		copied := *existing
		row = &copied
	} else if !errors.Is(err, domain.ErrNotFound) {
		return rejectionFor(err)
	}

	if v, rej := fieldString(env.Fields, "status"); rej != nil {
		return rej
	} else if v != nil {
		st := domain.ReadStatus(*v)
		switch st {
		case domain.Unread, domain.Reading, domain.Completed:
			row.Status = st
		default:
			return rejectField("status", "is not a known status")
		}
	}
	for key, dst := range map[string]**time.Time{
		"first_opened_at": &row.FirstOpenedAt,
		"last_read_at":    &row.LastReadAt,
		"completed_at":    &row.CompletedAt,
	} {
		if t, present, rej := fieldTime(env.Fields, key); rej != nil {
			return rej
		} else if present {
			*dst = t
		}
	}

	row.Revision = rev
	row.UpdatedAt = env.ClientTime
	if err := s.store.ReadingStates().Put(ctx, row); err != nil {
		return rejectionFor(err)
	}
	return nil
}

func (s *Service) upsertMeasurement(ctx context.Context, lib domain.LibraryID, env *Envelope, rev domain.Revision) *Rejection {
	if rej := unknownKeys(env.Fields, "source_id", "fraction", "observed_at"); rej != nil {
		return rej
	}
	source, rej := fieldUUID(env.Fields, "source_id", true)
	if rej != nil {
		return rej
	}
	row := &domain.Measurement{EntryID: env.EntityID, SourceID: *source, LibraryID: lib}
	if existing, err := s.store.Measurements().Get(ctx, lib, env.EntityID, *source); err == nil {
		copied := *existing
		row = &copied
	} else if !errors.Is(err, domain.ErrNotFound) {
		return rejectionFor(err)
	}

	if f, present, rej := fieldNumber(env.Fields, "fraction"); rej != nil {
		return rej
	} else if present {
		if f == nil {
			return rejectField("fraction", "must not be null")
		}
		if *f < 0 || *f > 1 {
			return rejectField("fraction", "must be between 0 and 1")
		}
		row.Fraction = *f
	}
	if t, present, rej := fieldTime(env.Fields, "observed_at"); rej != nil {
		return rej
	} else if present && t != nil {
		row.ObservedAt = *t
	}
	if row.ObservedAt.IsZero() {
		// The observation clock is the measurement's merge key; without an
		// explicit one the client's transaction time is the observation.
		row.ObservedAt = env.ClientTime
	}

	row.Revision = rev
	if err := s.store.Measurements().Put(ctx, row); err != nil {
		return rejectionFor(err)
	}
	return nil
}
