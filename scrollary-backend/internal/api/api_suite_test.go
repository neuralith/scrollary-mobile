package api

// The endpoint suite, shared between the in-memory store and PostgreSQL: the
// two must be indistinguishable through the API, so they run the same tests.

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"

	"github.com/neuralith/scrollary-backend/internal/config"
	"github.com/neuralith/scrollary-backend/internal/storage"
)

const testLibrary = "api-suite"

// responseCheck, when armed, validates every request/response pair against
// the frozen contract. The memory run arms it; see conformance_test.go.
type responseCheck func(t *testing.T, req *http.Request, res *http.Response, body []byte)

type apiHarness struct {
	t     *testing.T
	srv   *Server
	check responseCheck
}

func newHarness(t *testing.T, store storage.Store, check responseCheck) *apiHarness {
	t.Helper()
	srv := New(config.Config{DevMode: true, DevLibrary: "development"}, store)
	return &apiHarness{t: t, srv: srv, check: check}
}

// do performs one request with the development library header and returns the
// status and decoded body. Bodies are also handed to the conformance check.
func (h *apiHarness) do(t *testing.T, method, path string, payload any) (int, map[string]any) {
	t.Helper()
	var reqBody *bytes.Reader
	if payload != nil {
		raw, err := json.Marshal(payload)
		if err != nil {
			t.Fatalf("marshal: %v", err)
		}
		reqBody = bytes.NewReader(raw)
	} else {
		reqBody = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reqBody)
	req.Header.Set(LibraryHeader, testLibrary)
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	res, err := h.srv.App().Test(req, fiber.TestConfig{Timeout: 30 * time.Second})
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	defer res.Body.Close()

	var buf bytes.Buffer
	if _, err := buf.ReadFrom(res.Body); err != nil {
		t.Fatalf("read body: %v", err)
	}
	raw := buf.Bytes()

	if h.check != nil {
		// Re-create the request for validation: Test consumed the body.
		vreq := httptest.NewRequest(method, path, bytes.NewReader(nil))
		vreq.Header.Set(LibraryHeader, testLibrary)
		h.check(t, vreq, res, raw)
	}

	var decoded map[string]any
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &decoded); err != nil {
			t.Fatalf("%s %s: undecodable body %q", method, path, raw)
		}
	}
	return res.StatusCode, decoded
}

func envelope(entityType string, entityID uuid.UUID, op string, fields map[string]any, clock string) map[string]any {
	env := map[string]any{
		"mutation_id": uuid.NewString(),
		"entity_type": entityType,
		"entity_id":   entityID.String(),
		"op":          op,
		"client_time": clock,
	}
	if fields != nil {
		env["fields"] = fields
	}
	return env
}

func (h *apiHarness) push(t *testing.T, envs ...map[string]any) map[string]any {
	t.Helper()
	status, body := h.do(t, http.MethodPost, "/mutations", map[string]any{"mutations": envs})
	if status != http.StatusOK {
		t.Fatalf("push: expected 200, got %d: %v", status, body)
	}
	return body
}

func outcomes(t *testing.T, body map[string]any) []string {
	t.Helper()
	results, _ := body["results"].([]any)
	out := make([]string, 0, len(results))
	for _, r := range results {
		m, _ := r.(map[string]any)
		out = append(out, fmt.Sprint(m["outcome"]))
	}
	return out
}

func (h *apiHarness) pull(t *testing.T, cursor int64) map[string]any {
	t.Helper()
	status, body := h.do(t, http.MethodGet, fmt.Sprintf("/changes?cursor=%d", cursor), nil)
	if status != http.StatusOK {
		t.Fatalf("pull: expected 200, got %d: %v", status, body)
	}
	return body
}

// rootFolderID pulls from zero and finds the system root the library was
// created with.
func (h *apiHarness) rootFolderID(t *testing.T) uuid.UUID {
	t.Helper()
	body := h.pull(t, 0)
	for _, c := range body["changes"].([]any) {
		m := c.(map[string]any)
		if m["entity_type"] == "folder" {
			entity := m["entity"].(map[string]any)
			if entity["kind"] == "root" {
				return uuid.MustParse(entity["id"].(string))
			}
		}
	}
	t.Fatal("no root folder in the bootstrap pull")
	return uuid.Nil
}

func clock(offset time.Duration) string {
	return time.Date(2026, 8, 21, 12, 0, 0, 0, time.UTC).Add(offset).Format(time.RFC3339)
}

