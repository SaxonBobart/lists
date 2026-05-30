# Monetization & Business Model — Research

## Bottom line (3–5 sentences, plain English, for a non-technical product owner)
**"Free local, paid Sync" is the right model for Lists** — it fits the privacy/local-first ethos exactly and there's a natural value moment (your notes on every device). The strongest proof is Obsidian: free, unlimited local app, paid Sync at $4–5/month, ~$25M annual recurring revenue with no investors and a tiny team — built on the same "you own your files, sync is the optional service" promise Lists already makes. The key nuance from 2026 buyer behaviour: people resent subscriptions for *static, one-time* value but accept them when there's a real *ongoing cost* — and a cloud sync server is a legitimate ongoing cost, so a Sync subscription reads as fair. My concrete recommendation is a **hybrid**: the local app stays free forever, **Lists Sync is a low-priced subscription** (~$2–3/mo or ~$20/yr) with an optional **lifetime "pay once" Sync unlock** (~$40–60) to satisfy the buy-once crowd. **But do not charge a cent until two things are true: the data-loss bug is fixed (audit finding DI-1) and sync actually works** — charging for sync while a single corrupt file can wipe access to the whole library would be a trust-destroying betrayal of the exact promise you're selling.

## What the landscape / best practice looks like (May 2026)

### Three live pricing models among comparable apps

