package api

import "github.com/gofiber/fiber/v3"

// fiberCtx aliases the handler context so tests can declare handlers without
// repeating the framework import.
type fiberCtx = fiber.Ctx
