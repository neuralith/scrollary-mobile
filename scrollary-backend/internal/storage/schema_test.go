package storage_test

import (
	"os"
	"strings"
	"testing"
)

// The schema is validated by parsing the migration rather than by connecting to
// a database, so this runs everywhere with no infrastructure. A Postgres
// integration suite arrives with the real repository (roadmap task B5) and
// skips itself without DATABASE_URL.
func migration(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile("../../migrations/0001_init.up.sql")
	if err != nil {
		t.Fatalf("read migration: %v", err)
	}
	return string(b)
}

func TestSchemaHasEverySynchronisedTable(t *testing.T) {
	sql := migration(t)
	for _, table := range []string{
		"libraries", "folders", "collections", "sources", "entries",
		"locations", "reading_states", "measurements",
		"download_requests", "tombstones", "mutations",
	} {
		if !strings.Contains(sql, "CREATE TABLE "+table+" (") {
			t.Errorf("the schema is missing table %q", table)
		}
	}
}

// What the server must NOT hold is as much of the contract as what it must.
// Offline copies, browsing history and capture state are device-owned;
// reproducing the mobile database here is the mistake this boundary prevents.
func TestSchemaHoldsNoDeviceOwnedState(t *testing.T) {
	sql := strings.ToLower(migration(t))
	for _, forbidden := range []string{
		"offline_cop", "browsing_history", "save_queue", "save_runs",
		"content_path", "byte_size", "manifest", "artifact_format",
		"progress_anchor", "anchor_index", "page_hints", "favicon",
	} {
		if strings.Contains(sql, forbidden) {
			t.Errorf("the server schema must not contain device-owned state: found %q", forbidden)
		}
	}
}

func TestSchemaEnforcesTheLoadBearingInvariants(t *testing.T) {
	sql := migration(t)
	checks := map[string]string{
		"I1 root has no parent":             "folder_root_has_no_parent",
		"I1 exactly one root per library":   "one_root_per_library",
		"I2 a folder is not its own parent": "folder_is_not_its_own_parent",
		"I3 entry placement":                "entry_placement",
		"I6 one url is one place":           "location_url_key_unique",
		"I8 ordinal unique per collection":  "entry_ordinal_unique",
		"I9 preferred source belongs":       "preferred_source_belongs_to_collection",
		"download request idempotency":      "one_open_request_per_entry",
	}
	for name, constraint := range checks {
		if !strings.Contains(sql, constraint) {
			t.Errorf("%s: expected constraint %q in the schema", name, constraint)
		}
	}
}

// Recognition is the hot path, asked on every page load. It must be an index,
// not a scan.
func TestSchemaIndexesTheRecognitionPath(t *testing.T) {
	sql := migration(t)
	for _, idx := range []string{
		"location_url_key_unique", // url_key -> Location
		"sources_by_identity",     // host + path_key -> Source
		"entries_by_collection",   // collection + ordinal -> Entry
	} {
		if !strings.Contains(sql, idx) {
			t.Errorf("the recognition path needs index %q", idx)
		}
	}
}

// Every synchronised table carries the revision a client's cursor points into.
func TestEverySynchronisedTableCarriesARevision(t *testing.T) {
	sql := migration(t)
	for _, table := range []string{
		"folders", "collections", "sources", "entries", "locations",
		"reading_states", "measurements", "download_requests", "tombstones",
	} {
		start := strings.Index(sql, "CREATE TABLE "+table+" (")
		if start < 0 {
			t.Fatalf("missing table %q", table)
		}
		end := strings.Index(sql[start:], ");")
		if end < 0 {
			t.Fatalf("unterminated CREATE TABLE for %q", table)
		}
		if !strings.Contains(sql[start:start+end], "revision") {
			t.Errorf("table %q must carry a revision for the change cursor", table)
		}
	}
}

func TestDownMigrationReversesEveryTable(t *testing.T) {
	b, err := os.ReadFile("../../migrations/0001_init.down.sql")
	if err != nil {
		t.Fatalf("read down migration: %v", err)
	}
	down := string(b)
	for _, table := range []string{
		"libraries", "folders", "collections", "sources", "entries",
		"locations", "reading_states", "measurements",
		"download_requests", "tombstones", "mutations",
	} {
		if !strings.Contains(down, "DROP TABLE IF EXISTS "+table) {
			t.Errorf("the down migration does not drop %q", table)
		}
	}
}