// runAPISuite is the whole endpoint behaviour, against whichever store.
func runAPISuite(t *testing.T, store storage.Store, check responseCheck) {
	h := newHarness(t, store, check)

	root := h.rootFolderID(t)
	folderID := uuid.New()
	collectionID := uuid.New()
	sourceID := uuid.New()
	entry101 := uuid.New()
	location101 := uuid.New()

	t.Run("mutation round trip through the feed", func(t *testing.T) {
		body := h.push(t,
			envelope("folder", folderID, "upsert", map[string]any{
				"parent_id": root.String(), "name": "Weekly", "sort_key": float64(10),
			}, clock(0)),
			envelope("collection", collectionID, "upsert", map[string]any{
				"folder_id": folderID.String(), "name": "Serial Alpha",
				"ordering_basis": "explicitNumericIndex",
			}, clock(time.Second)),
			envelope("source", sourceID, "upsert", map[string]any{
				"collection_id": collectionID.String(), "host": "reading.example.com",
				"path_key": "serial-alpha", "language": "en",
			}, clock(2*time.Second)),
			envelope("entry", entry101, "upsert", map[string]any{
				"collection_id": collectionID.String(), "ordinal": float64(101),
				"placement": "placed", "title": "Part 101",
			}, clock(3*time.Second)),
			envelope("location", location101, "upsert", map[string]any{
				"entry_id": entry101.String(), "source_id": sourceID.String(),
				"url":     "https://reading.example.com/serial-alpha/part-101",
				"url_key": "https://reading.example.com/serial-alpha/part-101",
			}, clock(4*time.Second)),
			envelope("readingState", entry101, "upsert", map[string]any{
				"status": "reading", "last_read_at": clock(5 * time.Second),
			}, clock(5*time.Second)),
			envelope("measurement", entry101, "upsert", map[string]any{
				"source_id": sourceID.String(), "fraction": 0.4,
			}, clock(6*time.Second)),
		)
		for i, o := range outcomes(t, body) {
			if o != "applied" {
				t.Fatalf("mutation %d: expected applied, got %v (%v)", i, o, body)
			}
		}

		pulled := h.pull(t, 0)
		changes := pulled["changes"].([]any)
		kinds := map[string]int{}
		lastRev := float64(0)
		for _, c := range changes {
			m := c.(map[string]any)
			rev := m["revision"].(float64)
			if rev < lastRev {
				t.Fatalf("feed out of revision order: %v then %v", lastRev, rev)
			}
			lastRev = rev
			if m["type"] == "entity" {
				kinds[m["entity_type"].(string)]++
			}
		}
		for _, want := range []string{"folder", "collection", "source", "entry", "location", "readingState", "measurement"} {
			if kinds[want] == 0 {
				t.Fatalf("feed is missing a %s row: %v", want, kinds)
			}
		}
		if pulled["has_more"] != false {
			t.Fatal("has_more should be false on a complete pull")
		}
	})

	t.Run("duplicate mutation produces one effect and the same reply", func(t *testing.T) {
		dupID := uuid.New()
		env := envelope("folder", dupID, "upsert", map[string]any{
			"parent_id": root.String(), "name": "Dup",
		}, clock(10*time.Second))

		first := h.push(t, env)
		second := h.push(t, env)

		firstResults := first["results"].([]any)[0].(map[string]any)
		secondResults := second["results"].([]any)[0].(map[string]any)
		if firstResults["outcome"] != "applied" || secondResults["outcome"] != "duplicate" {
			t.Fatalf("expected applied then duplicate, got %v / %v", firstResults, secondResults)
		}
		if firstResults["revision"] != secondResults["revision"] {
			t.Fatalf("a duplicate must carry the originally assigned revision: %v vs %v",
				firstResults["revision"], secondResults["revision"])
		}

		// One effect: exactly one folder named Dup in the feed.
		count := 0
		for _, c := range h.pull(t, 0)["changes"].([]any) {
			m := c.(map[string]any)
			if m["type"] == "entity" && m["entity_type"] == "folder" {
				if m["entity"].(map[string]any)["name"] == "Dup" {
					count++
				}
			}
		}
		if count != 1 {
			t.Fatalf("expected exactly one Dup folder, found %d", count)
		}
	})

	t.Run("last write wins on the client clock", func(t *testing.T) {
		body := h.push(t,
			envelope("entry", entry101, "upsert", map[string]any{
				"title": "Part 101 (revised)",
			}, clock(20*time.Second)),
			envelope("entry", entry101, "upsert", map[string]any{
				"title": "Part 101 (stale)",
			}, clock(15*time.Second)),
		)
		for i, o := range outcomes(t, body) {
			if o != "applied" {
				t.Fatalf("mutation %d: losing last-write-wins is convergence, not failure; got %v", i, o)
			}
		}
		title := ""
		for _, c := range h.pull(t, 0)["changes"].([]any) {
			m := c.(map[string]any)
			if m["type"] == "entity" && m["entity_type"] == "entry" {
				e := m["entity"].(map[string]any)
				if e["id"] == entry101.String() {
					title = e["title"].(string)
				}
			}
		}
		if title != "Part 101 (revised)" {
			t.Fatalf("the newer clock must win regardless of arrival order; kept %q", title)
		}
	})

	t.Run("rejections are named and do not poison the batch", func(t *testing.T) {
		badKind := envelope("downloadRequest", uuid.New(), "upsert", map[string]any{}, clock(0))
		orphan := envelope("collection", uuid.New(), "upsert", map[string]any{
			"folder_id": uuid.NewString(), "name": "Orphan", "ordering_basis": "discoveryOrder",
		}, clock(0))
		i3 := envelope("entry", uuid.New(), "upsert", map[string]any{
			"collection_id": collectionID.String(), "folder_id": folderID.String(),
			"placement": "placed",
		}, clock(0))
		good := envelope("folder", uuid.New(), "upsert", map[string]any{
			"parent_id": root.String(), "name": "Still fine",
		}, clock(0))

		body := h.push(t, badKind, orphan, i3, good)
		got := outcomes(t, body)
		want := []string{"rejected", "rejected", "rejected", "applied"}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("mutation %d: expected %s, got %s (%v)", i, want[i], got[i], body)
			}
		}
		results := body["results"].([]any)
		codeOf := func(i int) string {
			return results[i].(map[string]any)["error"].(map[string]any)["code"].(string)
		}
		if codeOf(0) != "invalid_mutation" {
			t.Fatalf("downloadRequest must not ride the outbox: %s", codeOf(0))
		}
		if codeOf(1) != "unknown_entity" {
			t.Fatalf("an orphan collection names unknown_entity: %s", codeOf(1))
		}
		if codeOf(2) != "invariant_violation" {
			t.Fatalf("I3 names invariant_violation: %s", codeOf(2))
		}
	})

	t.Run("delete writes a tombstone and converges when already gone", func(t *testing.T) {
		victim := uuid.New()
		h.push(t, envelope("folder", victim, "upsert", map[string]any{
			"parent_id": root.String(), "name": "Doomed",
		}, clock(30*time.Second)))

		first := h.push(t, envelope("folder", victim, "delete", nil, clock(31*time.Second)))
		if outcomes(t, first)[0] != "applied" {
			t.Fatalf("delete: %v", first)
		}
		// A second client deleting the same folder converges rather than erroring.
		second := h.push(t, envelope("folder", victim, "delete", nil, clock(32*time.Second)))
		if outcomes(t, second)[0] != "applied" {
			t.Fatalf("re-delete must converge: %v", second)
		}

		found := false
		for _, c := range h.pull(t, 0)["changes"].([]any) {
			m := c.(map[string]any)
			if m["type"] == "tombstone" {
				ts := m["tombstone"].(map[string]any)
				if ts["kind"] == "folder" && ts["entity_id"] == victim.String() {
					found = true
				}
			}
		}
		if !found {
			t.Fatal("the deletion must appear as a tombstone in the feed")
		}
	})

	t.Run("feed pages with has_more", func(t *testing.T) {
		status, body := h.do(t, http.MethodGet, "/changes?cursor=0&limit=3", nil)
		if status != http.StatusOK {
			t.Fatalf("expected 200, got %d", status)
		}
		if len(body["changes"].([]any)) != 3 {
			t.Fatalf("expected exactly 3 changes, got %d", len(body["changes"].([]any)))
		}
		if body["has_more"] != true {
			t.Fatal("has_more must be true when a page remains")
		}
		next := int64(body["next_cursor"].(float64))
		rest := h.pull(t, next)
		if len(rest["changes"].([]any)) == 0 {
			t.Fatal("the next page must continue after the cursor")
		}
	})

	t.Run("cursor validation", func(t *testing.T) {
		status, body := h.do(t, http.MethodGet, "/changes", nil)
		if status != http.StatusBadRequest || body["error"].(map[string]any)["code"] != "invalid_cursor" {
			t.Fatalf("missing cursor: %d %v", status, body)
		}
		status, body = h.do(t, http.MethodGet, "/changes?cursor=-1", nil)
		if status != http.StatusBadRequest || body["error"].(map[string]any)["code"] != "invalid_cursor" {
			t.Fatalf("negative cursor: %d %v", status, body)
		}
		status, body = h.do(t, http.MethodGet, "/changes?cursor=0&limit=1001", nil)
		if status != http.StatusBadRequest || body["error"].(map[string]any)["code"] != "validation_failed" {
			t.Fatalf("oversized limit: %d %v", status, body)
		}
	})

	t.Run("arbitration resolves a known url_key", func(t *testing.T) {
		provEntry := uuid.New()
		provLocation := uuid.New()
		status, body := h.do(t, http.MethodPost, "/identity/arbitrate", map[string]any{
			"evidence": map[string]any{
				"url":         "https://reading.example.com/serial-alpha/part-101",
				"url_key":     "https://reading.example.com/serial-alpha/part-101",
				"host":        "reading.example.com",
				"observed_at": clock(40 * time.Second),
			},
			"provisional": map[string]any{
				"entry_id":    provEntry.String(),
				"location_id": provLocation.String(),
			},
		})
		if status != http.StatusOK || body["outcome"] != "resolved" {
			t.Fatalf("url_key hit must resolve: %d %v", status, body)
		}
		mapped := map[string]string{}
		for _, m := range body["mappings"].([]any) {
			mm := m.(map[string]any)
			mapped[mm["kind"].(string)] = mm["canonical_id"].(string)
		}
		if mapped["entry"] != entry101.String() || mapped["location"] != location101.String() {
			t.Fatalf("wrong canonical identity: %v", mapped)
		}
	})

	t.Run("arbitration resolves by source and ordinal", func(t *testing.T) {
		provEntry := uuid.New()
		status, body := h.do(t, http.MethodPost, "/identity/arbitrate", map[string]any{
			"evidence": map[string]any{
				"url":            "https://mirror.example.org/serial-alpha/101",
				"url_key":        "https://mirror.example.org/serial-alpha/101",
				"host":           "reading.example.com",
				"path_key":       "serial-alpha",
				"ordering_basis": "explicitNumericIndex",
				"ordinal":        float64(101),
				"observed_at":    clock(41 * time.Second),
			},
			"provisional": map[string]any{"entry_id": provEntry.String()},
		})
		if status != http.StatusOK || body["outcome"] != "resolved" {
			t.Fatalf("source+ordinal must resolve: %d %v", status, body)
		}
		found := false
		for _, m := range body["mappings"].([]any) {
			mm := m.(map[string]any)
			if mm["kind"] == "entry" && mm["canonical_id"] == entry101.String() {
				found = true
			}
		}
		if !found {
			t.Fatalf("entry 101 must map by ordinal: %v", body)
		}
	})

	t.Run("arbitration refuses what must not merge", func(t *testing.T) {
		base := map[string]any{
			"url":         "https://mirror.example.org/serial-alpha/x",
			"url_key":     "https://mirror.example.org/serial-alpha/x",
			"host":        "reading.example.com",
			"path_key":    "serial-alpha",
			"observed_at": clock(42 * time.Second),
		}

		// A printed number that disagrees with the ordinal: kept, not repaired.
		conflicting := map[string]any{}
		for k, v := range base {
			conflicting[k] = v
		}
		conflicting["ordering_basis"] = "explicitNumericIndex"
		conflicting["ordinal"] = float64(100)
		conflicting["source_number"] = 99.5
		status, body := h.do(t, http.MethodPost, "/identity/arbitrate",
			map[string]any{"evidence": conflicting, "provisional": map[string]any{"entry_id": uuid.NewString()}})
		if status != http.StatusOK || body["outcome"] != "unresolved" || body["reason"] != "conflicting_ordinals" {
			t.Fatalf("100 vs 99.5 must stay two entries: %d %v", status, body)
		}

		// An ordinal without the explicit numeric basis is an invention: 400.
		wrongBasis := map[string]any{}
		for k, v := range base {
			wrongBasis[k] = v
		}
		wrongBasis["ordering_basis"] = "publicationDate"
		wrongBasis["ordinal"] = float64(7)
		status, body = h.do(t, http.MethodPost, "/identity/arbitrate",
			map[string]any{"evidence": wrongBasis})
		if status != http.StatusBadRequest || body["error"].(map[string]any)["code"] != "validation_failed" {
			t.Fatalf("ordinal without explicitNumericIndex is validation_failed: %d %v", status, body)
		}

		// Nothing recognisable: unresolved, and the client keeps its identity.
		unknown := map[string]any{
			"url":         "https://elsewhere.example.net/x",
			"url_key":     "https://elsewhere.example.net/x",
			"host":        "elsewhere.example.net",
			"observed_at": clock(43 * time.Second),
		}
		status, body = h.do(t, http.MethodPost, "/identity/arbitrate",
			map[string]any{"evidence": unknown, "provisional": map[string]any{"entry_id": uuid.NewString()}})
		if status != http.StatusOK || body["outcome"] != "unresolved" || body["reason"] != "insufficient_evidence" {
			t.Fatalf("unknown evidence is unresolved: %d %v", status, body)
		}
	})

	t.Run("placement wins once and refuses honestly", func(t *testing.T) {
		unplacedA := uuid.New()
		unplacedB := uuid.New()
		h.push(t,
			envelope("entry", unplacedA, "upsert", map[string]any{
				"collection_id": collectionID.String(), "placement": "unplaced", "title": "Mystery A",
			}, clock(50*time.Second)),
			envelope("entry", unplacedB, "upsert", map[string]any{
				"collection_id": collectionID.String(), "placement": "unplaced", "title": "Mystery B",
			}, clock(51*time.Second)),
		)

		status, body := h.do(t, http.MethodPost,
			fmt.Sprintf("/entries/%s/placement", unplacedA), map[string]any{"ordinal": 99.5})
		if status != http.StatusOK {
			t.Fatalf("first placement must win: %d %v", status, body)
		}
		entry := body["entry"].(map[string]any)
		if entry["placement"] != "userPlaced" || entry["ordinal"] != 99.5 {
			t.Fatalf("placement result: %v", entry)
		}

		status, body = h.do(t, http.MethodPost,
			fmt.Sprintf("/entries/%s/placement", unplacedB), map[string]any{"ordinal": 99.5})
		if status != http.StatusConflict {
			t.Fatalf("second placement must lose: %d %v", status, body)
		}
		errBody := body["error"].(map[string]any)
		if errBody["code"] != "placement_conflict" {
			t.Fatalf("the loser is told: %v", errBody)
		}
		details := errBody["details"].(map[string]any)
		if details["current_entry_id"] != unplacedA.String() || details["current_ordinal"] != 99.5 {
			t.Fatalf("the conflict names the holder: %v", details)
		}
	})

	t.Run("placement is idempotent through the ledger", func(t *testing.T) {
		e := uuid.New()
		h.push(t, envelope("entry", e, "upsert", map[string]any{
			"collection_id": collectionID.String(), "placement": "unplaced", "title": "Retry",
		}, clock(60*time.Second)))

		mid := uuid.NewString()
		status, first := h.do(t, http.MethodPost,
			fmt.Sprintf("/entries/%s/placement", e), map[string]any{"ordinal": 42.5, "mutation_id": mid})
		if status != http.StatusOK {
			t.Fatalf("placement: %d %v", status, first)
		}
		status, second := h.do(t, http.MethodPost,
			fmt.Sprintf("/entries/%s/placement", e), map[string]any{"ordinal": 42.5, "mutation_id": mid})
		if status != http.StatusOK {
			t.Fatalf("a retried placement is idempotent: %d %v", status, second)
		}
		if second["entry"].(map[string]any)["ordinal"] != 42.5 {
			t.Fatalf("retry returns the placed row: %v", second)
		}
	})

	t.Run("placement refuses a basis that gives ordinals no meaning", func(t *testing.T) {
		dateCollection := uuid.New()
		dateEntry := uuid.New()
		h.push(t,
			envelope("collection", dateCollection, "upsert", map[string]any{
				"folder_id": root.String(), "name": "A weekly", "ordering_basis": "publicationDate",
			}, clock(70*time.Second)),
			envelope("entry", dateEntry, "upsert", map[string]any{
				"collection_id": dateCollection.String(), "placement": "unplaced", "title": "An issue",
			}, clock(71*time.Second)),
		)
		status, body := h.do(t, http.MethodPost,
			fmt.Sprintf("/entries/%s/placement", dateEntry), map[string]any{"ordinal": float64(1)})
		if status != http.StatusConflict || body["error"].(map[string]any)["code"] != "invalid_placement" {
			t.Fatalf("date-ordered collections refuse placement: %d %v", status, body)
		}
	})

	t.Run("measurement delete needs its scope and keeps the other scope", func(t *testing.T) {
		otherSource := uuid.New()
		h.push(t,
			envelope("source", otherSource, "upsert", map[string]any{
				"collection_id": collectionID.String(), "host": "mirror.example.org",
				"path_key": "serial-alpha-mirror", "language": "fr",
			}, clock(80*time.Second)),
			envelope("measurement", entry101, "upsert", map[string]any{
				"source_id": otherSource.String(), "fraction": 0.9,
			}, clock(81*time.Second)),
		)

		noScope := h.push(t, envelope("measurement", entry101, "delete", nil, clock(82*time.Second)))
		if outcomes(t, noScope)[0] != "rejected" {
			t.Fatalf("a measurement delete without source_id must be rejected: %v", noScope)
		}

		scoped := h.push(t, envelope("measurement", entry101, "delete",
			map[string]any{"source_id": otherSource.String()}, clock(83*time.Second)))
		if outcomes(t, scoped)[0] != "applied" {
			t.Fatalf("scoped delete: %v", scoped)
		}

		// The first source's measurement survives.
		kept := false
		for _, c := range h.pull(t, 0)["changes"].([]any) {
			m := c.(map[string]any)
			if m["type"] == "entity" && m["entity_type"] == "measurement" {
				e := m["entity"].(map[string]any)
				if e["entry_id"] == entry101.String() && e["source_id"] == sourceID.String() {
					kept = true
				}
			}
		}
		if !kept {
			t.Fatal("deleting one scope must not take the other")
		}
	})

	t.Run("concurrent placement has exactly one winner", func(t *testing.T) {
		contested := make([]uuid.UUID, 6)
		envs := make([]map[string]any, 0, len(contested))
		for i := range contested {
			contested[i] = uuid.New()
			envs = append(envs, envelope("entry", contested[i], "upsert", map[string]any{
				"collection_id": collectionID.String(), "placement": "unplaced",
				"title": fmt.Sprintf("Contender %d", i),
			}, clock(90*time.Second)))
		}
		h.push(t, envs...)

		var wg sync.WaitGroup
		statuses := make([]int, len(contested))
		for i, id := range contested {
			wg.Add(1)
			go func(i int, id uuid.UUID) {
				defer wg.Done()
				raw, _ := json.Marshal(map[string]any{"ordinal": 77.75})
				req := httptest.NewRequest(http.MethodPost,
					fmt.Sprintf("/entries/%s/placement", id), bytes.NewReader(raw))
				req.Header.Set(LibraryHeader, testLibrary)
				req.Header.Set("Content-Type", "application/json")
				res, err := h.srv.App().Test(req, fiber.TestConfig{Timeout: 30 * time.Second})
				if err != nil {
					return
				}
				defer res.Body.Close()
				statuses[i] = res.StatusCode
			}(i, id)
		}
		wg.Wait()

		winners, losers := 0, 0
		for _, s := range statuses {
			switch s {
			case http.StatusOK:
				winners++
			case http.StatusConflict:
				losers++
			default:
				t.Fatalf("unexpected status %d", s)
			}
		}
		if winners != 1 || losers != len(contested)-1 {
			t.Fatalf("expected exactly one winner, got %d winners / %d losers", winners, losers)
		}
	})

	t.Run("dev mode is required", func(t *testing.T) {
		plain := New(config.Config{DevMode: false}, h.srv.store)
		req := httptest.NewRequest(http.MethodGet, "/changes?cursor=0", nil)
		req.Header.Set(LibraryHeader, testLibrary)
		res, err := plain.App().Test(req, fiber.TestConfig{Timeout: 30 * time.Second})
		if err != nil {
			t.Fatalf("test: %v", err)
		}
		defer res.Body.Close()
		if res.StatusCode != http.StatusForbidden {
			t.Fatalf("the namespace outside dev mode is 403, got %d", res.StatusCode)
		}
	})
}
