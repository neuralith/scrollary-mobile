package postgres

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/neuralith/scrollary-backend/internal/domain"
)

// nullableTime maps Go's zero time to SQL NULL so column defaults apply.
func nullableTime(t time.Time) *time.Time {
	if t.IsZero() {
		return nil
	}
	return &t
}

// --- reading state ----------------------------------------------------------

type readingStates Store

const readingColumns = `entry_id, library_id, status, first_opened_at, last_read_at,
	completed_at, revision, updated_at`

func scanReading(row pgx.Row) (*domain.ReadingState, error) {
	var r domain.ReadingState
	var status string
	var rev int64
	if err := row.Scan(&r.EntryID, &r.LibraryID, &status, &r.FirstOpenedAt, &r.LastReadAt,
		&r.CompletedAt, &rev, &r.UpdatedAt); err != nil {
		return nil, err
	}
	r.Status = domain.ReadStatus(status)
	r.Revision = domain.Revision(rev)
	return &r, nil
}

func (x *readingStates) Get(ctx context.Context, lib domain.LibraryID, entry domain.ID) (*domain.ReadingState, error) {
	r, err := scanReading((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+readingColumns+` FROM reading_states WHERE library_id = $1 AND entry_id = $2`,
		lib, entry))
	if err != nil {
		return nil, translate(err)
	}
	return r, nil
}

// Put applies last-write-wins on the reading clock in one statement: an older
// write than the stored row simply does not update it. Completion is a value,
// not a floor - an older completion never beats a newer mark-as-unread.
func (x *readingStates) Put(ctx context.Context, r *domain.ReadingState) error {
	_, err := (*Store)(x).pool.Exec(ctx, `
		INSERT INTO reading_states (entry_id, library_id, status, first_opened_at,
			last_read_at, completed_at, revision, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (entry_id) DO UPDATE SET
			status = EXCLUDED.status,
			first_opened_at = EXCLUDED.first_opened_at,
			last_read_at = EXCLUDED.last_read_at,
			completed_at = EXCLUDED.completed_at,
			revision = EXCLUDED.revision,
			updated_at = EXCLUDED.updated_at
		WHERE reading_states.updated_at <= EXCLUDED.updated_at`,
		r.EntryID, r.LibraryID, string(r.Status), r.FirstOpenedAt, r.LastReadAt,
		r.CompletedAt, int64(r.Revision), r.UpdatedAt)
	return translate(err)
}

// --- measurements -----------------------------------------------------------

type measurements Store

const measurementColumns = `entry_id, source_id, library_id, fraction, observed_at, revision`

func scanMeasurement(row pgx.Row) (*domain.Measurement, error) {
	var m domain.Measurement
	var rev int64
	if err := row.Scan(&m.EntryID, &m.SourceID, &m.LibraryID, &m.Fraction, &m.ObservedAt, &rev); err != nil {
		return nil, err
	}
	m.Revision = domain.Revision(rev)
	return &m, nil
}

func (x *measurements) Get(ctx context.Context, lib domain.LibraryID, entry, source domain.ID) (*domain.Measurement, error) {
	m, err := scanMeasurement((*Store)(x).pool.QueryRow(ctx,
		`SELECT `+measurementColumns+` FROM measurements
		 WHERE library_id = $1 AND entry_id = $2 AND source_id = $3`, lib, entry, source))
	if err != nil {
		return nil, translate(err)
	}
	return m, nil
}

