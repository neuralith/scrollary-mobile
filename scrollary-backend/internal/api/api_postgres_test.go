package api

// The same endpoint suite, against a real PostgreSQL engine. The two stores
// must be indistinguishable through the API; running one suite over both is
// what makes that a tested property instead of a hope.
//
// Selection order matches the storage harness: SCROLLARY_TEST_DATABASE_URL if
// set, otherwise a postgres:17-alpine testcontainer, otherwise skip.

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

	"github.com/neuralith/scrollary-backend/internal/storage/postgres"
)

var (
	apiAdminOnce sync.Once
	apiAdminDSN  string
	apiAdminErr  error
	apiDBCounter atomic.Int64
)

func apiAdminConn(t *testing.T) string {
	t.Helper()
	apiAdminOnce.Do(func() {
		if dsn := os.Getenv("SCROLLARY_TEST_DATABASE_URL"); dsn != "" {
			apiAdminDSN = dsn
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
			apiAdminErr = err
			return
		}
		dsn, err := container.ConnectionString(ctx, "sslmode=disable")
		if err != nil {
			apiAdminErr = err
			return
		}
		apiAdminDSN = dsn
	})
	if apiAdminErr != nil {
		t.Skipf("no PostgreSQL available (set SCROLLARY_TEST_DATABASE_URL or start Docker): %v", apiAdminErr)
	}
	if apiAdminDSN == "" {
		t.Skip("no PostgreSQL available")
	}
	return apiAdminDSN
}

func newPostgresStore(t *testing.T) *postgres.Store {
	t.Helper()
	ctx := context.Background()
	admin := apiAdminConn(t)

	name := fmt.Sprintf("scrollary_api_%d_%d", time.Now().UnixNano(), apiDBCounter.Add(1))
	conn, err := pgx.Connect(ctx, admin)
	if err != nil {
		t.Fatalf("connect admin: %v", err)
	}
	if _, err := conn.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		_ = conn.Close(ctx)
		t.Fatalf("create database: %v", err)
	}

	cfg, err := pgx.ParseConfig(admin)
	if err != nil {
		_ = conn.Close(ctx)
		t.Fatalf("parse admin dsn: %v", err)
	}
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=disable",
		cfg.User, cfg.Password, cfg.Host, cfg.Port, name)

	store, err := postgres.Open(ctx, dsn)
	if err != nil {
		_ = conn.Close(ctx)
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		store.Close()
		_, _ = conn.Exec(context.Background(), "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)")
		_ = conn.Close(context.Background())
	})
	return store
}

func TestAPISuiteOnPostgres(t *testing.T) {
	runAPISuite(t, newPostgresStore(t), nil)
}
