package api

import (
	"testing"

	"github.com/neuralith/scrollary-backend/internal/storage/memory"
)

func TestAPISuiteOnMemory(t *testing.T) {
	runAPISuite(t, memory.New(), nil)
}
