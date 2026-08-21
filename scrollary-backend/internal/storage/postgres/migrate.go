package postgres

import (
	"context"
	"fmt"
	"io/fs"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/neuralith/scrollary-backend/migrations"
)

// migrate applies every pending up migration in order.
//
// The ledger is a plain schema_migrations table keyed by file name. There is
// deliberately no external migration dependency: the files are ordered,
// append-only and owned by Lane B, and this runner is the whole mechanism.
func migrate(ctx context.Context, pool *pgxpool.Pool) error {
	if _, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version    TEXT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)`); err != nil {
		return fmt.Errorf("create schema_migrations: %w", err)
	}

	names, err := migrationNames(".up.sql")
	if err != nil {
		return err
	}
	for _, name := range names {
		var applied bool
		if err := pool.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, name,
		).Scan(&applied); err != nil {
			return fmt.Errorf("check %s: %w", name, err)
		}
		if applied {
			continue
		}
		sql, err := migrations.FS.ReadFile(name)
		if err != nil {
			return fmt.Errorf("read %s: %w", name, err)
		}
		tx, err := pool.Begin(ctx)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, string(sql)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("apply %s: %w", name, err)
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO schema_migrations (version) VALUES ($1)`, name); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("record %s: %w", name, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
	}
	return nil
}

// migrateDown applies every down migration in reverse order. Tests use it to
// prove the down files actually reverse the schema; the service never calls it.
func migrateDown(ctx context.Context, pool *pgxpool.Pool) error {
	names, err := migrationNames(".down.sql")
	if err != nil {
		return err
	}
	for i := len(names) - 1; i >= 0; i-- {
		sql, err := migrations.FS.ReadFile(names[i])
		if err != nil {
			return fmt.Errorf("read %s: %w", names[i], err)
		}
		if _, err := pool.Exec(ctx, string(sql)); err != nil {
			return fmt.Errorf("apply %s: %w", names[i], err)
		}
		up := strings.TrimSuffix(names[i], ".down.sql") + ".up.sql"
		if _, err := pool.Exec(ctx,
			`DELETE FROM schema_migrations WHERE version = $1`, up); err != nil {
			return fmt.Errorf("unrecord %s: %w", up, err)
		}
	}
	return nil
}

func migrationNames(suffix string) ([]string, error) {
	entries, err := fs.ReadDir(migrations.FS, ".")
	if err != nil {
		return nil, err
	}
	var names []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), suffix) {
			names = append(names, e.Name())
		}
	}
	sort.Strings(names)
	return names, nil
}
