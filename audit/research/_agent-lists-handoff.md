# Agent-Lists — the founder's idea (verbatim sketch)

Saxon's note: *"Don't actually follow this like a Bible — this is just a random chat I had with
Claude about the kind of idea I wanted."* Treat as a direction to pressure-test, not a spec.

---

I'm adding a new list type to Lists called **"agent list"** — a list whose items are worked on by an
external agent process (OpenClaw, Hermes, etc.) that reads and writes the list's markdown files
directly. The protocol is files-only; no custom API.

**Core design:**

1. **Agent list** = a list whose directory is accessed by an external worker process. Same
   markdown-with-YAML-frontmatter format as every other list. Workers conform to a documented file
   protocol; the app is worker-agnostic.

2. **Four sections** in the agent list view, in this order:
   - **Needs Attention**: items with pending questions or error status
   - **Working**: items with `status=in_progress` and a valid claim
   - **Scheduled**: items with future `scheduled_at` or recurring habits
   - **Completed**: `status=done`, collapsed by default

3. **New item type: "question"** (child of a task). Frontmatter fields:
   - `question_text`: string
   - `answer_type`: `yes_no` | `choice` | `text`
   - `choices`: [string] (when `answer_type=choice`)
   - `answer`: string | null (filled by user; presence unblocks parent)
   - `risk`: `low` | `high` (high renders with confirmation friction)
   - `parent`: parent task id
   Render inline at the list row level when the parent is in Needs Attention. Tick/cross for
   `yes_no`, chips for `choice`, expandable text field always available as "other". On answer, write
   the file, child resolves, parent task transitions back to Working.

4. **Claim mechanism** in task frontmatter:
   - `claimed_by`: hostname/worker id
   - `claimed_at`: timestamp
   - Workers write a claim before starting; others skip claimed items; stale claims (no progress in
     N minutes) auto-release.

5. **Status bubble** at top of agent list view, reads from `<list_dir>/_status.md` (markdown w/ frontmatter):
   - `current_task`: task id or null
   - `next_scheduled`: timestamp or null
   - `last_active`: timestamp
   - `summary`: free-form one-to-three-line natural language
   App reads file directly on change, no model calls. Status dot derives from `last_active` freshness
   (green <60s, amber <5min, red beyond).

6. **Recurring agent jobs** reuse the existing habit item type with the agent worker attached. The
   habit's recurrence machinery handles scheduling; each fire spawns a child task that flows through
   the normal Working → Completed lifecycle so there's a history per run.

7. **Worker config** per list:
   - `worker_type`: `local_byo` | `hosted`
   - `worker_endpoint`: discovery info (path, hostname, or hosted service id)
   - Same UI for both; the only difference is where the worker process runs.