func (x *measurements) ForEntry(ctx context.Context, lib domain.LibraryID, entry domain.ID) ([]*domain.Measurement, error) {
	rows, err := (*Store)(x).pool.Query(ctx,
		`SELECT `+measurementColumns+` FROM measurements
		 WHERE library_id = $1 AND entry_id = $2
		 ORDER BY observed_at`, lib, entry)
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []*domain.Measurement
	for rows.Next() {
		m, err := scanMeasurement(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// Put stores a measurement against the rendering it was taken on. The scope is
// part of the primary key, and an older observation never overwrites a newer
// one.
func (x *measurements) Put(ctx context.Context, m *domain.Measurement) error {
	if err := m.Validate(); err != nil {
		return err
	}
	_, err := (*Store)(x).pool.Exec(ctx, `
		INSERT INTO measurements (entry_id, source_id, library_id, fraction, observed_at, revision)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (entry_id, source_id) DO UPDATE SET
			fraction = EXCLUDED.fraction,
			observed_at = EXCLUDED.observed_at,
			revision = EXCLUDED.revision
		WHERE measurements.observed_at <= EXCLUDED.observed_at`,
		m.EntryID, m.SourceID, m.LibraryID, m.Fraction, m.ObservedAt, int64(m.Revision))
	return translate(err)
}

// --- download requests ------------------------------------------------------

type downloadRequests Store

const downloadColumns = `id, library_id, entry_id, location_id, state, idempotency_key,
	created_by, created_at, claimed_by_device, claimed_at, resolved_at, failure_reason, revision`

func scanDownload(row pgx.Row) (*domain.DownloadRequest, error) {
	var d domain.DownloadRequest
	var state string
	var rev int64
	if err := row.Scan(&d.ID, &d.LibraryID, &d.EntryID, &d.LocationID, &state,
		&d.IdempotencyKey, &d.CreatedBy, &d.CreatedAt, &d.ClaimedByDevice, &d.ClaimedAt,
		&d.ResolvedAt, &d.FailureReason, &rev); err != nil {
		return nil, err
	}
	d.State = domain.DownloadRequestState(state)
	d.Revision = domain.Revision(rev)
	return &d, nil
}

// Create is idempotent by construction: an identical idempotency key returns
// the existing record, and the partial unique index one_open_request_per_entry
// guarantees at most one non-terminal request per (library, entry) even under
// concurrent creates.
func (x *downloadRequests) Create(ctx context.Context, d *domain.DownloadRequest) (*domain.DownloadRequest, error) {
	s := (*Store)(x)
	var out *domain.DownloadRequest
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if d.IdempotencyKey != "" {
			existing, err := scanDownload(tx.QueryRow(ctx,
				`SELECT `+downloadColumns+` FROM download_requests
				 WHERE library_id = $1 AND idempotency_key = $2
				 ORDER BY created_at, id LIMIT 1`, d.LibraryID, d.IdempotencyKey))
			if err == nil {
				out = existing
				return nil
			}
			if !errors.Is(err, pgx.ErrNoRows) {
				return err
			}
		}
		open, err := scanDownload(tx.QueryRow(ctx,
			`SELECT `+downloadColumns+` FROM download_requests
			 WHERE library_id = $1 AND entry_id = $2 AND state IN ('pending','claimed')`,
			d.LibraryID, d.EntryID))
		if err == nil {
			out = open
			return nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}
		inserted, err := scanDownload(tx.QueryRow(ctx, `
			INSERT INTO download_requests (id, library_id, entry_id, location_id, state,
				idempotency_key, created_by, created_at, claimed_by_device, revision)
			VALUES ($1, $2, $3, $4, $5, $6, $7, coalesce($8, now()), '', $9)
			RETURNING `+downloadColumns,
			d.ID, d.LibraryID, d.EntryID, d.LocationID, string(d.State),
			d.IdempotencyKey, d.CreatedBy, nullableTime(d.CreatedAt), int64(d.Revision)))
		if err != nil {
			return err
		}
		out = inserted
		return nil
	})
	if err != nil {
		// A concurrent create can slip between the SELECT and the INSERT; the
		// partial unique index catches it, and the open request it protects is
		// the correct answer.
		if errors.Is(err, domain.ErrAlreadyExists) {
			open, selErr := scanDownload(s.pool.QueryRow(ctx,
				`SELECT `+downloadColumns+` FROM download_requests
				 WHERE library_id = $1 AND entry_id = $2 AND state IN ('pending','claimed')`,
				d.LibraryID, d.EntryID))
			if selErr == nil {
				return open, nil
			}
		}
		return nil, err
	}
	return out, nil
}

func (x *downloadRequests) Pending(ctx context.Context, lib domain.LibraryID) ([]*domain.DownloadRequest, error) {
	rows, err := (*Store)(x).pool.Query(ctx,
		`SELECT `+downloadColumns+` FROM download_requests
		 WHERE library_id = $1 AND state = 'pending'
		 ORDER BY created_at, id`, lib)
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []*domain.DownloadRequest
	for rows.Next() {
		d, err := scanDownload(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// Claim is the single-winner transition as one conditional UPDATE: exactly one
// device moves a request from pending to claimed, and every loser is told
// rather than silently proceeding.
func (x *downloadRequests) Claim(ctx context.Context, lib domain.LibraryID, id domain.ID, device string) (*domain.DownloadRequest, error) {
	s := (*Store)(x)
	d, err := scanDownload(s.pool.QueryRow(ctx, `
		UPDATE download_requests
		SET state = 'claimed', claimed_by_device = $3, claimed_at = now()
		WHERE library_id = $1 AND id = $2 AND state = 'pending'
		RETURNING `+downloadColumns, lib, id, device))
	if err == nil {
		return d, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, translate(err)
	}
	// No row transitioned: distinguish "never existed" from "already claimed".
	var exists bool
	if err := s.pool.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM download_requests WHERE library_id = $1 AND id = $2)`,
		lib, id).Scan(&exists); err != nil {
		return nil, translate(err)
	}
	if !exists {
		return nil, domain.ErrNotFound
	}
	return nil, domain.ErrRequestClaimed
}

// Resolve records the terminal state a device reported.
func (x *downloadRequests) Resolve(ctx context.Context, lib domain.LibraryID, id domain.ID, state domain.DownloadRequestState, reason string) (*domain.DownloadRequest, error) {
	if !state.Terminal() {
		return nil, domain.ErrRequestClaimed
	}
	d, err := scanDownload((*Store)(x).pool.QueryRow(ctx, `
		UPDATE download_requests
		SET state = $3, failure_reason = $4, resolved_at = now()
		WHERE library_id = $1 AND id = $2
		RETURNING `+downloadColumns, lib, id, string(state), reason))
	if err != nil {
		return nil, translate(err)
	}
	return d, nil
}

// --- tombstones -------------------------------------------------------------

type tombstones Store

// Add records a deliberate removal. Re-deleting the same entity keeps one
// tombstone and advances it to the newer revision.
func (x *tombstones) Add(ctx context.Context, t domain.Tombstone) error {
	_, err := (*Store)(x).pool.Exec(ctx, `
		INSERT INTO tombstones (library_id, kind, entity_id, revision, deleted_at)
		VALUES ($1, $2, $3, $4, coalesce($5, now()))
		ON CONFLICT (library_id, kind, entity_id) DO UPDATE SET
			revision = EXCLUDED.revision,
			deleted_at = EXCLUDED.deleted_at`,
		t.LibraryID, string(t.Kind), t.EntityID, int64(t.Revision), nullableTime(t.DeletedAt))
	return translate(err)
}

func (x *tombstones) Since(ctx context.Context, lib domain.LibraryID, since domain.Revision) ([]domain.Tombstone, error) {
	rows, err := (*Store)(x).pool.Query(ctx,
		`SELECT library_id, kind, entity_id, revision, deleted_at FROM tombstones
		 WHERE library_id = $1 AND revision > $2
		 ORDER BY revision`, lib, int64(since))
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []domain.Tombstone
	for rows.Next() {
		var t domain.Tombstone
		var kind string
		var rev int64
		if err := rows.Scan(&t.LibraryID, &kind, &t.EntityID, &rev, &t.DeletedAt); err != nil {
			return nil, err
		}
		t.Kind = domain.EntityKind(kind)
		t.Revision = domain.Revision(rev)
		out = append(out, t)
	}
	return out, rows.Err()
}
