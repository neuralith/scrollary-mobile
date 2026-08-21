// Package migrations embeds the SQL migration files so the service applies
// them from its own binary, with no filesystem layout dependency at run time.
//
// This file is Go plumbing only. The migration SQL itself is frozen; schema
// changes are a central decision, never a side effect of other work.
package migrations

import "embed"

// FS holds every migration file, up and down.
//
//go:embed *.sql
var FS embed.FS
