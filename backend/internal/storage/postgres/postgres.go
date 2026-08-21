// Package postgres is the PostgreSQL Store.
//
// It implements exactly the same semantics as the in-memory Store: where a
// rule is enforced here by a SQL constraint, the violation is translated back
// into the same named domain error, so no caller can tell the stores apart.
// Where the schema can enforce a rule (partial unique indexes, CHECKs,
// conditional UPDATEs) it does, instead of a read-then-write race.
package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
	"github.com/mcagricaliskan/scrollary/backend/internal/storage"
)

// Store is the PostgreSQL persistence boundary.
type Store struct {
	pool *pgxpool.Pool
}

// Open connects, applies pending migrations and returns a ready Store.
func Open(ctx context.Context, databaseURL string) (*Store, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	if err := migrate(ctx, pool); err != nil {
		pool.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}
	return &Store{pool: pool}, nil
}

// Close releases the connection pool.
func (s *Store) Close() { s.pool.Close() }

func (s *Store) Revisions() storage.Revisions               { return (*revisions)(s) }
func (s *Store) Libraries() storage.Libraries               { return (*libraries)(s) }
func (s *Store) Folders() storage.Folders                   { return (*folders)(s) }
func (s *Store) Collections() storage.Collections           { return (*collections)(s) }
func (s *Store) Sources() storage.Sources                   { return (*sources)(s) }
func (s *Store) Entries() storage.Entries                   { return (*entries)(s) }
func (s *Store) Locations() storage.Locations               { return (*locations)(s) }
func (s *Store) ReadingStates() storage.ReadingStates       { return (*readingStates)(s) }
func (s *Store) Measurements() storage.Measurements         { return (*measurements)(s) }
func (s *Store) DownloadRequests() storage.DownloadRequests { return (*downloadRequests)(s) }
func (s *Store) Tombstones() storage.Tombstones             { return (*tombstones)(s) }

// translate maps a PostgreSQL constraint violation onto the named domain error
// the in-memory store returns for the same rule.
func translate(err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.ErrNotFound
	}
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return err
	}
	switch pgErr.Code {
	case "23505": // unique_violation
		switch pgErr.ConstraintName {
		case "entry_ordinal_unique":
			return domain.ErrDuplicateOrdinal
		case "location_url_key_unique":
			return domain.ErrDuplicateURLKey
		case "one_root_per_library":
			return domain.ErrRootMustNotHaveParent
		default:
			return domain.ErrAlreadyExists
		}
	case "23503": // foreign_key_violation
		if pgErr.ConstraintName == "preferred_source_belongs_to_collection" {
			return domain.ErrPreferredSourceForeign
		}
		return domain.ErrNotFound
	case "23514": // check_violation
		switch pgErr.ConstraintName {
		case "entry_placement":
			return domain.ErrEntryPlacement
		case "unplaced_entry_has_no_ordinal":
			return domain.ErrDuplicateOrdinal
		case "folder_root_has_no_parent":
			return domain.ErrRootMustNotHaveParent
		case "folder_is_not_its_own_parent":
			return domain.ErrFolderCycle
		}
	}
	return err
}

// inTx runs fn inside a transaction, translating the returned error.
func (s *Store) inTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return translate(err)
	}
	return tx.Commit(ctx)
}

// lockLibrary serialises structural tree mutations within one library, the
// same guarantee the in-memory store gets from its mutex. Without it, two
// concurrent folder moves could each pass the cycle walk and then commit a
// cycle together.
func lockLibrary(ctx context.Context, tx pgx.Tx, lib domain.LibraryID) error {
	tag, err := tx.Exec(ctx, `SELECT 1 FROM libraries WHERE id = $1 FOR UPDATE`, lib)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

// --- revisions --------------------------------------------------------------

type revisions Store

func (r *revisions) Next(ctx context.Context, lib domain.LibraryID) (domain.Revision, error) {
	var rev int64
	err := (*Store)(r).pool.QueryRow(ctx,
		`UPDATE libraries SET revision = revision + 1 WHERE id = $1 RETURNING revision`, lib,
	).Scan(&rev)
	if err != nil {
		return 0, translate(err)
	}
	return domain.Revision(rev), nil
}

func (r *revisions) Current(ctx context.Context, lib domain.LibraryID) (domain.Revision, error) {
	var rev int64
	err := (*Store)(r).pool.QueryRow(ctx,
		`SELECT revision FROM libraries WHERE id = $1`, lib,
	).Scan(&rev)
	if err != nil {
		return 0, translate(err)
	}
	return domain.Revision(rev), nil
}

// --- libraries --------------------------------------------------------------

type libraries Store

// EnsureByName creates the library and its single system root Folder together,
// so I1 holds from the very first write. The name is matched
// case-insensitively, and a per-name advisory lock makes two concurrent
// ensures of the same name resolve to one library rather than two.
func (l *libraries) EnsureByName(ctx context.Context, name string) (*domain.Library, error) {
	s := (*Store)(l)
	var lib *domain.Library
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx,
			`SELECT pg_advisory_xact_lock(hashtext(lower($1)))`, name); err != nil {
			return err
		}
		existing, err := scanLibrary(tx.QueryRow(ctx,
			`SELECT id, name, revision, created_at FROM libraries WHERE lower(name) = lower($1)`,
			name))
		if err == nil {
			lib = existing
			return nil
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return err
		}

		created := &domain.Library{ID: domain.NewID(), Name: name, Revision: 1}
		if err := tx.QueryRow(ctx,
			`INSERT INTO libraries (id, name, revision) VALUES ($1, $2, 1) RETURNING created_at`,
			created.ID, created.Name,
		).Scan(&created.CreatedAt); err != nil {
			return err
		}
		root := &domain.Folder{
			ID:        domain.NewID(),
			LibraryID: created.ID,
			Kind:      domain.FolderRoot,
			Name:      "Library",
			Revision:  1,
		}
		if err := root.Validate(); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO folders (id, library_id, parent_id, kind, name, sort_key, revision)
			VALUES ($1, $2, NULL, $3, $4, 0, $5)`,
			root.ID, root.LibraryID, string(root.Kind), root.Name, int64(root.Revision),
		); err != nil {
			return err
		}
		lib = created
		return nil
	})
	if err != nil {
		return nil, err
	}
	return lib, nil
}

func (l *libraries) Get(ctx context.Context, id domain.LibraryID) (*domain.Library, error) {
	lib, err := scanLibrary((*Store)(l).pool.QueryRow(ctx,
		`SELECT id, name, revision, created_at FROM libraries WHERE id = $1`, id))
	if err != nil {
		return nil, translate(err)
	}
	return lib, nil
}

func scanLibrary(row pgx.Row) (*domain.Library, error) {
	var lib domain.Library
	var rev int64
	if err := row.Scan(&lib.ID, &lib.Name, &rev, &lib.CreatedAt); err != nil {
		return nil, err
	}
	lib.Revision = domain.Revision(rev)
	return &lib, nil
}
