package postgres

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

// --- collections ------------------------------------------------------------

type collections Store

const collectionColumns = `id, library_id, folder_id, name, detected_title, ordering_basis,
	lifecycle, preferred_source_id, sort_key, revision, updated_at`

func scanCollection(row pgx.Row) (*domain.Collection, error) {
	var c domain.Collection
	var basis, lifecycle string
	var rev int64
	if err := row.Scan(&c.ID, &c.LibraryID, &c.FolderID, &c.Name, &c.DetectedTitle, &basis,
		&lifecycle, &c.PreferredSourceID, &c.SortKey, &rev, &c.UpdatedAt); err != nil {
		return nil, err
	}
	c.OrderingBasis = domain.OrderingBasis(basis)
	c.Lifecycle = domain.CollectionLifecycle(lifecycle)
	c.Revision = domain.Revision(rev)
	return &c, nil
}

func (c *collections) Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Collection, error) {
	col, err := scanCollection((*Store)(c).pool.QueryRow(ctx,
		`SELECT `+collectionColumns+` FROM collections WHERE library_id = $1 AND id = $2`, lib, id))
	if err != nil {
		return nil, translate(err)
	}
	return col, nil
}

func (c *collections) InFolder(ctx context.Context, lib domain.LibraryID, folder domain.ID) ([]*domain.Collection, error) {
	rows, err := (*Store)(c).pool.Query(ctx,
		`SELECT `+collectionColumns+` FROM collections
		 WHERE library_id = $1 AND folder_id = $2
		 ORDER BY sort_key, id`, lib, folder)
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []*domain.Collection
	for rows.Next() {
		col, err := scanCollection(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, col)
	}
	return out, rows.Err()
}

func (c *collections) Upsert(ctx context.Context, col *domain.Collection) error {
	if err := col.Validate(); err != nil {
		return err
	}
	_, err := (*Store)(c).pool.Exec(ctx, `
		INSERT INTO collections (id, library_id, folder_id, name, detected_title, ordering_basis,
			lifecycle, preferred_source_id, sort_key, revision, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now())
		ON CONFLICT (id) DO UPDATE SET
			folder_id = EXCLUDED.folder_id,
			name = EXCLUDED.name,
			detected_title = EXCLUDED.detected_title,
			ordering_basis = EXCLUDED.ordering_basis,
			lifecycle = EXCLUDED.lifecycle,
			preferred_source_id = EXCLUDED.preferred_source_id,
			sort_key = EXCLUDED.sort_key,
			revision = EXCLUDED.revision,
			updated_at = now()`,
		col.ID, col.LibraryID, col.FolderID, col.Name, col.DetectedTitle,
		string(col.OrderingBasis), string(col.Lifecycle), col.PreferredSourceID,
		col.SortKey, int64(col.Revision))
	return translate(err)
}

// SetPreferredSource enforces I9: a preferred Source must belong to this
// Collection. The membership check and the write are one statement, so there
// is no window in which the source could move between them.
func (c *collections) SetPreferredSource(ctx context.Context, lib domain.LibraryID, id domain.ID, source *domain.ID) error {
	s := (*Store)(c)
	return s.inTx(ctx, func(tx pgx.Tx) error {
		var locked domain.ID
		err := tx.QueryRow(ctx,
			`SELECT id FROM collections WHERE library_id = $1 AND id = $2 FOR UPDATE`,
			lib, id).Scan(&locked)
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.ErrNotFound
		}
		if err != nil {
			return err
		}
		tag, err := tx.Exec(ctx, `
			UPDATE collections c SET preferred_source_id = $3
			WHERE c.library_id = $1 AND c.id = $2
			  AND ($3::uuid IS NULL OR EXISTS (
				SELECT 1 FROM sources s WHERE s.id = $3 AND s.collection_id = c.id))`,
			lib, id, source)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return domain.ErrPreferredSourceForeign
		}
		return nil
	})
}

// --- sources ----------------------------------------------------------------

type sources Store

const sourceColumns = `id, library_id, collection_id, host, path_key, language, lifecycle,
	resolved_into_source_id, first_seen_at, last_seen_at, revision, updated_at`

func scanSource(row pgx.Row) (*domain.Source, error) {
	var s domain.Source
	var lifecycle string
	var rev int64
	if err := row.Scan(&s.ID, &s.LibraryID, &s.CollectionID, &s.Host, &s.PathKey, &s.Language,
		&lifecycle, &s.ResolvedIntoSourceID, &s.FirstSeenAt, &s.LastSeenAt, &rev, &s.UpdatedAt); err != nil {
		return nil, err
	}
	s.Lifecycle = domain.SourceLifecycle(lifecycle)
	s.Revision = domain.Revision(rev)
	return &s, nil
}

