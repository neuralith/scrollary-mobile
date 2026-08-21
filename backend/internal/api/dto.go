package api

// Wire shapes for the frozen contract. Field names are snake_case and match
// contracts/openapi.yaml exactly; required fields are always emitted, nullable
// fields are pointers that serialise as null. Converters keep every handler's
// output going through one place, so a contract drift is one diff, not five.

import (
	"time"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage"
)

type folderDTO struct {
	ID        domain.ID  `json:"id"`
	ParentID  *domain.ID `json:"parent_id"`
	Kind      string     `json:"kind"`
	Name      string     `json:"name"`
	SortKey   int64      `json:"sort_key"`
	Revision  int64      `json:"revision"`
	UpdatedAt time.Time  `json:"updated_at"`
}

func toFolderDTO(f *domain.Folder) folderDTO {
	return folderDTO{
		ID: f.ID, ParentID: f.ParentID, Kind: string(f.Kind), Name: f.Name,
		SortKey: f.SortKey, Revision: int64(f.Revision), UpdatedAt: f.UpdatedAt,
	}
}

type collectionDTO struct {
	ID                domain.ID  `json:"id"`
	FolderID          domain.ID  `json:"folder_id"`
	Name              string     `json:"name"`
	DetectedTitle     string     `json:"detected_title"`
	OrderingBasis     string     `json:"ordering_basis"`
	Lifecycle         string     `json:"lifecycle"`
	PreferredSourceID *domain.ID `json:"preferred_source_id"`
	SortKey           int64      `json:"sort_key"`
	Revision          int64      `json:"revision"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

func toCollectionDTO(c *domain.Collection) collectionDTO {
	return collectionDTO{
		ID: c.ID, FolderID: c.FolderID, Name: c.Name, DetectedTitle: c.DetectedTitle,
		OrderingBasis: string(c.OrderingBasis), Lifecycle: string(c.Lifecycle),
		PreferredSourceID: c.PreferredSourceID, SortKey: c.SortKey,
		Revision: int64(c.Revision), UpdatedAt: c.UpdatedAt,
	}
}

type sourceDTO struct {
	ID                   domain.ID  `json:"id"`
	CollectionID         domain.ID  `json:"collection_id"`
	Host                 string     `json:"host"`
	PathKey              string     `json:"path_key"`
	Language             string     `json:"language"`
	Lifecycle            string     `json:"lifecycle"`
	ResolvedIntoSourceID *domain.ID `json:"resolved_into_source_id"`
	FirstSeenAt          time.Time  `json:"first_seen_at"`
	LastSeenAt           time.Time  `json:"last_seen_at"`
	Revision             int64      `json:"revision"`
	UpdatedAt            time.Time  `json:"updated_at"`
}

func toSourceDTO(s *domain.Source) sourceDTO {
	return sourceDTO{
		ID: s.ID, CollectionID: s.CollectionID, Host: s.Host, PathKey: s.PathKey,
		Language: s.Language, Lifecycle: string(s.Lifecycle),
		ResolvedIntoSourceID: s.ResolvedIntoSourceID,
		FirstSeenAt:          s.FirstSeenAt, LastSeenAt: s.LastSeenAt,
		Revision: int64(s.Revision), UpdatedAt: s.UpdatedAt,
	}
}

type entryDTO struct {
	ID           domain.ID  `json:"id"`
	CollectionID *domain.ID `json:"collection_id"`
	FolderID     *domain.ID `json:"folder_id"`
	Ordinal      *float64   `json:"ordinal"`
	Placement    string     `json:"placement"`
	Title        string     `json:"title"`
	SortKey      int64      `json:"sort_key"`
	Revision     int64      `json:"revision"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

func toEntryDTO(e *domain.Entry) entryDTO {
	return entryDTO{
		ID: e.ID, CollectionID: e.CollectionID, FolderID: e.FolderID,
		Ordinal: e.Ordinal, Placement: string(e.Placement), Title: e.Title,
		SortKey: e.SortKey, Revision: int64(e.Revision), UpdatedAt: e.UpdatedAt,
	}
}

type locationDTO struct {
	ID             domain.ID  `json:"id"`
	EntryID        domain.ID  `json:"entry_id"`
	SourceID       *domain.ID `json:"source_id"`
	URL            string     `json:"url"`
	URLKey         string     `json:"url_key"`
	SourceLabel    string     `json:"source_label"`
	SourceNumber   *float64   `json:"source_number"`
	DiscoveredAt   time.Time  `json:"discovered_at"`
	DiscoveryBasis string     `json:"discovery_basis"`
	Lifecycle      string     `json:"lifecycle"`
	Revision       int64      `json:"revision"`
	UpdatedAt      time.Time  `json:"updated_at"`
}

func toLocationDTO(l *domain.Location) locationDTO {
	return locationDTO{
		ID: l.ID, EntryID: l.EntryID, SourceID: l.SourceID, URL: l.URL,
		URLKey: l.URLKey, SourceLabel: l.SourceLabel, SourceNumber: l.SourceNumber,
		DiscoveredAt: l.DiscoveredAt, DiscoveryBasis: l.DiscoveryBasis,
		Lifecycle: string(l.Lifecycle), Revision: int64(l.Revision), UpdatedAt: l.UpdatedAt,
	}
}

type readingStateDTO struct {
	EntryID       domain.ID  `json:"entry_id"`
	Status        string     `json:"status"`
	FirstOpenedAt *time.Time `json:"first_opened_at"`
	LastReadAt    *time.Time `json:"last_read_at"`
	CompletedAt   *time.Time `json:"completed_at"`
	Revision      int64      `json:"revision"`
	UpdatedAt     time.Time  `json:"updated_at"`
}

func toReadingStateDTO(r *domain.ReadingState) readingStateDTO {
	return readingStateDTO{
		EntryID: r.EntryID, Status: string(r.Status),
		FirstOpenedAt: r.FirstOpenedAt, LastReadAt: r.LastReadAt, CompletedAt: r.CompletedAt,
		Revision: int64(r.Revision), UpdatedAt: r.UpdatedAt,
	}
}

type measurementDTO struct {
	EntryID    domain.ID `json:"entry_id"`
	SourceID   domain.ID `json:"source_id"`
	Fraction   float64   `json:"fraction"`
	ObservedAt time.Time `json:"observed_at"`
	Revision   int64     `json:"revision"`
}

func toMeasurementDTO(m *domain.Measurement) measurementDTO {
	return measurementDTO{
		EntryID: m.EntryID, SourceID: m.SourceID, Fraction: m.Fraction,
		ObservedAt: m.ObservedAt, Revision: int64(m.Revision),
	}
}

type downloadRequestDTO struct {
	ID              domain.ID  `json:"id"`
	EntryID         domain.ID  `json:"entry_id"`
	LocationID      *domain.ID `json:"location_id"`
	State           string     `json:"state"`
	IdempotencyKey  string     `json:"idempotency_key"`
	CreatedBy       string     `json:"created_by"`
	CreatedAt       time.Time  `json:"created_at"`
	ClaimedByDevice string     `json:"claimed_by_device"`
	ClaimedAt       *time.Time `json:"claimed_at"`
	ResolvedAt      *time.Time `json:"resolved_at"`
	FailureReason   string     `json:"failure_reason"`
	Revision        int64      `json:"revision"`
}

func toDownloadRequestDTO(d *domain.DownloadRequest) downloadRequestDTO {
	return downloadRequestDTO{
		ID: d.ID, EntryID: d.EntryID, LocationID: d.LocationID, State: string(d.State),
		IdempotencyKey: d.IdempotencyKey, CreatedBy: d.CreatedBy, CreatedAt: d.CreatedAt,
		ClaimedByDevice: d.ClaimedByDevice, ClaimedAt: d.ClaimedAt, ResolvedAt: d.ResolvedAt,
		FailureReason: d.FailureReason, Revision: int64(d.Revision),
	}
}

type tombstoneDTO struct {
	Kind      string     `json:"kind"`
	EntityID  domain.ID  `json:"entity_id"`
	SourceID  *domain.ID `json:"source_id,omitempty"`
	Revision  int64      `json:"revision"`
	DeletedAt time.Time  `json:"deleted_at"`
}

func toTombstoneDTO(t *domain.Tombstone) tombstoneDTO {
	return tombstoneDTO{
		Kind: string(t.Kind), EntityID: t.EntityID,
		Revision: int64(t.Revision), DeletedAt: t.DeletedAt,
	}
}

type changeDTO struct {
	Type       string        `json:"type"`
	Revision   int64         `json:"revision"`
	EntityType string        `json:"entity_type,omitempty"`
	Entity     any           `json:"entity,omitempty"`
	Tombstone  *tombstoneDTO `json:"tombstone,omitempty"`
}

func toChangeDTO(item storage.FeedItem) changeDTO {
	dto := changeDTO{Revision: int64(item.Revision)}
	if item.Tombstone != nil {
		dto.Type = "tombstone"
		ts := toTombstoneDTO(item.Tombstone)
		dto.Tombstone = &ts
		return dto
	}
	dto.Type = "entity"
	dto.EntityType = string(item.Kind)
	switch {
	case item.Folder != nil:
		dto.Entity = toFolderDTO(item.Folder)
	case item.Collection != nil:
		dto.Entity = toCollectionDTO(item.Collection)
	case item.Source != nil:
		dto.Entity = toSourceDTO(item.Source)
	case item.Entry != nil:
		dto.Entity = toEntryDTO(item.Entry)
	case item.Location != nil:
		dto.Entity = toLocationDTO(item.Location)
	case item.ReadingState != nil:
		dto.Entity = toReadingStateDTO(item.ReadingState)
	case item.Measurement != nil:
		dto.Entity = toMeasurementDTO(item.Measurement)
	case item.DownloadRequest != nil:
		dto.Entity = toDownloadRequestDTO(item.DownloadRequest)
	}
	return dto
}
