package api

// The single error payload shape (contracts/errors.yaml): `code` is the only
// field a client may branch on, `message` is display text, `details` is
// code-specific context. Every non-2xx body goes through here so no handler
// can invent a shape of its own.

type errorBody struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

type errorResponse struct {
	Error errorBody `json:"error"`
}

func writeError(c fiberCtx, status int, code, message string, details map[string]any) error {
	return c.Status(status).JSON(errorResponse{Error: errorBody{
		Code:    code,
		Message: message,
		Details: details,
	}})
}