func (x *sources) Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Source, error) {
	src, err := scanSource((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+sourceColumns+` FROM sources WHERE library_id = $1 AND id = $2`, lib, id))
	if err != nil {
		return nil, translate(err)
	}
	return src, nil
}

func (x *sources) ForCollection(ctx context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Source, error) {
	rows, err := (*Store)(x).pool.Query(ctx,
		`SELECT `+sourceColumns+` FROM sources
		 WHERE library_id = $1 AND collection_id = $2
		 ORDER BY host, id`, lib, collection)
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []*domain.Source
	for rows.Next() {
		src, err := scanSource(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, src)
	}
	return out, rows.Err()
}

// ByIdentity resolves a Source from host and path key, case-insensitively -
// what V1 computed as collection_key, now at the level it actually identifies.
func (x *sources) ByIdentity(ctx context.Context, lib domain.LibraryID, host, pathKey string) (*domain.Source, error) {
	src, err := scanSource((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+sourceColumns+` FROM sources
		 WHERE library_id = $1 AND lower(host) = lower($2) AND lower(path_key) = lower($3)
		 ORDER BY first_seen_at, id LIMIT 1`, lib, host, pathKey))
	if err != nil {
		return nil, translate(err)
	}
	return src, nil
}

func (x *sources) Upsert(ctx context.Context, src *domain.Source) error {
	s := (*Store)(x)
	var exists bool
	if err := s.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM collections WHERE id = $1)`, src.CollectionID,
	).Scan(&exists); err != nil {
		return translate(err)
	}
	if !exists {
		return domain.ErrNotFound
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO sources (id, library_id, collection_id, host, path_key, language, lifecycle,
			resolved_into_source_id, first_seen_at, last_seen_at, revision, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, coalesce($9, now()), coalesce($10, now()), $11, now())
		ON CONFLICT (id) DO UPDATE SET
			collection_id = EXCLUDED.collection_id,
			host = EXCLUDED.host,
			path_key = EXCLUDED.path_key,
			language = EXCLUDED.language,
			lifecycle = EXCLUDED.lifecycle,
			resolved_into_source_id = EXCLUDED.resolved_into_source_id,
			last_seen_at = EXCLUDED.last_seen_at,
			revision = EXCLUDED.revision,
			updated_at = now()`,
		src.ID, src.LibraryID, src.CollectionID, src.Host, src.PathKey, src.Language,
		string(src.Lifecycle), src.ResolvedIntoSourceID,
		nullableTime(src.FirstSeenAt), nullableTime(src.LastSeenAt), int64(src.Revision))
	return translate(err)
}

// --- entries ----------------------------------------------------------------

type entries Store

const entryColumns = `id, library_id, collection_id, folder_id, ordinal, placement, title,
	sort_key, revision, updated_at`

func scanEntry(row pgx.Row) (*domain.Entry, error) {
	var e domain.Entry
	var placement string
	var rev int64
	if err := row.Scan(&e.ID, &e.LibraryID, &e.CollectionID, &e.FolderID, &e.Ordinal,
		&placement, &e.Title, &e.SortKey, &rev, &e.UpdatedAt); err != nil {
		return nil, err
	}
	e.Placement = domain.Placement(placement)
	e.Revision = domain.Revision(rev)
	return &e, nil
}

func (x *entries) Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Entry, error) {
	e, err := scanEntry((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+entryColumns+` FROM entries WHERE library_id = $1 AND id = $2`, lib, id))
	if err != nil {
		return nil, translate(err)
	}
	return e, nil
}

