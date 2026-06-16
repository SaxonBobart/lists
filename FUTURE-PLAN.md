# Lists -- Future Plan & Strategy

This doc captures the long-range product direction: mission, market position,
cross-platform plan, Markdown/file philosophy, agents, sync, monetization, and
the honest risks. `PRODUCT-SPEC.md` describes what the app is. `docs/CURRENT.md`
describes where the build is now. This describes where it is going and why.

Living document, revised after product planning on 2026-06-17.

---

## Mission

Lists is the private, open, native tasks + notes + reminders app that should
already exist on every operating system.

The product belief is simple: nobody should be locked out of the good version
because they use Android, Windows, Linux, an older/budget device, or cannot pay a
subscription. The app should feel like a default system app, but the data should
belong to the user.

The philosophy:

- Free forever for the app itself.
- Open source.
- Native-feeling on every platform.
- Local-first and private by default.
- Real files and documented formats.
- No account required for local use.
- Paid only when Saxon is running infrastructure or providing support that has a
  real ongoing cost.

The trust promise:

> If Lists disappears tomorrow, your files still work.

That is the product's strongest moral and commercial wedge. Users are not held
hostage by pricing, cloud lock-in, proprietary formats, or a company changing
direction.

---

## Positioning

The mainstream pitch:

> Apple Reminders + Apple Notes, but open-source, private, free, and native
> everywhere.

The shorter pitch:

> Free forever. Open source. Native everywhere. Your data stays yours.

The technical trust pitch:

> Real Markdown files, local-first storage, self-hostable sync, and native
> clients that respect every platform.

Do not lead with Markdown, plugins, AI, dashboards, methods, or agents. Those are
trust and power layers. The front door is a calm app for tasks, notes, reminders,
events, and habits.

The honest competitor statement:

- Some apps let tasks have notes, reminders, and repeat rules.
- Some apps support Markdown-like editing.
- Some apps are cross-platform.
- Some apps are beautiful.
- Some apps are free or open-source.

The gap is the combination: simple default-app UX, real reminders, rich notes,
real Markdown/files, native cross-platform clients, privacy, open source, free
core app, self-hostability, and no lock-in.

Do not claim "nothing has rich task notes." Claim:

> Nothing has this philosophy, this trust model, and this native-everywhere
> product shape.

---

## Core Loop

The app wins or loses on the first five minutes.

First launch should feel like opening a preinstalled app:

1. Empty Inbox.
2. Plus button.
3. Start typing.
4. Lists understands the task/note/reminder/event facts.
5. Tap the item later and it has a full document body underneath.

No account wall. No onboarding carousel. No sample productivity method. No
"choose your workspace." If onboarding exists, it should be one small native
sheet or a settings link:

> Free forever. Private by default. Your data stays yours.

The quick-capture direction:

- The normal title field becomes smarter; there is no separate AI box.
- Typing natural language can surface parsed chips/facts for date, time, repeat,
  flag, priority, tags, and type.
- The title should not be silently rewritten unless the change is visible,
  reversible, and clearly useful.
- Detailed sheets exist for correction, not as the primary path.

The core loop to make excellent:

> Open app -> type anything -> it becomes the right task/note/reminder -> it
> looks clean -> it works everywhere -> the file remains yours.

---

## Audience

Lists has two audiences, and both matter.

**Mainstream users** create scale. They want a simple app that works on all their
devices without an account, subscription, or privacy trade-off.

**Power users** create early trust and distribution. They inspect whether the
architecture is serious, whether Markdown is real, whether export is fake, and
whether the app is trying to trap them. If they respect it, they recommend it to
normal people.

The product should therefore have two doors:

- **Front door:** clean default-app experience for normal use.
- **Trust door:** open source, real Markdown, documented format, plugins,
  self-hosting, and external-agent hooks.

The mistake is letting the trust door visually dominate the front door. Power
features should be discoverable and strong, but they should not clutter the
default task/notes experience.

---

## Design Direction

The app should feel like the operating system should have shipped it.

Design benchmarks:

- Apple Reminders for capture, lists, calm metadata, and native familiarity.
- Apple Notes for document feel.
- Things for restraint and polish.
- Platform-native apps on Android, Windows, Linux, and macOS for each client's
  interaction language.

Avoid the category traps:

- Web dashboard dressed as mobile app.
- Productivity methodology app before the user has created one item.
- Notion/Craft-style workspace overhead for a simple reminder.
- Markdown power-user UI as the default surface.
- SaaS AI dashboard language inside the product.

Item rows should preserve the current direction:

- Title first.
- Metadata/facts quiet and readable.
- Tags separate enough to scan.
- Notes/body preview softer than the action fields.
- Extreme metadata can wrap or collapse without turning the row into a
  spreadsheet.

---

## Markdown & File Philosophy

Markdown is not the mainstream headline. It is one of the deepest product
advantages.

The framing:

