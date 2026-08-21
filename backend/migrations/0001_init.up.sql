-- Scrollary V2 -- initial schema.
--
-- This is a FRESH schema designed from the V2 domain, not derived from the
-- mobile database and not migrated from anything. There are no released users
-- (DECISIONS.md V2-D1), so nothing is carried forward.
--
-- What is deliberately ABSENT is as much of the contract as what is present:
-- no offline copies, no browsing history, no capture or save-queue state, no
-- reading anchors, no content. Those are device-owned. Reproducing the mobile
-- database here is the mistake this boundary exists to prevent.

CREATE TABLE libraries (
    id          UUID PRIMARY KEY,
    name        TEXT        NOT NULL UNIQUE,
    revision    BIGINT      NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Folders: user organisation, a tree with exactly one system root per library.
--
-- I1 is enforced by the CHECK plus the partial unique index: parent_id is NULL
-- if and only if kind = 'root', and there can be only one root.
CREATE TABLE folders (
    id          UUID PRIMARY KEY,
    library_id  UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    parent_id   UUID        REFERENCES folders(id) ON DELETE RESTRICT,
    kind        TEXT        NOT NULL CHECK (kind IN ('root','user')),
    name        TEXT        NOT NULL,
    sort_key    BIGINT      NOT NULL DEFAULT 0,
    revision    BIGINT      NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT folder_root_has_no_parent
        CHECK ((kind = 'root') = (parent_id IS NULL)),
    CONSTRAINT folder_is_not_its_own_parent
        CHECK (parent_id IS NULL OR parent_id <> id)
);
CREATE UNIQUE INDEX one_root_per_library ON folders(library_id) WHERE kind = 'root';
CREATE INDEX folders_by_parent ON folders(library_id, parent_id, sort_key);
CREATE INDEX folders_by_revision ON folders(library_id, revision);

-- Collections: a logical work. No URL and no host -- those belong to Sources,
-- which is what lets a Collection outlive the site that published it.
--
-- lifecycle 'active' means the user follows it; that is the authorisation for
-- Scrollary to keep it current from their reading. 'archived' stops following
-- and preserves everything.
CREATE TABLE collections (
    id                  UUID PRIMARY KEY,
    library_id          UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    folder_id           UUID        NOT NULL REFERENCES folders(id) ON DELETE RESTRICT,
    name                TEXT        NOT NULL,
    detected_title      TEXT        NOT NULL DEFAULT '',
    ordering_basis      TEXT        NOT NULL CHECK (ordering_basis IN (
                            'explicitNumericIndex','publicationDate',
                            'detectedNextLink','discoveryOrder','userDefinedManualOrder')),
    lifecycle           TEXT        NOT NULL CHECK (lifecycle IN ('active','archived')),
    preferred_source_id UUID,
    sort_key            BIGINT      NOT NULL DEFAULT 0,
    revision            BIGINT      NOT NULL,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX collections_by_folder ON collections(library_id, folder_id, sort_key);
CREATE INDEX collections_by_revision ON collections(library_id, revision);

-- Sources: one Collection as published on one site.
--
-- (host, path_key) is the Source's identity -- what V1 computed as
-- collection_key, at the level it actually identifies. Language lives here
-- because a translation is a Source of the same work: you read the work once.
--
-- Active alternatives and dead predecessors share this one structure with
-- different lifecycle; a site returning is a state change, not a row moved
-- between tables. There is no separate source-history table.
CREATE TABLE sources (
    id                       UUID PRIMARY KEY,
    library_id               UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    collection_id            UUID        NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    host                     TEXT        NOT NULL,
    path_key                 TEXT        NOT NULL,
    language                 TEXT        NOT NULL DEFAULT '',
    lifecycle                TEXT        NOT NULL CHECK (lifecycle IN ('active','dormant','dead','resolvedInto')),
    resolved_into_source_id  UUID        REFERENCES sources(id) ON DELETE SET NULL,
    first_seen_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    revision                 BIGINT      NOT NULL,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT source_identity UNIQUE (collection_id, host, path_key)
);
CREATE INDEX sources_by_identity ON sources(library_id, host, path_key);
CREATE INDEX sources_by_revision ON sources(library_id, revision);

-- I9: a preferred Source must belong to its Collection.
ALTER TABLE collections
    ADD CONSTRAINT preferred_source_belongs_to_collection
    FOREIGN KEY (preferred_source_id) REFERENCES sources(id) ON DELETE SET NULL;

-- Entries: one logical unit of reading, and what reading state belongs to.
--
-- An Entry is NOT a URL. I3 is enforced below: an Entry has a folder if and
-- only if it has no collection, so a standalone Entry is a first-class library
-- item placed directly in a Folder and is never wrapped in a Collection of one.
--
-- ordinal NULL means unplaced: a real, visible state where no position could be
-- established. The app keeps the contradiction rather than guessing one.
CREATE TABLE entries (
    id             UUID PRIMARY KEY,
    library_id     UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    collection_id  UUID        REFERENCES collections(id) ON DELETE CASCADE,
    folder_id      UUID        REFERENCES folders(id) ON DELETE RESTRICT,
    ordinal        DOUBLE PRECISION,
    placement      TEXT        NOT NULL CHECK (placement IN ('placed','unplaced','userPlaced')),
    title          TEXT        NOT NULL DEFAULT '',
    sort_key       BIGINT      NOT NULL DEFAULT 0,
    revision       BIGINT      NOT NULL,
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT entry_placement
        CHECK ((collection_id IS NULL) = (folder_id IS NOT NULL)),
    CONSTRAINT unplaced_entry_has_no_ordinal
        CHECK (placement <> 'unplaced' OR ordinal IS NULL)
);
-- I8: an ordinal is unique within its collection, so two Sources reporting the
-- same position resolve to one logical Entry rather than to two.
CREATE UNIQUE INDEX entry_ordinal_unique
    ON entries(collection_id, ordinal)
    WHERE collection_id IS NOT NULL AND ordinal IS NOT NULL;
CREATE INDEX entries_by_collection ON entries(library_id, collection_id, ordinal);
CREATE INDEX entries_by_folder ON entries(library_id, folder_id) WHERE folder_id IS NOT NULL;
CREATE INDEX entries_by_revision ON entries(library_id, revision);

-- Locations: this Entry, at one URL, on one Source.
--
-- url_key is unique per library (I6): one URL is one place. This index is the
-- recognition hot path -- a URL the library already knows resolves in one
-- lookup, with no arbitration and no round trip.
--
-- source_label and source_number are what the site printed. They are evidence,
-- never identity.
CREATE TABLE locations (
    id               UUID PRIMARY KEY,
    library_id       UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    entry_id         UUID        NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    source_id        UUID        REFERENCES sources(id) ON DELETE CASCADE,
    url              TEXT        NOT NULL,
    url_key          TEXT        NOT NULL,
    source_label     TEXT        NOT NULL DEFAULT '',
    source_number    DOUBLE PRECISION,
    discovered_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    discovery_basis  TEXT        NOT NULL DEFAULT '',
    lifecycle        TEXT        NOT NULL CHECK (lifecycle IN ('active','retracted')),
    revision         BIGINT      NOT NULL,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT location_url_key_unique UNIQUE (library_id, url_key)
);
CREATE INDEX locations_by_entry ON locations(library_id, entry_id);
CREATE INDEX locations_by_source ON locations(library_id, source_id);
CREATE INDEX locations_by_revision ON locations(library_id, revision);

-- Reading state: the portable, language-agnostic fact about an Entry.
--
-- A separate table rather than columns on entries, for a concrete reason:
-- reading updates are the most frequent mutation, and a separate row means a
-- separate revision -- so marking something read does not bump the Entry's
-- metadata revision and force every other client to re-pull metadata that did
-- not change.
--
-- There is deliberately no anchor column. An index and offset inside a specific
-- artifact is meaningless without the bytes it indexes, so it lives on the
-- device's offline copy and never leaves it.
CREATE TABLE reading_states (
    entry_id        UUID PRIMARY KEY REFERENCES entries(id) ON DELETE CASCADE,
    library_id      UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    status          TEXT        NOT NULL CHECK (status IN ('unread','reading','completed')),
    first_opened_at TIMESTAMPTZ,
    last_read_at    TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    revision        BIGINT      NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX reading_states_by_revision ON reading_states(library_id, revision);

-- Measurements: progress scoped to the rendering it was measured against.
--
-- I12: the Source is part of the key, so a reading taken on one Source can
-- never be silently read as a claim about another.
CREATE TABLE measurements (
    entry_id    UUID        NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    source_id   UUID        NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
    library_id  UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    fraction    DOUBLE PRECISION NOT NULL CHECK (fraction >= 0 AND fraction <= 1),
    observed_at TIMESTAMPTZ NOT NULL,
    revision    BIGINT      NOT NULL,
    PRIMARY KEY (entry_id, source_id)
);
CREATE INDEX measurements_by_revision ON measurements(library_id, revision);

-- Download requests: an intent, never content.
--
-- The extension does not capture and this service never fetches. A device with
-- a capture engine claims a request, converts it into an ordinary local save
-- task and applies its own capture policy unchanged. This is NOT offline-copy
-- state: the server still does not know what any device holds.
--
-- The partial unique index gives idempotency by construction -- at most one
-- non-terminal request per (library, entry), so pressing the button twice does
-- not queue two saves.
CREATE TABLE download_requests (
    id                 UUID PRIMARY KEY,
    library_id         UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    entry_id           UUID        NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    location_id        UUID        REFERENCES locations(id) ON DELETE SET NULL,
    state              TEXT        NOT NULL CHECK (state IN ('pending','claimed','completed','failed','cancelled')),
    idempotency_key    TEXT        NOT NULL DEFAULT '',
    created_by         TEXT        NOT NULL DEFAULT '',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_by_device  TEXT        NOT NULL DEFAULT '',
    claimed_at         TIMESTAMPTZ,
    resolved_at        TIMESTAMPTZ,
    failure_reason     TEXT        NOT NULL DEFAULT '',
    revision           BIGINT      NOT NULL
);
CREATE UNIQUE INDEX one_open_request_per_entry
    ON download_requests(library_id, entry_id)
    WHERE state IN ('pending','claimed');
CREATE INDEX download_requests_by_revision ON download_requests(library_id, revision);

-- Tombstones: deliberate user removals only.
--
-- A Location a Source stopped listing does NOT produce one: that is
-- source-scoped evidence each device reconciles from its own reading, and
-- propagating it would let a stale reading on one device remove a row on
-- another. A tombstone never destroys bytes on any device (I14).
CREATE TABLE tombstones (
    library_id  UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    kind        TEXT        NOT NULL CHECK (kind IN (
                    'folder','collection','source','entry','location',
                    'readingState','measurement','downloadRequest')),
    entity_id   UUID        NOT NULL,
    revision    BIGINT      NOT NULL,
    deleted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (library_id, kind, entity_id)
);
CREATE INDEX tombstones_by_revision ON tombstones(library_id, revision);

-- Mutation ledger: idempotency over client-supplied mutation ids, so a retry
-- after an ambiguous failure is safe. The outbox will retry; this is what makes
-- that harmless.
CREATE TABLE mutations (
    library_id   UUID        NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    mutation_id  TEXT        NOT NULL,
    applied_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    revision     BIGINT      NOT NULL,
    PRIMARY KEY (library_id, mutation_id)
);