// ForCollection returns placed entries in ordinal order, with unplaced ones
// after them rather than forced to the front of a collection they have no
// position in.
func (x *entries) ForCollection(ctx context.Context, lib domain.LibraryID, collection domain.ID) ([]*domain.Entry, error) {
	rows, err := (*Store)(x).pool.Query(ctx,
		`SELECT `+entryColumns+` FROM entries
		 WHERE library_id = $1 AND collection_id = $2
		 ORDER BY ordinal ASC NULLS LAST, sort_key, id`, lib, collection)
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []*domain.Entry
	for rows.Next() {
		e, err := scanEntry(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (x *entries) ByOrdinal(ctx context.Context, lib domain.LibraryID, collection domain.ID, ordinal float64) (*domain.Entry, error) {
	e, err := scanEntry((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+entryColumns+` FROM entries
		 WHERE library_id = $1 AND collection_id = $2 AND ordinal = $3`, lib, collection, ordinal))
	if err != nil {
		return nil, translate(err)
	}
	return e, nil
}

// Upsert enforces I3 through Entry.Validate and I8 through the partial unique
// index entry_ordinal_unique, whose violation translates to ErrDuplicateOrdinal.
func (x *entries) Upsert(ctx context.Context, e *domain.Entry) error {
	if err := e.Validate(); err != nil {
		return err
	}
	_, err := (*Store)(x).pool.Exec(ctx, `
		INSERT INTO entries (id, library_id, collection_id, folder_id, ordinal, placement,
			title, sort_key, revision, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
		ON CONFLICT (id) DO UPDATE SET
			collection_id = EXCLUDED.collection_id,
			folder_id = EXCLUDED.folder_id,
			ordinal = EXCLUDED.ordinal,
			placement = EXCLUDED.placement,
			title = EXCLUDED.title,
			sort_key = EXCLUDED.sort_key,
			revision = EXCLUDED.revision,
			updated_at = now()`,
		e.ID, e.LibraryID, e.CollectionID, e.FolderID, e.Ordinal, string(e.Placement),
		e.Title, e.SortKey, int64(e.Revision))
	return translate(err)
}

// --- locations --------------------------------------------------------------

type locations Store

const locationColumns = `id, library_id, entry_id, source_id, url, url_key, source_label,
	source_number, discovered_at, discovery_basis, lifecycle, revision, updated_at`

func scanLocation(row pgx.Row) (*domain.Location, error) {
	var l domain.Location
	var lifecycle string
	var rev int64
	if err := row.Scan(&l.ID, &l.LibraryID, &l.EntryID, &l.SourceID, &l.URL, &l.URLKey,
		&l.SourceLabel, &l.SourceNumber, &l.DiscoveredAt, &l.DiscoveryBasis,
		&lifecycle, &rev, &l.UpdatedAt); err != nil {
		return nil, err
	}
	l.Lifecycle = domain.LocationLifecycle(lifecycle)
	l.Revision = domain.Revision(rev)
	return &l, nil
}

// ByURLKey is the recognition hot path: one lookup through the unique index,
// no arbitration, no round trip anywhere else.
func (x *locations) ByURLKey(ctx context.Context, lib domain.LibraryID, urlKey string) (*domain.Location, error) {
	l, err := scanLocation((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+locationColumns+` FROM locations WHERE library_id = $1 AND url_key = $2`,
		lib, urlKey))
	if err != nil {
		return nil, translate(err)
	}
	return l, nil
}

func (x *locations) ForEntry(ctx context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Location, error) {
	rows, err := (*Store)(x).pool.Query(ctx,
		`SELECT `+locationColumns+` FROM locations
		 WHERE library_id = $1 AND entry_id = $2
		 ORDER BY url_key`, lib, entry)
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []*domain.Location
	for rows.Next() {
		l, err := scanLocation(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

// Upsert enforces I6 through the unique index location_url_key_unique and I7
// through Location.ValidateAgainstEntry.
func (x *locations) Upsert(ctx context.Context, l *domain.Location) error {
	s := (*Store)(x)
	e, err := scanEntry(s.pool.QueryRow(ctx,
		`SELECT `+entryColumns+` FROM entries WHERE library_id = $1 AND id = $2`,
		l.LibraryID, l.EntryID))
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrNotFound
	}
	if err != nil {
		return translate(err)
	}
	if err := l.ValidateAgainstEntry(*e); err != nil {
		return err
	}
	_, err = s.pool.Exec(ctx, `
		INSERT INTO locations (id, library_id, entry_id, source_id, url, url_key, source_label,
			source_number, discovered_at, discovery_basis, lifecycle, revision, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, coalesce($9, now()), $10, $11, $12, now())
		ON CONFLICT (id) DO UPDATE SET
			entry_id = EXCLUDED.entry_id,
			source_id = EXCLUDED.source_id,
			url = EXCLUDED.url,
			url_key = EXCLUDED.url_key,
			source_label = EXCLUDED.source_label,
			source_number = EXCLUDED.source_number,
			discovery_basis = EXCLUDED.discovery_basis,
			lifecycle = EXCLUDED.lifecycle,
			revision = EXCLUDED.revision,
			updated_at = now()`,
		l.ID, l.LibraryID, l.EntryID, l.SourceID, l.URL, l.URLKey, l.SourceLabel,
		l.SourceNumber, nullableTime(l.DiscoveredAt), l.DiscoveryBasis,
		string(l.Lifecycle), int64(l.Revision))
	return translate(err)
}
