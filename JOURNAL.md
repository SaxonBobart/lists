# Lists — My Journal

*Plain-English notes for me (Saxon): what I've built so far, and what I want to build next.*
*This one's mine. Agents can read it for context on what I care about — but don't edit it unless I ask.*

---

## What Lists is

A calm, native iOS app for tasks, habits, notes, and events — all stored as plain text files on my phone. No account, no sign-in, works offline. iOS only for now.

## What I've built so far

*(Newest first. This is the human version — the technical play-by-play is in `docs/CHANGELOG.md`.)*

- **Events** — a proper calendar item type with a start and an end. Some events are just "things happening" (they quietly drop off the list once they're over but stay in the timeline); others can be ticked off like a task. *(June 2026)*
- **The document view** — tap a task, note, or event and it opens full-screen like an Apple Notes page: title up top, the key facts in one line, and the body text you edit straight away, no save button.
- **Past events roll off the list** — once an event's over it leaves the list (but stays in the calendar timeline), so the list only shows what still needs me.
- **Habits, redone** — log each time I do something, with forgiving streaks ("never miss twice") and flexible goals like "3 times a week." A little progress ring on each row, and a contribution grid in the detail view.
- **Nested lists** — lists can hold other lists, as deep as I want, shown as a collapsible tree in the sidebar.
- **The markdown editor** — an Apple Reminders–style editor with tappable checkboxes, smart return/tab, and undo/redo.
- **Tags** — type `#something` in a title and it becomes a tag: coloured text inline, filter chips in the Tags overview.
- **Smart lists** — Today, Scheduled, Flagged, Urgent, Completed, All — live queries, not folders.

## What I want to build next

- **A calendar view** over scheduled items — the scroll-back timeline past events live in. (The event fields are already shaped for it.)
- **iCal import / export / sync** — get events in and out of real calendars.
- **Developer-friendly markdown** — finish the half-built extensions (wikilink navigation, footnotes, math, mermaid, tables), add callouts (`> [!NOTE]`), live-styled `#tags` with autocomplete, and syntax-highlighted code blocks. *(Detail: `docs/research/markdown-editor-architecture.md`.)*
- **Pluggable item types** — make habits the first "plugin" type, so new kinds of items can be added later without touching the core. *(Detail: `docs/research/pluggable-item-types.md`.)*

## Someday / parked (not now)

- Sync across devices
- Android and other platforms
- App Store release
- Urgent alarms (needs a paid Apple Developer account first)
- AI / agent features inside the app itself

## How I work on this

I build the product; Claude handles the code, the saving and backups (git), and the testing — I don't need to touch the terminal. For where things stand, the short version is here; the agent-facing detail is in `docs/CURRENT.md`, and how saving/backups work is in `GIT-GUIDE.md`.
