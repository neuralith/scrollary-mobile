package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/neuralith/scrollary-backend/internal/config"
	"github.com/neuralith/scrollary-backend/internal/storage/memory"
)

func TestHealthzAnswersWithoutTouchingTheStore(t *testing.T) {
	srv := New(config.Config{}, memory.New())

	res, err := srv.App().Test(httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if err != nil {
		t.Fatalf("healthz: %v", err)
	}
	if res.StatusCode != http.StatusOK {
		t.Fatalf("expected 200, got %d", res.StatusCode)
	}

	var body map[string]string
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("unexpected body %v", body)
	}
}

func TestVersionReportsDevMode(t *testing.T) {
	srv := New(config.Config{DevMode: true}, memory.New())

	res, err := srv.App().Test(httptest.NewRequest(http.MethodGet, "/version", nil))
	if err != nil {
		t.Fatalf("version: %v", err)
	}
	var body map[string]any
	if err := json.NewDecoder(res.Body).Decode(&body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body["devMode"] != true {
		t.Fatal("the service must say plainly when it is in development mode")
	}
}

// The development namespace is not authentication and must not behave like it.
// Without SCROLLARY_DEV_MODE there is no way to name a library at all: the
// production path is an account, not a header.
func TestLibraryNamespaceRequiresDevMode(t *testing.T) {
	srv := New(config.Config{DevMode: false}, memory.New())

	req := httptest.NewRequest(http.MethodGet, "/version", nil)
	req.Header.Set(LibraryHeader, "someone-elses-library")

	var resolveErr error
	srv.App().Get("/probe", func(c fiberCtx) error {
		_, resolveErr = srv.resolveLibrary(c)
		return c.SendStatus(http.StatusNoContent)
	})

	probe := httptest.NewRequest(http.MethodGet, "/probe", nil)
	probe.Header.Set(LibraryHeader, "someone-elses-library")
	if _, err := srv.App().Test(probe); err != nil {
		t.Fatalf("probe: %v", err)
	}
	if resolveErr != config.ErrDevHeaderWithoutDevMode {
		t.Fatalf("expected the namespace to be refused outside dev mode, got %v", resolveErr)
	}
}

// In development mode, several clients addressing the same name must reach the
// same library -- that is the entire purpose of the mechanism.
func TestDevLibraryIsSharedByName(t *testing.T) {
	store := memory.New()
	srv := New(config.Config{DevMode: true, DevLibrary: "development"}, store)

	var first, second string
	srv.App().Get("/probe", func(c fiberCtx) error {
		id, err := srv.resolveLibrary(c)
		if err != nil {
			return err
		}
		if first == "" {
			first = id.String()
		} else {
			second = id.String()
		}
		return c.SendStatus(http.StatusNoContent)
	})

	for range 2 {
		req := httptest.NewRequest(http.MethodGet, "/probe", nil)
		req.Header.Set(LibraryHeader, "shared")
		if _, err := srv.App().Test(req); err != nil {
			t.Fatalf("probe: %v", err)
		}
	}
	if first == "" || first != second {
		t.Fatalf("the same library name must resolve to the same library: %q vs %q", first, second)
	}
}
