-- Canonical SQLite cache schema for Lists.
-- Each platform's ORM may reformat (Room annotations, EF migrations, etc.),
-- but the column names + types must match this file. See ./README.md.

-- ---------------------------------------------------------------------------
-- Source-of-truth tables (mirror the file tree)
-- ---------------------------------------------------------------------------

CREATE TABLE lists (
    id              TEXT PRIMARY KEY NOT NULL,           -- ULID
    name            TEXT NOT NULL,
    kind            TEXT NOT NULL CHECK (kind IN ('task', 'habit', 'shopping')),
    color           TEXT NOT NULL,                       -- named palette colour
    icon            TEXT NOT NULL,                       -- SF Symbol / Material / Fluent / symbolic
    created         TEXT NOT NULL,                       -- ISO 8601 UTC
    modified        TEXT NOT NULL,                       -- ISO 8601 UTC
    position        REAL NOT NULL DEFAULT 0,             -- fractional index
    deleted_at      TEXT,                                -- ISO 8601 UTC tombstone, NULL = live
    lamport         INTEGER NOT NULL DEFAULT 0,
    -- cache-only metadata (not in .list.yml)
    last_seen_mtime INTEGER NOT NULL,                    -- file mtime in epoch ms
    last_walk_id    INTEGER NOT NULL                     -- bumped each full walk
);

CREATE INDEX idx_lists_position    ON lists (position);
CREATE INDEX idx_lists_deleted     ON lists (deleted_at);

CREATE TABLE reminders (
    id                  TEXT PRIMARY KEY NOT NULL,       -- ULID
    list_id             TEXT NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
    parent_id           TEXT REFERENCES reminders(id) ON DELETE CASCADE,
    title               TEXT NOT NULL,
    body                TEXT NOT NULL DEFAULT '',        -- markdown body
    created             TEXT NOT NULL,                   -- ISO 8601 UTC
    modified            TEXT NOT NULL,                   -- ISO 8601 UTC
    date                TEXT,                            -- YYYY-MM-DD or NULL
    time                TEXT,                            -- HH:MM:SS or NULL
    time_zone           TEXT,                            -- IANA tz id or NULL = floating local
    has_time            INTEGER NOT NULL DEFAULT 0,      -- generated: time IS NOT NULL
    urgent              INTEGER NOT NULL DEFAULT 0,      -- bool 0/1
    priority            TEXT NOT NULL DEFAULT 'none' CHECK (priority IN ('none', 'low', 'medium', 'high')),
    flagged             INTEGER NOT NULL DEFAULT 0,
    recurrence          TEXT,                            -- RRULE subset string
    location_lat        REAL,                            -- denormalised from location_trigger
    location_lng        REAL,
    location_radius_m   REAL,
    location_on         TEXT CHECK (location_on IN ('arrive', 'leave') OR location_on IS NULL),
    completed           INTEGER NOT NULL DEFAULT 0,
    completed_at        TEXT,
    section             TEXT,                            -- shopping only
    position            REAL NOT NULL DEFAULT 0,
    deleted_at          TEXT,
    lamport             INTEGER NOT NULL DEFAULT 0,
    -- cache-only metadata
    file_path           TEXT NOT NULL UNIQUE,            -- absolute path to the .md file
    last_seen_mtime     INTEGER NOT NULL,                -- file mtime in epoch ms
    last_walk_id        INTEGER NOT NULL
);

CREATE INDEX idx_reminders_list           ON reminders (list_id);
CREATE INDEX idx_reminders_parent         ON reminders (parent_id);
CREATE INDEX idx_reminders_date           ON reminders (date)             WHERE deleted_at IS NULL;
CREATE INDEX idx_reminders_completed      ON reminders (completed)        WHERE deleted_at IS NULL;
CREATE INDEX idx_reminders_flagged        ON reminders (flagged)          WHERE deleted_at IS NULL;
CREATE INDEX idx_reminders_urgent         ON reminders (urgent)           WHERE deleted_at IS NULL;
CREATE INDEX idx_reminders_modified       ON reminders (modified);
CREATE INDEX idx_reminders_completed_at   ON reminders (completed_at);
CREATE INDEX idx_reminders_deleted        ON reminders (deleted_at);

CREATE TABLE tags (
    reminder_id     TEXT NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
    tag             TEXT NOT NULL,
    PRIMARY KEY (reminder_id, tag)
);

CREATE INDEX idx_tags_tag      ON tags (tag);

CREATE TABLE completion_history (
    -- Habit completion dates. One row per (reminder_id, completed_date).
    reminder_id     TEXT NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
    completed_date  TEXT NOT NULL,                       -- YYYY-MM-DD
    PRIMARY KEY (reminder_id, completed_date)
);

CREATE INDEX idx_completion_history_date ON completion_history (completed_date);

-- ---------------------------------------------------------------------------
-- Device-local tables (NOT derivable from files; never synced)
-- ---------------------------------------------------------------------------

CREATE TABLE device_settings (
    key             TEXT PRIMARY KEY NOT NULL,
    value           TEXT NOT NULL
);
-- Seeded on first run with: library_path, default_list_id, hide_completed_ms,
-- urgent_alarm_volume, default_notification_time_hhmm.

CREATE TABLE notification_state (
    -- One row per scheduled notification / alarm. Used to cancel on edit.
    reminder_id     TEXT PRIMARY KEY NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
    kind            TEXT NOT NULL CHECK (kind IN ('alarm', 'notification')),
    handle          TEXT NOT NULL,                       -- platform-specific (alarm id, request id)
    fire_at         TEXT NOT NULL,                       -- ISO 8601 UTC
    scheduled_at    TEXT NOT NULL                        -- ISO 8601 UTC; for diagnostics
);

CREATE INDEX idx_notification_state_fire_at ON notification_state (fire_at);

CREATE TABLE cache_meta (
    -- Single-row table tracking the cache's own bookkeeping.
    id                  INTEGER PRIMARY KEY CHECK (id = 1),
    schema_version      INTEGER NOT NULL,
    library_root        TEXT NOT NULL,
    last_full_walk      TEXT NOT NULL,                   -- ISO 8601 UTC
    current_walk_id     INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- Views (optional; documented for cross-platform consistency)
-- ---------------------------------------------------------------------------

CREATE VIEW v_smart_today AS
    SELECT r.*
      FROM reminders r
     WHERE r.deleted_at IS NULL
       AND r.completed = 0
       AND (
           r.date <= date('now', 'localtime')
           OR (
               r.recurrence IS NOT NULL
               -- (recurrence "is today and not in completion_history" handled in app code)
           )
       );

CREATE VIEW v_smart_scheduled AS
    SELECT r.*
      FROM reminders r
     WHERE r.deleted_at IS NULL
       AND r.completed = 0
       AND r.date IS NOT NULL
     ORDER BY r.date ASC, r.time ASC;

CREATE VIEW v_smart_flagged AS
    SELECT r.*
      FROM reminders r
     WHERE r.deleted_at IS NULL
       AND r.completed = 0
       AND r.flagged = 1;

CREATE VIEW v_smart_urgent AS
    SELECT r.*
      FROM reminders r
     WHERE r.deleted_at IS NULL
       AND r.completed = 0
       AND r.urgent = 1;

CREATE VIEW v_smart_completed AS
    SELECT r.*
      FROM reminders r
     WHERE r.deleted_at IS NULL
       AND r.completed = 1
     ORDER BY r.completed_at DESC;