> Normal users get a clean reminders/notes app. Power users get real files that
> still make sense without Lists.

Rules:

- The item body is real Markdown, not app-shaped content pretending to be
  Markdown.
- Frontmatter stores Lists metadata for app-native items.
- External Markdown should be tolerated. A random `README.md`, docs folder, repo,
  Obsidian vault, or plain notes folder should render reasonably without Lists
  needing to own it.
- Do not inject proprietary metadata into external files unless the user
  explicitly turns that folder into a Lists workspace.
- Preserve source text when possible. Parsing should add usefulness, not corrupt
  the document.

Tags should be hybrid:

- Frontmatter tags are app-managed tags.
- Inline `#tags` in title/body remain in the Markdown and are parsed, styled,
  linked, and indexed.
- Effective tags are the union of app-managed tags and inline tags.
- Rename/delete behavior for inline tags should be explicit because it edits
  prose.

Developer-friendly Markdown direction:

- Wikilinks and backlinks.
- Footnotes.
- Tables.
- Math.
- Mermaid/diagrams.
- Callouts.
- Syntax-highlighted code.
- Live inline tags.
- Markdown checkboxes that can optionally be promoted into real Lists tasks.

The long-term power feature:

> Connect a folder or repo and let Lists read the Markdown without forcing it
> into a proprietary system.

---

## Item Types & Plugins

The core product should stay narrow:

- Task/reminder.
- Note.
- Event.
- Habit.
- Question, when agent workflows need a human reply.

Tasks, notes, and events share the document path: title, metadata, tags, Markdown
body. Habits are the first clean plugin-style item type because their completion
model is different.

Plugins exist to keep the core simple:

- New item types can be enabled in settings.
- Power-user features should not leak into normal rows unless the user enabled
  them.
- Plugins should integrate with the same list/detail/search/tag/smart-list
  surfaces rather than creating separate mini-apps.

The rule:

> Add depth without making the default app feel deep.

---

## Agents & AI

Lists should not become an agent platform or chat app. It should be the native
task/document surface that external agents can use.

External systems such as Hermes, OpenClaw, Codex, local scripts, MCP tools, or
future agent runners do the work. Lists gives them a sane human-facing workflow.

The contract should be small:

- Create an item.
- Update item metadata.
- Append notes/progress.
- Create subtasks.
- Create `question` subitems.
- Request approval.
- Mark blocked/done.
- Attach artifacts, links, files, or run logs.

User-facing model:

- An **agent task** is a normal task with agent metadata.
- A **question** is a child item whose main action is Reply.
- An **approval** can be metadata on a task/question at first; only make it its
  own item type if the workflow proves common.
- Agent output lives in the same item/document system as everything else.

Useful smart lists later:

- Needs Reply.
- Waiting on Agent.
- Needs Approval.
- Agent Runs, if a run history view becomes necessary.

Avoid:

- Dedicated agent dashboard as the main UI.
- Chat-first interaction.
- Hidden agent-only databases.
- Agents silently touching broad scopes.

Every agent action should have a scope:

- This item.
- This list.
- This folder.
- This repo.
- This plugin.

The product line:

> Agents do not live in a chat box. They create tasks, ask questions, and leave
> notes where your work already lives.

AI in capture should be optional and provider-based:

- Deterministic parser first.
- Platform intelligence where available.
- User-chosen local/cloud provider where desired.
- BYOK when external model APIs cost money.
- If the user hates AI, the plugin/provider can stay off.

Platform intelligence is a client superpower, not the product foundation. Apple
clients can use Apple APIs deeply; Android clients should use Android-native
equivalents where possible; every platform needs a non-AI fallback.

---

## Cross-Platform Strategy

The product only becomes truly interesting when it is not Apple-only.

Principles:

- Nobody is second-class.
- Native UI on every platform.
- Same product behavior and file model everywhere.
- Platform-specific APIs are adapters, not the foundation.
- No feature should be permanently Apple-only if Android, Windows, Linux, or
  macOS can reasonably provide an equivalent.

Apple clients can go deep on Apple APIs:

- App Intents.
- Shortcuts/Siri surfaces.
- Spotlight.
- Widgets/controls.
- Share sheet.
- Calendar/reminder integrations.
- Local notifications and future alarm capabilities.
- Apple Intelligence where it genuinely improves parsing or automation.

Android should not be "iOS but worse." It should respect Android:

- Material 3 / Material You.
- Android notification and alarm realities.
- Intents/share targets.
- Files/document providers.
- Homescreen widgets.
- Android-native intelligence integrations where useful.

Windows/Linux/macOS should not be web shells. They should feel like real desktop
apps with platform-appropriate menus, shortcuts, windows, file access, and
notification behavior.

The technical destination is shared behavior, not shared UI. A shared core may
eventually own the file format, recurrence, Markdown parsing, sync/conflict
logic, and plugin contracts while each platform keeps its native interface.

---

