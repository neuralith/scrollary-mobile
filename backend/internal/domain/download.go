package domain

import "time"

// DownloadRequestState is the lifecycle of an intent, never of content.
type DownloadRequestState string

const (
	DownloadPending   DownloadRequestState = "pending"
	DownloadClaimed   DownloadRequestState = "claimed"
	DownloadCompleted DownloadRequestState = "completed"
	DownloadFailed    DownloadRequestState = "failed"
	DownloadCancelled DownloadRequestState = "cancelled"
)

// Terminal reports whether no further transition is expected.
func (s DownloadRequestState) Terminal() bool {
	return s == DownloadCompleted || s == DownloadFailed || s == DownloadCancelled
}

// DownloadRequest is "download this Entry on mobile", expressed as an intent.
//
// The extension does not capture and the backend never fetches content. This
// record says only what the user asked for; a device with a capture engine
// claims it, converts it into an ordinary local save task, and applies its own
// capture policy and validation unchanged.
//
// It is NOT OfflineCopy state and must never be read as one: the server still
// does not know what any device holds. A failure never changes library
// membership (I17).
//
// Device targeting stays minimal - any device may claim - because full device
// management would drag account work into the foundation.
type DownloadRequest struct {
	ID              ID
	LibraryID       LibraryID
	EntryID         ID
	LocationID      *ID
	State           DownloadRequestState
	IdempotencyKey  string
	CreatedBy       string
	CreatedAt       time.Time
	ClaimedByDevice string
	ClaimedAt       *time.Time
	ResolvedAt      *time.Time
	FailureReason   string
	Revision        Revision
}

// Claim moves a pending request to claimed for exactly one device.
//
// The single-winner conditional transition is the same pattern V1 already uses
// for its queue: exactly one caller wins and the loser is told, rather than
// both proceeding and one silently overwriting the other.
func (d *DownloadRequest) Claim(device string, at time.Time) error {
	if d.State != DownloadPending {
		return ErrRequestClaimed
	}
	d.State = DownloadClaimed
	d.ClaimedByDevice = device
	d.ClaimedAt = &at
	return nil
}

// Resolve records the terminal state a device reported.
func (d *DownloadRequest) Resolve(state DownloadRequestState, reason string, at time.Time) error {
	if !state.Terminal() {
		return ErrRequestClaimed
	}
	d.State = state
	d.FailureReason = reason
	d.ResolvedAt = &at
	return nil
}
