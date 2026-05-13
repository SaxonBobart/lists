# ULID

Lists ids are ULID-like sortable identifiers.

Rules:

- Use uppercase Crockford base32.
- Exclude ambiguous letters: `I`, `L`, `O`, `U`.
- Preserve lexicographic sort by creation time.
- Inbox sentinel id: `00000000000000000000INBOX0`.

Do not change existing ids during migrations.
