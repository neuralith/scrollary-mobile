package postgres

import (
	"context"
	"errors"
	"sort"

	"github.com/jackc/pgx/v5"

	"github.com/neuralith/scrollary-backend/internal/domain"
	"github.com/neuralith/scrollary-backend/internal/storage"
)

// --- folder upsert ----------------------------------------------------------

// Upsert applies a synchronised folder write with the same cycle discipline as
// Move, inside a transaction holding the library row lock: a sync-applied
// parent change must not commit what an interactive move would refuse.
func (f *folders) Upsert(ctx context.Context, fd *domain.Folder) error {
	if err := fd.Validate(); err != nil {
		return err
	}
	s := (*Store)(f)
	return s.inTx(ctx, func(tx pgx.Tx) error {
		if err := lockLibrary(ctx, tx, fd.LibraryID); err != nil {
			return err
		}
		if fd.ParentID != nil {
			var exists bool
			if err := tx.QueryRow(ctx,
				`SELECT EXISTS (SELECT 1 FROM folders WHERE library_id = $1 AND id = $2)`,
				fd.LibraryID, *fd.ParentID).Scan(&exists); err != nil {
				return err
			}
			if !exists {
				return domain.ErrNotFound
			}
			// I2: walk up from the proposed parent; meeting this folder is a
			// cycle.
			var cycle bool
			if err := tx.QueryRow(ctx, `
				WITH RECURSIVE up AS (
					SELECT id, parent_id FROM folders WHERE library_id = $1 AND id = $2
					UNION ALL
					SELECT f.id, f.parent_id FROM folders f JOIN up ON f.id = up.parent_id
				)
				SELECT EXISTS (SELECT 1 FROM up WHERE id = $3)`,
				fd.LibraryID, *fd.ParentID, fd.ID).Scan(&cycle); err != nil {
				return err
			}
			if cycle {
				return domain.ErrFolderCycle
			}
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO folders (id, library_id, parent_id, kind, name, sort_key, revision, updated_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, coalesce($8, now()))
			ON CONFLICT (id) DO UPDATE SET
				parent_id = EXCLUDED.parent_id,
				name = EXCLUDED.name,
				sort_key = EXCLUDED.sort_key,
				revision = EXCLUDED.revision,
				updated_at = EXCLUDED.updated_at
			WHERE folders.updated_at <= EXCLUDED.updated_at`,
			fd.ID, fd.LibraryID, fd.ParentID, string(fd.Kind), fd.Name, fd.SortKey,
			int64(fd.Revision), nullableTime(fd.UpdatedAt))
		return err
	})
}

// --- deletes ----------------------------------------------------------------
//
// The schema's ON DELETE actions carry the cascade; each method only needs to
// address the right row and report whether it existed.

func deleteRow(ctx context.Context, s *Store, table string, lib domain.LibraryID, id domain.ID) error {
	tag, err := s.pool.Exec(ctx,
		`DELETE FROM `+table+` WHERE library_id = $1 AND id = $2`, lib, id)
	if err != nil {
		return translate(err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

func (c *collections) Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error {
	return deleteRow(ctx, (*Store)(c), "collections", lib, id)
}

func (x *sources) Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error {
	return deleteRow(ctx, (*Store)(x), "sources", lib, id)
}

func (x *entries) Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error {
	return deleteRow(ctx, (*Store)(x), "entries", lib, id)
}

func (x *locations) Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Location, error) {
	l, err := scanLocation((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+locationColumns+` FROM locations WHERE library_id = $1 AND id = $2`, lib, id))
	if err != nil {
		return nil, translate(err)
	}
	return l, nil
}

func (x *locations) Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) error {
	return deleteRow(ctx, (*Store)(x), "locations", lib, id)
}

func (x *readingStates) Delete(ctx context.Context, lib domain.LibraryID, entry domain.ID) error {
	tag, err := (*Store)(x).pool.Exec(ctx,
		`DELETE FROM reading_states WHERE library_id = $1 AND entry_id = $2`, lib, entry)
	if err != nil {
		return translate(err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

func (x *measurements) Delete(ctx context.Context, lib domain.LibraryID, entry, source domain.ID) error {
	tag, err := (*Store)(x).pool.Exec(ctx,
		`DELETE FROM measurements WHERE library_id = $1 AND entry_id = $2 AND source_id = $3`,
		lib, entry, source)
	if err != nil {
		return translate(err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

// --- placement --------------------------------------------------------------

// Place is the serialised ordinal-placement arbitration (B9). The whole
// check-and-write runs in one transaction holding the library row lock, so two
// devices placing at once resolve to exactly one winner.
func (x *entries) Place(ctx context.Context, lib domain.LibraryID, id domain.ID, ordinal float64, rev domain.Revision) (*domain.Entry, *domain.Entry, error) {
	s := (*Store)(x)
	var placed, holder *domain.Entry
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if err := lockLibrary(ctx, tx, lib); err != nil {
			return err
		}
		e, err := scanEntry(tx.QueryRow(ctx,
			`SELECT `+entryColumns+` FROM entries WHERE library_id = $1 AND id = $2`, lib, id))
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.ErrNotFound
		}
		if err != nil {
			return err
		}
		if e.CollectionID == nil {
			return domain.ErrPlacementUnsupported
		}
		var basis string
		if err := tx.QueryRow(ctx,
			`SELECT ordering_basis FROM collections WHERE library_id = $1 AND id = $2`,
			lib, *e.CollectionID).Scan(&basis); err != nil {
			return err
		}
		if !domain.OrderingBasis(basis).SupportsCrossSourceMerge() {
			return domain.ErrPlacementUnsupported
		}
		h, err := scanEntry(tx.QueryRow(ctx,
			`SELECT `+entryColumns+` FROM entries
			 WHERE library_id = $1 AND collection_id = $2 AND ordinal = $3 AND id <> $4`,
			lib, *e.CollectionID, ordinal, id))
		if err == nil {
			holder = h
			return domain.ErrDuplicateOrdinal
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		placed, err = scanEntry(tx.QueryRow(ctx, `
			UPDATE entries
			SET ordinal = $3, placement = 'userPlaced', revision = $4, updated_at = now()
			WHERE library_id = $1 AND id = $2
			RETURNING `+entryColumns, lib, id, ordinal, int64(rev)))
		return err
	})
	if err != nil {
		return nil, holder, err
	}
	return placed, nil, nil
}

// --- mutation ledger --------------------------------------------------------

type mutationsLedger Store

func (m *mutationsLedger) Get(ctx context.Context, lib domain.LibraryID, mutationID string) (*storage.MutationRecord, error) {
	rec := &storage.MutationRecord{LibraryID: lib, MutationID: mutationID}
	var rev int64
	err := (*Store)(m).pool.QueryRow(ctx,
		`SELECT revision, applied_at FROM mutations WHERE library_id = $1 AND mutation_id = $2`,
		lib, mutationID).Scan(&rev, &rec.AppliedAt)
	if err != nil {
		return nil, translate(err)
	}
	rec.Revision = domain.Revision(rev)
	return rec, nil
}

func (m *mutationsLedger) Record(ctx context.Context, rec *storage.MutationRecord) error {
	tag, err := (*Store)(m).pool.Exec(ctx, `
		INSERT INTO mutations (library_id, mutation_id, revision)
		VALUES ($1, $2, $3)
		ON CONFLICT (library_id, mutation_id) DO NOTHING`,
		rec.LibraryID, rec.MutationID, int64(rec.Revision))
	if err != nil {
		return translate(err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrAlreadyExists
	}
	return nil
}

// --- change feed ------------------------------------------------------------

type changeFeed Store

// Feed queries each table for rows past the cursor and merges by revision.
// Each query is bounded by limit+1, so a page costs at most nine bounded index
// scans regardless of library size.
func (c *changeFeed) Feed(ctx context.Context, lib domain.LibraryID, after domain.Revision, limit int) ([]storage.FeedItem, bool, error) {
	s := (*Store)(c)
	if limit <= 0 {
		limit = 200
	}
	bound := limit + 1
	var items []storage.FeedItem

	collect := func(query string, scan func(pgx.Rows) (storage.FeedItem, error)) error {
		rows, err := s.pool.Query(ctx, query, lib, int64(after), bound)
		if err != nil {
			return translate(err)
		}
		defer rows.Close()
		for rows.Next() {
			item, err := scan(rows)
			if err != nil {
				return err
			}
			items = append(items, item)
		}
		return rows.Err()
	}

	if err := collect(
		`SELECT `+folderColumns+` FROM folders WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			f, err := scanFolder(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: f.Revision, Kind: domain.KindFolder, Folder: f}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT `+collectionColumns+` FROM collections WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			col, err := scanCollection(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: col.Revision, Kind: domain.KindCollection, Collection: col}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT `+sourceColumns+` FROM sources WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			src, err := scanSource(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: src.Revision, Kind: domain.KindSource, Source: src}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT `+entryColumns+` FROM entries WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			e, err := scanEntry(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: e.Revision, Kind: domain.KindEntry, Entry: e}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT `+locationColumns+` FROM locations WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			l, err := scanLocation(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: l.Revision, Kind: domain.KindLocation, Location: l}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT `+readingColumns+` FROM reading_states WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			r, err := scanReading(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: r.Revision, Kind: domain.KindReading, ReadingState: r}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT `+measurementColumns+` FROM measurements WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			m, err := scanMeasurement(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: m.Revision, Kind: domain.KindMeasure, Measurement: m}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT `+downloadColumns+` FROM download_requests WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			d, err := scanDownload(rows)
			if err != nil {
				return storage.FeedItem{}, err
			}
			return storage.FeedItem{Revision: d.Revision, Kind: domain.KindDownload, DownloadRequest: d}, nil
		}); err != nil {
		return nil, false, err
	}
	if err := collect(
		`SELECT library_id, kind, entity_id, revision, deleted_at FROM tombstones
		 WHERE library_id = $1 AND revision > $2 ORDER BY revision LIMIT $3`,
		func(rows pgx.Rows) (storage.FeedItem, error) {
			var t domain.Tombstone
			var kind string
			var rev int64
			if err := rows.Scan(&t.LibraryID, &kind, &t.EntityID, &rev, &t.DeletedAt); err != nil {
				return storage.FeedItem{}, err
			}
			t.Kind = domain.EntityKind(kind)
			t.Revision = domain.Revision(rev)
			return storage.FeedItem{Revision: t.Revision, Kind: t.Kind, Tombstone: &t}, nil
		}); err != nil {
		return nil, false, err
	}

	sort.Slice(items, func(i, j int) bool { return items[i].Revision < items[j].Revision })
	hasMore := false
	if len(items) > limit {
		items = items[:limit]
		hasMore = true
	}
	return items, hasMore, nil
}
