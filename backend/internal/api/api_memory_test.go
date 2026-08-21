package api

import (
	"testing"

	"github.com/mcagricaliskan/scrollary/backend/internal/storage/memory"
)

func TestAPISuiteOnMemory(t *testing.T) {
	runAPISuite(t, memory.New(), nil)
}
