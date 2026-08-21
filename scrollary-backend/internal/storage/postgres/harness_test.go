package postgres

// The integration harness. Tests here run against a real PostgreSQL engine,
// because most of what this package promises - partial unique indexes, CHECK
// constraints, conditional UPDATE claims, transactional reparenting - is
// PostgreSQL behaviour that a mock would only assert into existence.
//
// Selection order:
//  1. SCROLLARY_TEST_DATABASE_URL, if set, is used as the admin connection.
//  2. Otherwise a postgres:17-alpine testcontainer is started once per run.
//  3. If neither is possible the suite skips; it never fails for missing Docker.

import (
	"context"
	"fmt"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	tcpostgres "github.com/testcontainers/testcontainers-go/modules/postgres"

	"github.com/neuralith/scrollary-backend/internal/domain"
)

var (
	adminOnce sync.Once
	adminDSN  string
	adminErr  error
	dbCounter atomic.Int64
)

func adminConn(t *testing.T) string {
	t.Helper()
	adminOnce.Do(func() {
		if dsn := os.Getenv("SCROLLARY_TEST_DATABASE_URL"); dsn != "" {
			adminDSN = dsn
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		container, err := tcpostgres.Run(ctx, "postgres:17-alpine",
			tcpostgres.WithDatabase("scrollary"),
			tcpostgres.WithUsername("scrollary"),
			tcpostgres.WithPassword("scrollary"),
			tcpostgres.BasicWaitStrategies(),
		)
		if err != nil {
			adminErr = err
			return
		}
		dsn, err := container.ConnectionString(ctx, "sslmode=disable")
		if err != nil {
			adminErr = err
			return
		}
		adminDSN = dsn
	})
	if adminErr != nil {
		t.Skipf("no PostgreSQL available (set SCROLLARY_TEST_DATABASE_URL or start Docker): %v", adminErr)
	}
	if adminDSN == "" {
		t.Skip("no PostgreSQL available")
	}
	return adminDSN
}

// newTestStore creates a fresh database, migrates it and returns an open
// Store. Every test gets a clean slate; the database is dropped on cleanup.
func newTestStore(t *testing.T) *Store {
	t.Helper()
	ctx := context.Background()
	admin := adminConn(t)

	name := fmt.Sprintf("scrollary_test_%d_%d", time.Now().UnixNano(), dbCounter.Add(1))
	conn, err := pgx.Connect(ctx, admin)
	if err != nil {
		t.Fatalf("connect admin: %v", err)
	}
	if _, err := conn.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		_ = conn.Close(ctx)
		t.Fatalf("create test database: %v", err)
	}
	_ = conn.Close(ctx)

	cfg, err := pgx.ParseConfig(admin)
	if err != nil {
		t.Fatalf("parse admin dsn: %v", err)
	}
	cfg.Database = name
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=disable",
		cfg.User, cfg.Password, cfg.Host, cfg.Port, name)

	store, err := Open(ctx, dsn)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		store.Close()
		conn, err := pgx.Connect(context.Background(), admin)
		if err != nil {
			return
		}
		_, _ = conn.Exec(context.Background(), "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)")
		_ = conn.Close(context.Background())
	})
	return store
}

// newLibrary mirrors the helper the in-memory suite uses, so the conformance
// tests read the same way in both packages.
func newLibrary(t *testing.T) (*Store, domain.LibraryID, domain.ID) {
	t.Helper()
	s := newTestStore(t)
	lib, err := s.Libraries().EnsureByName(context.Background(), "test")
	if err != nil {
		t.Fatalf("ensure library: %v", err)
	}
	root, err := s.Folders().Root(context.Background(), lib.ID)
	if err != nil {
		t.Fatalf("a library is created with its root folder: %v", err)
	}
	return s, lib.ID, root.ID
}
