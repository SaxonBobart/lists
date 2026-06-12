# Android 17 Agentic Features — What Native Lists Should Adopt

Compiled 2026-05-30. Confidence: High (on what is real vs. future; one schema-related claim explicitly downgraded — see "What couldn't be confirmed").

---

## TL;DR for Saxon

- **"Android 17 agentic" is mostly the Android 16 agent stack, broadened — not brand-new magic.** Google itself says Android 17 "broadens" existing capabilities. The actual Android 17 platform changes are privacy and performance plumbing, not new agent APIs. So nothing here is locked to "Android 17"; it spans Android 16 → 17.
- **The genuinely useful, available-today piece is on-device AI** (Google's "ML Kit GenAI" / "Gemini Nano"). It can summarize a note, clean up messy captured text, and do voice-to-text — all **running locally on the phone, no cloud, no account, no per-use cost.** That matches the Lists privacy promise exactly.
- **The "say 'add milk to groceries' to Gemini and it lands in Lists" feature is real but not shippable yet.** The mechanism (called "AppFunctions") runs on-device, which is good — but the assistant-facing side is **invitation-only / private preview** as of May 2026. This is a 2026-roadmap item, not a today item.
- **Caveat that protects us:** on-device AI only exists on recent flagship phones (Pixel 9/10, Galaxy S25/S26 families). Cheaper/older Android phones don't have it. **Any AI feature must work gracefully when the phone can't do it** — i.e. the feature simply isn't offered, and nothing breaks.
- **Most of the flashy "agent" frameworks are early experiments or limited regional demos** (ADK 0.1.0, A2UI/Compose renderer, the "Gemini drives your app screen-by-screen" automation). Do **not** build core Lists features on these yet.
- **One specific thing the earlier research overstated:** there is *not* a confirmed official catalog of ready-made "CreateNote / CreateTask" templates we can drop into. The real, documented path is **we describe our own actions** (add task, log habit, etc.) and the assistant reads those descriptions. Slightly more work, same outcome.
- **Recommended posture:** adopt the local, private on-device AI now (in a way that degrades gracefully); *prepare* — but do not yet ship — the Gemini-assistant action hooks; ignore the rest. This keeps Lists private and avoids feature-box-filling bloat.

---

## 1. What "Android 17 Agentic" Actually Means

Google's framing (Feb 25 2026, "The Intelligent OS" post) is explicit: *"In Android 17, we're looking to broaden these capabilities to reach even more users, developers, and device manufacturers."* The word is **broaden**, not introduce.

The "17 Things to know" post (May 19 2026) confirms that the real Android 17 *platform* changes are privacy and performance, not agent APIs:

- Performance/system architecture: a "lock-free MessageQueue" and a garbage collector with "more frequent, less intensive young-generation collections."
- Privacy: "a new contact picker and eyedropper API help minimize the use of sensitive permissions," plus "background audio hardening and SMS OTP protection."
- Targeting Android 17 (= **API level 37**) requires "mandatory large-screen resizability, certificate transparency by default, and restricted local network access."

**Bottom line:** AppFunctions, Gemini Nano / Gemma 4, ML Kit GenAI, ADK, and the UI-automation framework are platform / Jetpack / Gemini-app features that span Android 16 → 17. **None is Android-17-gated.** This is good news — it means Lists doesn't need to chase a specific OS version to use the parts that matter.

---

## 2. Available Now — Build Against These Today

### 2.1 On-device AI: Gemini Nano + AICore (SHIPPING)

This is the foundation that fits Lists best. It is the system-level, on-device model. Access is layered: **AICore** (the OS system service) → **Google AI Edge SDK** → **ML Kit GenAI APIs** (the easy front door).

Google's privacy guarantees (page dated 2026-04-02) align directly with Lists' local-first ethos, verbatim:

- **Restricted Package Binding** — AICore is isolated from most packages.
- **Indirect Internet Access** — *"AICore does not have direct internet access. All internet requests, including model downloads, are routed through the open-source Private Compute Services companion APK."*
- **Per-Request Isolation & No Logging** — it *"doesn't store any record of the input data or the resulting outputs after processing."*
- **On-Device Processing** — it *"executes prompts locally, eliminating server calls."*

### 2.2 ML Kit GenAI APIs (SHIPPING — the easiest path for Lists)

This is the practical entry point. Built "on top of AICore" and "powered by Gemini Nano." Feature APIs available: **Prompt, Summarization, Proofreading, Rewriting, Image Description, Speech Recognition.**

Guarantees, verbatim:

- *"every app is able to use the shared Gemini Nano model that is on the device"* (we don't ship our own multi-GB model).
- *"Input, inference, and output data is processed locally."*
- Works *"without reliable internet connection."*
- *"No additional server cost incurred for each API call."*

**Device support (confirmed):** Pixel 10 / 10 Pro / Pro XL / Pro Fold, Pixel 9 / 9 Pro / Pro XL / Pro Fold; Galaxy S25 / S25+ / S25 Ultra, S26 / S26+ / S26 Ultra, Z Fold7, Z TriFold. **Older / cheaper phones without AICore won't have this** — graceful degradation is mandatory.

### 2.3 AppFunctions (EXPERIMENTAL PREVIEW — the assistant hook)

This is the mechanism that would let Gemini call into Lists ("add milk to groceries").

- Status, verbatim: *"AppFunctions is in an experimental preview as we refine the API surface, and is subject to change."*
- Minimum OS: *"AppFunctions is available on devices running Android 16 or higher."*
- Gemini side: *"As of May 2026, AppFunctions integration with Gemini is in a private preview with trusted testers."* → **A third-party app like Lists can build against the library now, but cannot ship a public, Gemini-discoverable integration today.**
- How it works (the part that fits us): it runs **on-device**. Google's comparison, verbatim: *"AppFunctions are built-in OS-level hooks exclusive to Android that execute locally. By contrast, a standard MCP server is a platform-agnostic solution that relies on cloud execution and network round-trips,"* and (Feb post) *"Much like WebMCP, it executes these functions locally on the device rather than on a server."*
- Already in scope per Google (Feb post): *"Through AppFunctions, Gemini can already automate tasks across app categories like Calendar, Notes, and Tasks, on devices from multiple manufacturers."*
- Confirmed API surface: annotations `@AppFunction(isDescribedByKDoc = true)` and `@AppFunctionSerializable(isDescribedByKDoc = true)`; classes `AppFunctionContext`, `AppFunctionManager`; method `AppFunctionManager.isAppFunctionEnabled(packageName, functionId)`; the permission `android.permission.EXECUTE_APP_FUNCTIONS` for cross-app callers; debug command `adb shell cmd app_function list-app-functions`.
- Worked examples in the docs are literally a note/task app: `listNotes(ctx)`, `createNote(ctx, title, content)`, `editNote(ctx, noteId, title?, content?)` returning a `@AppFunctionSerializable data class Note(id, title, content)`; plus `createTask(context, title, dueDateTime: LocalDateTime?, location: String?)`. **Important nuance:** these are *developer-authored custom functions*, not a drop-in standard schema library (see corrections in section 6).
- Jetpack library: latest **1.0.0-alpha09** (May 06 2026). Artifacts: `androidx.appfunctions:appfunctions`, `:appfunctions-service`, `:appfunctions-compiler`. The KDoc you write on each function becomes the agent-facing description.

### 2.4 App Actions / Built-in Intents (still active, legacy path)

The page (2026-02-26) has **no deprecation banner**. Requires the app published to Play Store + `androidx.core:core 1.6.0+`. It does **not** mention AppFunctions. This is the older voice-Assistant-era path; **AppFunctions is the strategic successor.** Not worth investing in for a new build.

---

## 3. Announced / Future / Preview — Do NOT Build Core Features On These

| Item | Status | Note for Lists |
|---|---|---|
| **A. Gemini ↔ AppFunctions integration** | Private preview / trusted testers (EAP) | The actual "talk to Gemini, it edits Lists" path. No public GA date. Can prototype, cannot ship publicly. |
| **B. Gemini Nano 4 / Gemma 4** | Developer preview | "over 140 languages," multimodal (text/images/audio), variants E4B (more reasoning) and E2B ("3x faster"); "up to 4x faster… up to 60% less battery." Code for Gemma 4 "will automatically work on Gemini Nano 4-enabled devices," available "later in 2026." Preview Prompt API adds "tool calling, structured output, system prompts, and thinking mode." |
| **C. ML Kit Prompt API → production + Structured Output API + Prefix Caching** | Prompt API going to production; Structured Output **upcoming**; prefix caching announced | **Structured Output** is the piece Lists would want for free-text → task/recurrence parsing (define an object class to be returned). It is **announced, not yet GA.** |
| **D. ADK for Android** | v0.1.0, experimental | "available for experimentation." Cloud-root-orchestrator + on-device-privacy-sub-agent pattern. Not a foundation yet. |
| **E. Firebase AI Logic orchestration modes** | Confirmed | Modes `PREFER_ON_DEVICE`, `PREFER_CLOUD`, `ONLY_ON_DEVICE`, `ONLY_CLOUD`. **`ONLY_ON_DEVICE` is the natural privacy-first default for Lists** if we ever route through Firebase AI Logic. |
| **F. AG-UI / A2UI + Compose Renderer** | Upcoming | "the upcoming Jetpack Compose Renderer… render these A2UI messages as native UI." Not shipped. |
| **G. UI automation framework ("Gemini drives your app")** | Early preview, narrow | Verbatim: "Starting with an early preview on the Galaxy S26 series and select Pixel 10 devices… a curated selection of apps in the food delivery, grocery, and rideshare categories in the US and Korea to start." **Lists is out of scope; ignore.** |
| **H. Android CLI stable, Migration Assistant, AI Studio app-from-prompt, Gemma 4 on Android Bench** | Announced | The Migration Assistant "weeks → hours" (iOS → Android) claim is vendor marketing — **treat skeptically.** |

---

## 4. Decision Table — Genuine Fit vs. Feature-Box-Filling (Skip)

Opinionated, biased toward protecting Lists' local-first/private promise and avoiding bloat.

| Agentic capability | Genuine fit for Lists (why) | Feature-box-filling — skip (why) |
|---|---|---|
| **On-device note summarization** (ML Kit GenAI Summarization) | **ADOPT.** Real user job: long note → quick gist. Runs locally, no cloud, no cost, no account. Pure local-first fit. | — |
| **Voice / speech → task or habit** (ML Kit Speech Recognition + Prompt) | **ADOPT (near-term).** Real job: "add a task by voice" / "log my habit" hands-free. On-device. Highest-value capture improvement. | — |
| **Clean up captured text** (Proofreading / Rewriting) | **ADOPT (optional, low-risk).** Real job: tidy a messy quick-capture. Local. Keep it opt-in and unobtrusive. | — |
| **Free-text → structured task/recurrence** ("remind me every 2nd Tue") via **Structured Output API** | **PREPARE, don't ship.** Genuinely useful for parsing natural dates/recurrence locally — but the API is **upcoming/not GA.** Design for it; wait to ship. | Skip building on the preview Prompt API's ad-hoc structured output as a core dependency until GA — too unstable to anchor a shipping feature. |
| **Gemini-callable actions** (AppFunctions: add item, create reminder, complete task, log habit) | **PREPARE the surface, don't ship publicly.** This is the marquee "add milk to groceries" win and runs on-device. We can author the `@AppFunction` declarations now. | But the Gemini side is **private-preview only** — do not promise or market it. Wait for public GA, and confirm the no-account question first (see gaps). |
| **Image Description** (ML Kit GenAI) | Niche — only if Lists ever attaches photos. | **SKIP for now.** No current user job in a notes/tasks/habits app. Pure box-filling. |
| **ADK on-device/cloud agent orchestration** | — | **SKIP.** v0.1.0 experimental. Adds a heavy "agent framework" where Lists needs simple, local features. Bloat + instability. |
| **A2UI / Compose Renderer (agent-generated UI)** | — | **SKIP.** Upcoming, unshipped. Lists' value is its own crafted UI, not server/agent-rendered screens. |
| **UI automation framework ("Gemini operates the app")** | — | **SKIP / actively avoid.** Out of scope (regional, 3 categories). Opt-out and permission model **undocumented** — a privacy-sensitive unknown for a private app. Watch, don't touch. |
| **Cloud routing of any AI** (`PREFER_CLOUD` / `ONLY_CLOUD`) | — | **SKIP.** Directly violates the local-first/private promise. If Firebase AI Logic is ever used, pin `ONLY_ON_DEVICE`. |
| **App Actions / Built-in Intents (legacy)** | — | **SKIP.** Legacy path, superseded by AppFunctions. No reason to invest in a new build. |

---

## 5. Recommendations for Lists

**Recommended minimal native-Android agentic surface — concrete and opinionated:**

1. **Ship on-device AI as opt-in "smart helpers," gated on capability.**
   - Use **ML Kit GenAI Summarization** for "summarize this note" and **Speech Recognition + Prompt** for "add by voice."
   - Hard rule: **detect AICore/Gemini Nano availability at runtime; if absent, the feature simply doesn't appear.** No spinner, no error, no degraded cloud fallback. On unsupported phones Lists behaves exactly as today.
   - **Never route to cloud.** If we ever touch Firebase AI Logic, set `ONLY_ON_DEVICE`. This is non-negotiable for the privacy promise.

2. **Author the AppFunctions surface now, but don't market or rely on it.**
   - Write **custom `@AppFunction` declarations** for the core jobs: add item, create reminder, complete task, **log habit** (habit logging will need a custom function regardless — there is no evidenced standard schema for it).
   - Treat this as forward-investment that becomes live when Google opens the Gemini integration to the public. **Do not put "works with Gemini" on any roadmap promise to users until GA.**

3. **Design for the Structured Output API, ship with a simple parser.**
   - The natural-language → recurrence/date parsing is a real Lists win, but the clean on-device API is **upcoming.** Ship our own lightweight local parser now; swap in Structured Output when it's GA. Don't block on Google.

4. **Explicitly decline the heavy agent stack.** No ADK, no A2UI, no UI-automation integration. They are experimental, unshipped, or privacy-ambiguous, and none serves a real Lists user job today. Saying no here is what keeps the app un-bloated and trustworthy.

5. **Set a review trigger, not a build trigger.** Re-check two things each quarter: (a) has AppFunctions-with-Gemini hit public GA, and (b) is Structured Output API GA. Those two events — not the OS version number — are when Lists should ship the assistant-facing features.

**One-line posture:** Adopt the private, local, free on-device AI now (degrading gracefully); pre-wire the Gemini action hooks but don't ship or promise them; ignore everything experimental. Lists stays private, useful, and free of agent-bloat.

---

## 6. Sources

- [official] **Overview of AppFunctions | AI | Android Developers** — https://developer.android.com/ai/appfunctions — 2026-05-21 — **high confidence**
- [official] **Add the AppFunctions API to your app | AI | Android Developers** — https://developer.android.com/ai/appfunctions/add-appfunctions — 2026-05-12 — **high confidence**
- [official] **appfunctions | Jetpack | Android Developers (release notes)** — https://developer.android.com/jetpack/androidx/releases/appfunctions — 2026-05-06 — **high confidence**
- [official] **The Intelligent OS: Making AI agents more helpful for Android apps** — https://android-developers.googleblog.com/2026/02/the-intelligent-os-making-ai-agents.html — 2026-02-25 — **high confidence**
- [official] **Top AI on Android updates… from Google I/O '26** — https://android-developers.googleblog.com/2026/05/android-ai-intelligence-system.html — 2026-05-26 — **high confidence**
- [official] **17 Things to know for Android developers at Google I/O** — https://android-developers.googleblog.com/2026/05/17-things-android-developers-google-io.html — 2026-05-19 — **high confidence**
- [official] **Gemini Nano | AI | Android Developers** — https://developer.android.com/ai/gemini-nano — 2026-04-02 — **high confidence**
- [official] **Announcing Gemma 4 in the AICore Developer Preview** — https://android-developers.googleblog.com/2026/04/AI-Core-Developer-Preview.html — 2026-04-02 — **high confidence**
- [official] **Overview of the ML Kit GenAI APIs** — https://developers.google.com/ml-kit/genai — 2026 (current) — **high confidence**
- [official] **Build ADK agents for Android | AI | Android Developers** — https://developer.android.com/ai/adk — 2026-05-21 — **high confidence**
- [official] **Build App Actions | Assistant | Android Developers** — https://developer.android.com/develop/devices/assistant/get-started — 2026-02-26 — **high confidence**
- [secondary] **Google details 'AppFunctions' that let Gemini use Android apps (9to5Google)** — https://9to5google.com/2026/02/25/android-appfunctions-gemini/ — 2026-02-25 — **medium confidence**

**Corrections applied to earlier (scout) research, for transparency:**

- **Overstated → downgraded to UNVERIFIED:** the claim of a predefined "CreateNote" / "CreateTask" *standard schema* catalog (`AppFunctionSchemaDefinition`) and the quote *"An app function that implements the CreateNote schema can be identified and invoked by an assistant app."* This could **not** be confirmed in Google's primary docs — it traced to third-party/AI-generated summaries. The documented path is **custom `@AppFunction` declarations** whose KDoc becomes the agent-facing schema. The `createTask`/`createNote`/`listNotes` examples are real, but as developer-authored functions, not a standard schema library.
- **Minor:** the exact MCP-comparison quote was loosely reconstructed by the scout; substance correct, wording corrected above.
- **Minor (unconfirmed):** the claim that `AppFunctionManagerCompat` supports "Android U (API 34)+." Docs consistently say **Android 16+**. Treat the API-34 backport claim as unconfirmed.
- **Minor (sourcing):** the `gemini-nano` doc itself (2026-04-02) does **not** list devices or "Gemini Nano 4"; those specifics live in the Apr 2 AICore preview blog and the May 26 I/O recap.

---

## 7. What Couldn't Be Confirmed (Honest Gaps)

- **Predefined AppFunction standard-schema catalog** (CreateNote / CreateTask / Reminder — and especially any **habit / log-completion** schema) is **not documented** in the primary Google docs checked. A habit-logging standard schema is evidenced nowhere; Lists would almost certainly need **custom `@AppFunction`** declarations regardless. Do not anchor any plan on a standard schema library existing.
- **No public GA date for AppFunctions-with-Gemini.** Still private preview / trusted testers as of May 2026. When a third-party app can ship a live, Gemini-discoverable integration is **unknown.**
- **Whether on-device AppFunctions invocation requires a Google account / Play Services beyond AICore is not stated.** This is **material to Lists' no-account stance** and is unconfirmed. Must be answered before committing to the assistant surface.
- **Android 17 final stable release date not pinned** (I/O '26 surfaced QPR1 betas; API level confirmed as **37**). No agent-specific platform API is Android-17-gated — confirmed as "broadening," not new-API.
- **Gemini Nano 4 production rollout** = "flagship devices later in 2026," **no exact device/min-spec list.** The fallback for mid/low-end phones without AICore is the "AI Edge Gallery app" — **for testing only** ("not representative of final production performance"). A documented graceful-degradation path for *shipping* apps on non-AICore devices is **not spelled out** (so Lists must define its own: hide the feature).
- **ADK for Android (0.1.0) and A2UI production-readiness timeline unknown** — explicitly "for experimentation" / "upcoming." Not advisable to build core Lists features on them.
- **UI automation framework opt-out / permission model** for an app that did **not** implement AppFunctions is **not documented.** Current preview is limited (food delivery / grocery / rideshare, US + Korea, Galaxy S26 / select Pixel 10), so Lists is out of scope today — but whether such an agent could later act on Lists data without explicit AppFunctions exposure, and whether a developer can opt out, is **unconfirmed and privacy-sensitive.** Watch this one closely.
