package api

// Contract conformance: every real HTTP response the API produces is validated
// against contracts/openapi.yaml, so the contract stays the single authority
// instead of drifting into a suggestion.
//
// kin-openapi speaks OpenAPI 3.0 while the contract is 3.1, so the loader
// down-converts the 3.1 constructs on the fly as it reads each file:
// `type: [T, "null"]` becomes `type: T` + `nullable: true`, `const: v` becomes
// `enum: [v]`, and the version string becomes 3.0.3. The transformation is
// in-memory only - contracts/ is frozen and never edited - and it is lossless
// for validation purposes: every shape constraint survives.

import (
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/getkin/kin-openapi/openapi3"
	"github.com/getkin/kin-openapi/openapi3filter"
	"github.com/getkin/kin-openapi/routers"
	"github.com/getkin/kin-openapi/routers/gorillamux"
	"gopkg.in/yaml.v3"

	"github.com/neuralith/scrollary-backend/internal/storage/memory"
)

func contractsDir(t *testing.T) string {
	t.Helper()
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate this file")
	}
	// backend/internal/api → repository root → contracts.
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "..", "contracts")
}

// downconvert rewrites the 3.1-only constructs kin-openapi cannot parse.
func downconvert(node *yaml.Node) {
	if node == nil {
		return
	}
	if node.Kind == yaml.DocumentNode {
		for _, child := range node.Content {
			downconvert(child)
		}
		return
	}
	if node.Kind == yaml.SequenceNode {
		for _, child := range node.Content {
			downconvert(child)
		}
		return
	}
	if node.Kind != yaml.MappingNode {
		return
	}
	for i := 0; i+1 < len(node.Content); i += 2 {
		key, value := node.Content[i], node.Content[i+1]
		switch key.Value {
		case "openapi":
			if value.Value == "3.1.0" {
				value.Value = "3.0.3"
			}
		case "type":
			// type: [T, "null"] → type: T + nullable: true
			if value.Kind == yaml.SequenceNode && len(value.Content) == 2 {
				var plain string
				hasNull := false
				for _, item := range value.Content {
					if item.Value == "null" {
						hasNull = true
					} else {
						plain = item.Value
					}
				}
				if hasNull && plain != "" {
					value.Kind = yaml.ScalarNode
					value.Tag = "!!str"
					value.Value = plain
					value.Content = nil
					node.Content = append(node.Content,
						&yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: "nullable"},
						&yaml.Node{Kind: yaml.ScalarNode, Tag: "!!bool", Value: "true"},
					)
				}
			}
		case "const":
			// const: v → enum: [v]
			key.Value = "enum"
			item := *value
			value.Kind = yaml.SequenceNode
			value.Tag = "!!seq"
			value.Value = ""
			value.Content = []*yaml.Node{&item}
		}
		downconvert(value)
	}

	// info.summary is 3.1-only; drop it wherever a mapping carries both a
	// summary and a version (which identifies the info object).
	hasVersion := false
	for i := 0; i+1 < len(node.Content); i += 2 {
		if node.Content[i].Value == "version" {
			hasVersion = true
		}
	}
	if hasVersion {
		for i := 0; i+1 < len(node.Content); i += 2 {
			if node.Content[i].Value == "summary" {
				node.Content = append(node.Content[:i], node.Content[i+2:]...)
				break
			}
		}
	}
}

func loadContract(t *testing.T) (*openapi3.T, routers.Router) {
	t.Helper()
	dir := contractsDir(t)

	loader := &openapi3.Loader{IsExternalRefsAllowed: true}
	loader.ReadFromURIFunc = func(_ *openapi3.Loader, uri *url.URL) ([]byte, error) {
		raw, err := os.ReadFile(uri.Path)
		if err != nil {
			return nil, err
		}
		var doc yaml.Node
		if err := yaml.Unmarshal(raw, &doc); err != nil {
			return nil, err
		}
		downconvert(&doc)
		return yaml.Marshal(&doc)
	}

	doc, err := loader.LoadFromFile(filepath.Join(dir, "openapi.yaml"))
	if err != nil {
		t.Fatalf("load contract: %v", err)
	}
	if err := doc.Validate(loader.Context); err != nil {
		t.Fatalf("the down-converted contract must itself validate: %v", err)
	}
	router, err := gorillamux.NewRouter(doc)
	if err != nil {
		t.Fatalf("router: %v", err)
	}
	return doc, router
}

// TestContractConformance runs the entire endpoint suite with every response
// validated against the contract schemas.
func TestContractConformance(t *testing.T) {
	_, router := loadContract(t)

	validated := 0
	check := func(t *testing.T, req *http.Request, res *http.Response, body []byte) {
		t.Helper()
		// The test request has an httptest host; the contract names a local
		// server. Match by path only, as gorillamux does when hosts differ.
		req.URL.Scheme = "http"
		req.URL.Host = "localhost:8080"
		route, pathParams, err := router.FindRoute(req)
		if err != nil {
			t.Fatalf("no contract route for %s %s: %v", req.Method, req.URL.Path, err)
		}
		input := &openapi3filter.ResponseValidationInput{
			RequestValidationInput: &openapi3filter.RequestValidationInput{
				Request:    req,
				PathParams: pathParams,
				Route:      route,
			},
			Status: res.StatusCode,
			Header: res.Header,
		}
		input.SetBodyBytes(body)
		if err := openapi3filter.ValidateResponse(t.Context(), input); err != nil {
			t.Fatalf("response of %s %s (%d) violates the contract: %v\nbody: %s",
				req.Method, req.URL.Path, res.StatusCode, err, body)
		}
		validated++
	}

	runAPISuite(t, memory.New(), check)
	if validated == 0 {
		t.Fatal("the conformance check never ran")
	}
	t.Logf("validated %d responses against the contract", validated)
}
