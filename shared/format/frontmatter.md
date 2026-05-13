# Frontmatter Rules

Item files use YAML frontmatter followed by a markdown body.

```text
---
id: ...
title: ...
---

Markdown body
```

Rules:

- Opener and closer are exactly `---` on their own line.
- Writers emit UTF-8 and `\n` line endings.
- Readers should tolerate `\r\n`.
- Everything after the closing fence is markdown body.
- Writers preserve key order for readable diffs.
- Dates and times are strings, not YAML-native dates.
- Unknown keys should be preserved where possible for forward compatibility.

iOS reference: `platforms/ios/Lists/Core/Storage/FrontmatterCodec.swift`.
