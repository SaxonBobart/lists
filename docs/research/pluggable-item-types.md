# Pluggable Item Types

Research note for a future architecture direction. This is not current app UI.

## Current Rule

Lists has one durable primitive, `Item`, with four current types: task, habit, note, and event.

Habits are the first-party module-shaped type:

- They share `Item` identity, tags, list placement, reminders, priority, and flags.
- They do not expose or persist a markdown body.
- They own their completion history, current-cycle progress, heatmap, log, and detail screen.
- They have smart-list rules that differ from tasks/notes/events.
- Settings presents Habits as built in, not as an external plugin.

That is the product behavior to preserve. A future plugin architecture should make this clearer internally without making Habits feel optional or separate to the user.

## Possible Direction

If more item types become real, extract type behavior behind a small first-party module surface:

- Row leading control and primary tap behavior.
- Detail surface route.
- Completion semantics.
- Smart-list participation.
- Capture/edit fields.
- Storage normalization.

The first useful extraction would be habits, because habit behavior is already the most separate. The goal would be less branching and clearer ownership, not a visible feature change.

## Constraints

- Keep the on-disk `type` string stable.
- Unknown types should continue to degrade safely.
- Do not add a Plugins settings area until there is a real user-facing plugin capability.
- Do not split product behavior by platform; Android should translate the same type/module rules natively when Android work resumes.