**1. One-time purchase (buy once, own forever)**
- **Things 3** — per-platform one-time: **$9.99 iPhone, $19.99 iPad, $49.99 Mac** (~$80 for the full suite). Watch included with iPhone. **Sync (Things Cloud) is free.** ([Cultured Code](https://culturedcode.com/things/pricing/), [Ellie Planner](https://ellieplanner.com/productivity-copilot/things-3-pricing))
- **Streaks** (habit tracker, direct comparable to Lists' habit feature) — **$5.99 one-time**, no subscription, all future updates included. Apple Design Award winner. ([66 Streaks](https://66streaks.com/blog/is-streaks-app-free/), [App Store](https://apps.apple.com/us/app/streaks/id963034692))
- **iA Writer** — **$29.99 one-time per platform** (Mac/iOS/Windows bought separately). ([Unmarkdown comparison](https://unmarkdown.com/blog/bear-vs-ia-writer-vs-ulysses))

**2. Sync-as-the-paywall / freemium-local (the model Lists is considering)**
- **Obsidian** — the flagship example. **Core app free, unlimited, no sign-up, no telemetry, local data unrestricted.** Paid optional services: **Sync $4/mo annual ($48/yr) or $5/mo monthly** (E2E-encrypted, version history, shared vaults); **Publish $8/mo annual ($10 monthly)**; **Commercial license $50/user/yr**; a one-time **Catalyst $25** for early access. ([Obsidian pricing](https://obsidian.md/pricing))
  - Earlier "Standard" Sync tier marketing referenced $4/mo for 1 vault / 1 GB; the current page shows a single $4–5/mo Sync line. ([Obsidian on X, 2024](https://x.com/obsdmd/status/1770493867806298438))
  - **Why it matters:** Obsidian is reportedly **~$350M valuation, ~$25M ARR, ~3 engineers, no venture capital** as of early 2026 — proof the model is sustainable for a small, focused, privacy-aligned team. ([VersaEdits](https://www.versaedits.com/article/obsidian-built-350m-app-3-engineers), [Robin Landy pricing analysis](https://www.robinlandy.com/blog/obsidian-as-an-example-of-thoughtful-pricing-strategy-and-the-power-of-product-tradeoffs))

**3. Subscription (recurring, all features gated)**
- **Bear** — **$2.99/mo or $29.99/yr** (Bear Pro); one subscription covers all devices on the same Apple ID; sync is the headline paid feature. ([Bear FAQ](https://bear.app/faq/features-and-price-of-bear-pro/))
- **Todoist** — Pro **$5/mo annual ($60/yr) or $7/mo monthly**; raised from $4 in Dec 2025; free tier capped at 5 projects. ([Morgen](https://www.morgen.so/blog-posts/todoist-pricing), [alfred_](https://get-alfred.ai/blog/todoist-pricing))
- **TickTick** — Premium **$35.99/yr (~$3/mo)**; includes calendar + habit tracker. ~40% cheaper than Todoist annually. ([CompareTiers](https://comparetiers.com/tools/ticktick))
- **NotePlan** — subscription-only (no lifetime); Personal around **$1.33–1.99/mo annual** depending on source; 7-day trial, no free tier. ([NotePlan pricing](https://noteplan.co/pricing))

### App Store economics in 2026
- **Apple Small Business Program: 15% commission** (vs 30%) for developers under **$1M/yr in proceeds** — Lists qualifies automatically as a new/small developer. Must enroll; rate begins ~15 days after approval. ([Apple Developer](https://developer.apple.com/app-store/small-business-program/), [RevenueCat](https://www.revenuecat.com/blog/engineering/small-business-program/)) So on a $20/yr sync sub, Apple takes ~$3, you keep ~$17.
- **Subscription fatigue is real and measurable: ~41% of consumers report it**; average person spends $200+/mo on subscriptions and underestimates the total. One-time/lifetime plan share grew from **6.4% → 10.3% (2023→2025)**; consumers actively search for "buy once" alternatives. ([influencers-time](https://www.influencers-time.com/subscription-fatigue-why-one-time-purchases-are-rising/), [adapty](https://adapty.io/blog/9-subscription-trends-dominating-2025/))
- **The decisive distinction** (multiple sources agree): buyers **reject subscriptions for static, single-purpose utilities** ("I bought it, why am I still paying?") but **accept them when there's genuine ongoing cost or value — cloud services, sync, compute, support.** ([Stripe-adjacent guide](https://www.influencers-time.com/subscription-fatigue-rising-why-one-time-purchases-rebound/), [subscription economics summary](https://www.influencers-time.com/tackling-subscription-fatigue-in-2025-new-pricing-models/)) **A sync server is squarely in the "legitimate ongoing cost" bucket** — which is exactly why sync-as-paywall sidesteps the fatigue backlash.
- **Freemium conversion is low: typically 2–5%**, exceptional self-serve products 6–8%. ([Meegle](https://www.meegle.com/en_us/topics/monetization-models/freemium-conversion-rates), [daydream](https://www.withdaydream.com/library/insights/freemium-conversion-rate)) The free local app must therefore be the *acquisition engine*, not a loss — it's free to run (no server) so a low conversion rate is fine.
- **Indie consensus** (Indie Hackers, HN): one-time/credit models "feel fairer — buy it, own it," convert faster, and suit privacy-first audiences (no account needed); subscriptions win on predictable cash flow *if* retention holds, but churn is "the silent killer." No universal answer — match the model to *when value is delivered*. ([Indie Hackers honest take](https://www.indiehackers.com/post/subscriptions-vs-one-time-payments-a-developers-honest-take-f153e48960))

## Implications for Lists ← the most important section

**1. Yes — adopt "free local, paid Sync." It is the model that matches the product.** Lists already makes Obsidian's exact promises: files are the source of truth, plain-text Markdown + YAML, no telemetry, no account, no cloud dependency for local use. The free local app costs you nothing to operate (it's on the user's device), so giving it away unlimited is both ethically on-brand and commercially smart: it's a zero-marginal-cost top of funnel. Sync is the one feature that *does* cost you (servers, bandwidth, E2E infra) and delivers continuous value across devices — the textbook justification for a recurring fee that won't trigger subscription-fatigue resentment.

**2. Recommended pricing shape — a hybrid, undercutting Bear/Obsidian:**
   - **Free, forever:** the entire local app — tasks, habits, notes, the one-`Item` model, smart lists, tags, the Markdown editor, local export ("you own your data"). No feature crippling. This *is* the privacy promise and the marketing.
   - **Lists Sync (paid):** multi-device end-to-end-encrypted sync. Price it **below the productivity-app pack**: ~**$2–3/mo or ~$19–24/yr** (Bear is $2.99/$29.99; TickTick $35.99/yr; Obsidian $48/yr — a calm single-purpose indie app should sit at or under the cheap end). Lead with the annual price.
   - **Lifetime Sync unlock (optional, important):** a one-time **~$40–60 "pay once, sync forever"** option. This directly answers the 41%-fatigued, "buy once" crowd (the rebound trend), captures users who'll never subscribe, and gives you lump-sum cash now. Streaks ($5.99) and Things (per-platform one-time) show this audience exists and pays. Set lifetime ≈ 2–3 years of the subscription so it's a fair trade for both sides.
   - **iOS-26-only caveat:** with a tiny installable audience near-term (audit STRAT-1), keep prices simple and don't over-engineer tiers. One sub + one lifetime is enough until volume justifies more (storage tiers, Publish-style add-ons later, à la Obsidian).

**3. What stays free vs paid — keep the line clean:** Free = everything that runs on-device. Paid = only what needs a server (sync, and any future cloud-backup/web-publish). Resist the temptation to paywall local features (e.g. unlimited lists, habits, themes) — that breaks the "the free app is genuinely yours" trust that makes this model work, and it's what users hate about Todoist's 5-project free cap.

**4. DO NOT CHARGE until two preconditions are met — this is the critical risk, tie directly to the audit:**
   - **(a) The data-loss P0 must be fixed first.** Audit finding **DI-1** (`Core/Storage/FileStore.swift` — one corrupt or half-written `.md`/`.list.yml` throws out of `loadAll`, wedging the app permanently on "Loading your lists…" with the whole library invisible, surfaced only by a console `print`). You cannot sell "your data is safe and yours" while a single bad file silently locks the user out of everything. Worse, **sync is exactly the mechanism that introduces partially-written/conflicting files** (the audit's DI-3 malformed-`deleted_at` un-delete and DI-4 out-of-order writes get *more* likely once two devices write). Shipping paid sync on top of a non-resilient read path would convert a private bug into a paying-customer data-loss event — the worst possible reputational outcome for a privacy-first app. **Fix the per-file quarantine/resilience first.**
   - **(b) Sync must actually work and be trustworthy.** Today sync is deferred — only tombstones exist as groundwork. You can't charge for a feature that isn't built; and because it's the *paid* feature, its reliability bar is higher than anything else. Beta it free, prove reconciliation is correct (especially conflict + delete cases), *then* turn on billing.
   - **Sequencing:** Free local app (now, post-DI-1 fix) → build + free-beta Lists Sync → enroll in Apple's 15% Small Business Program → introduce the Sync subscription + lifetime unlock once sync is proven. The free app can ship and build an audience *before* any monetization exists, which is the correct order anyway.

**5. Enroll in the Small Business Program day one** — 15% not 30% on every sale, automatic for a developer under $1M. On a $20/yr sub you keep ~$17. ([Apple](https://developer.apple.com/app-store/small-business-program/))

## Open questions / things to validate
- **Sync infrastructure cost per user** — needed to confirm $2–3/mo covers E2E-encrypted sync + storage + bandwidth at small scale and still nets margin. (Coordinate with the R2 sync research / R3 storage-format findings.)
- **Lifetime-unlock math** — what fraction choose lifetime vs subscription, and does the lump sum cover *future* server cost for those users forever? (Risk: lifetime buyers cost you sync compute indefinitely. Mitigate by pricing lifetime at 2–3 yrs of sub, and/or capping lifetime to a fair-use storage tier.)
- **iOS 26-only audience size** (audit STRAT-1) — directly bounds near-term revenue; monetization can't outrun installable-device count. Validate with the R9/ASO research before assuming any revenue.
- **Regional pricing** — Apple supports per-territory price tiers; a calm indie app may want lower prices outside the US. Not urgent pre-launch.
- **Does Lists want a "Publish"-style add-on later?** (Obsidian's $8–10/mo Publish is a meaningful second revenue line.) Likely premature; note as a future option, not v1.

## Sources
- [Obsidian — Pricing](https://obsidian.md/pricing)
- [Obsidian on X — Sync Standard plan ($4/mo, 1 GB)](https://x.com/obsdmd/status/1770493867806298438)
- [VersaEdits — How Obsidian Built a $350M App With 3 Engineers](https://www.versaedits.com/article/obsidian-built-350m-app-3-engineers)
- [Robin Landy — Obsidian as thoughtful pricing strategy](https://www.robinlandy.com/blog/obsidian-as-an-example-of-thoughtful-pricing-strategy-and-the-power-of-product-tradeoffs)
- [Cultured Code — Things pricing](https://culturedcode.com/things/pricing/)
- [Ellie Planner — Things 3 pricing detail](https://ellieplanner.com/productivity-copilot/things-3-pricing)
- [66 Streaks — Is Streaks free? ($5.99 one-time)](https://66streaks.com/blog/is-streaks-app-free/)
- [Streaks — App Store listing](https://apps.apple.com/us/app/streaks/id963034692)
- [Bear — Features and price of Bear Pro](https://bear.app/faq/features-and-price-of-bear-pro/)
- [Unmarkdown — Bear vs iA Writer vs Ulysses (iA Writer $29.99 one-time)](https://unmarkdown.com/blog/bear-vs-ia-writer-vs-ulysses)
- [Todoist pricing — Morgen](https://www.morgen.so/blog-posts/todoist-pricing) / [alfred_ (Dec 2025 price rise)](https://get-alfred.ai/blog/todoist-pricing)
- [TickTick pricing — CompareTiers](https://comparetiers.com/tools/ticktick)
- [NotePlan — Pricing](https://noteplan.co/pricing)
- [Apple Developer — App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [RevenueCat — The 15% App Store Fee guide (2026)](https://www.revenuecat.com/blog/engineering/small-business-program/)
- [influencers-time — Subscription fatigue & one-time purchase rise (2026)](https://www.influencers-time.com/subscription-fatigue-why-one-time-purchases-are-rising/)
- [influencers-time — One-time purchase rebound / static-vs-ongoing value](https://www.influencers-time.com/subscription-fatigue-rising-why-one-time-purchases-rebound/)
- [influencers-time — Tackling subscription fatigue, new pricing models](https://www.influencers-time.com/tackling-subscription-fatigue-in-2025-new-pricing-models/)
- [adapty — Subscription economy trends & fatigue stats 2026](https://adapty.io/blog/9-subscription-trends-dominating-2025/)
- [Meegle — Freemium conversion rates](https://www.meegle.com/en_us/topics/monetization-models/freemium-conversion-rates)
- [daydream — Freemium conversion rate benchmarks](https://www.withdaydream.com/library/insights/freemium-conversion-rate)
- [Indie Hackers — Subscriptions vs one-time payments: a developer's honest take](https://www.indiehackers.com/post/subscriptions-vs-one-time-payments-a-developers-honest-take-f153e48960)
- Internal: `audit/findings/data-integrity.md` (DI-1 corrupt-file load failure; DI-3 malformed `deleted_at`; DI-4 out-of-order writes) and `audit/_PROGRESS.md` (STRAT-1 iOS 26 audience).