## Sync Strategy

Free sync should exist wherever the user is supplying the account or storage.

Free/user-owned options:

- iCloud sync on Apple when it uses the user's iCloud.
- Syncthing.
- Nextcloud.
- Dropbox/OneDrive/Google Drive-style folders where the platform file APIs make
  that viable.
- Git or repo-backed folders for technical users.
- Self-hosted Lists sync.

Paid sync is only for infrastructure Saxon runs:

- Hosted Lists Cloud sync.
- Hosted web access.
- Attachment storage.
- Cross-device push/reliability services.
- Cloud compute or agent runners.

Conflict safety matters more than transport:

- Files are the source of truth.
- Indexes/caches are rebuildable.
- Deletes are tombstoned.
- Worst-case conflict behavior should duplicate or ask, not lose data.
- Free file-sync warnings should be specific and honest, not vague scare copy.

Reminder reliability:

- Same-device reminders should always work and should never be paywalled.
- Cross-device reminders are the hard case because sleeping devices may need a
  push/reliable sync channel.
- If a paid hosted service provides stronger cross-device reminder guarantees,
  the reason must be real infrastructure cost, not artificial crippling.

---

## Monetization

This is not open-core. Do not lock normal app capability behind "Pro."

The pricing rule:

> If it runs on the user's device or the user's account, it is free. If it runs
> on Saxon's infrastructure, charge enough to cover the cost and keep the project
> alive.

Free forever:

- Local app.
- Tasks/reminders/notes/events/habits.
- Markdown/files.
- Plugins.
- Import/export.
- Local notifications.
- Platform-provided sync such as iCloud when it uses the user's account.
- Self-hosting.
- No account required for local use.

Paid only for real ongoing costs:

- Lists Cloud hosted sync.
- Hosted web access.
- Attachment/storage hosting.
- Cloud plugin runners.
- Cloud AI/API compute if not using the user's own key/provider.
- Managed self-hosting.
- Business support, admin tooling, deployment help, SLAs, and security/compliance
  documentation.

Do not call the paid thing "Pro." The app is not upgraded by paying. The hosting
is. Better names:

- Lists Cloud.
- Hosted Sync.
- Managed Lists.

Other money paths:

- Support development/sponsor button.
- Business self-host support.
- Managed private deployments.
- Consulting/integrations around the open-source product.
- Career/exposure value from building a widely used open-source app.

The commercial wedge is trust:

> You never pay to unlock your own productivity. You only pay if you want Saxon
> to run infrastructure for you.

---

## Marketing Direction

The product should not beg. It should show evidence.

The strongest technical-crowd visual, once real clients exist:

> iPhone + Android tablet + Framework/Linux laptop + Windows desktop, all showing
> the same data in native UI.

That shot says:

> Nobody is second-class here.

First-post framing:

> I got tired of every tasks/notes app being paid, ugly, closed, cloud-first, or
> Apple-only, so I am building the default one I wanted.

Possible one-liners:

- Free forever. Open source. Native everywhere. Your data stays yours.
- The private, open Reminders + Notes app Apple should have made for everyone.
- No account. No subscription. No lock-in. Real files.

Keep AI/agents/plugins as a reply or deeper page, not the headline. The headline
is the app, the trust model, and the device inclusiveness.

Do not fake shipped platforms. It is fine to say "I am building this" and show
the current reality. Technical users forgive ambition; they do not forgive bait.

---

## Honest Risks

The demand gap is real, but execution decides whether it matters.

Main risks:

- Making the first five minutes less clean than the pitch.
- Letting power-user depth clutter the normal UI.
- Cross-platform clients feeling like ports instead of native apps.
- Sync conflicts or reminder reliability breaking trust.
- Overpromising platform parity before clients exist.
- Adding AI/agent surfaces that make Lists look like the SaaS apps it is trying
  not to become.
- Shipping a file format that is technically open but practically hard to use
  outside the app.

The discipline:

- Keep the core loop excellent.
- Keep files real.
- Keep paid features tied to real costs.
- Keep every platform respected.
- Keep the marketing proof-based.

---

## Near-Term Focus

1. Make iOS undeniable: empty-inbox first launch, fast capture, clean rows,
   reliable reminders, excellent document view.
2. Lock the item/file/Markdown contract before other clients depend on it.
3. Finish Markdown interoperability: inline tags, wikilinks, checkboxes,
   code/tables/callouts, and external Markdown tolerance.
4. Build calendar and iCal import/export/sync around the existing event shape.
5. Finish the plugin boundary with habits as the first real plugin-style type.
6. Design the future `question`/agent-task workflow as item-native, not chat.
7. Prepare public positioning around free/open/private/native-everywhere without
   pretending deferred platforms are shipped.
8. After iOS is strong, make Android the first proof that nobody is second-class.
9. Build sync so free/user-owned routes work first, then hosted infrastructure can
   charge honestly for convenience and reliability.
