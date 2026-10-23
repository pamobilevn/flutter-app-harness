---
name: app-harness-research
description: Phase 1 — discover mobile app concepts from store category charts, competitor reviews (1–3★ = unmet needs) and trend signals, propose 2-3 options, query the user (or auto-select), run the App Store 4.2 + 4.3 review check, and record the chosen concept.
argument-hint: ""
allowed-tools: [Agent, Read, Write, Edit, WebFetch, WebSearch, AskUserQuestion, Bash]
---

# app-harness-research

> **Plugin paths.** `docs/harness-protocol.md`, `docs/app-gotchas.md`, and `templates/` are files of this
> plugin, not of the app: read them at `${CLAUDE_PLUGIN_ROOT}/<path>` (fallback: this skill's base
> directory + `/../../<path>`). `docs/harness/` (config, state, specs, plans, logs) is the app's run
> state in the working directory.

Phase 1 of the flutter-app-harness pipeline. Reads the user's raw idea from `config.md`, performs
market research if needed, proposes 2-3 concrete app concepts, queries the user via AskUserQuestion
to pick one, checks it against App Store guidelines **4.3 (Spam / copycats)** and **4.2 (Minimum
Functionality)**, then writes the research spec and advances the pipeline state.

All file schemas (`config.md`, `state.md`, `pipeline-log.md`) are defined in
`docs/harness-protocol.md` — refer to that document as the single source of truth. Do not redefine
schemas here. The rejection patterns behind the review check live in `docs/app-gotchas.md`
(*Store rejections*) — cite, do not restate.

**Language:** every message shown to the user (AskUserQuestion prompts, confirmations, the
auto-select line) is written in `default_language`. The English wording below is the reference text.

---

## Input

Read `docs/harness/config.md` and extract:

- `app_idea` — the raw one-line app idea supplied by the user (may be blank if the user invoked
  the harness without an idea, in which case you will generate ideas from scratch in the Discovery
  step). When `app_idea` is blank, the Discovery and "Propose & query" steps run exactly as normal
  but driven purely by market research and reasoning with no seed concept; the resulting proposals
  are presented via AskUserQuestion for the user to pick — the AI does not select automatically
  **unless `auto_idea: true`**, in which case the "Propose & query" step auto-scores and selects the
  best concept with no user prompt (see that section).
- `skip_research` — boolean. If `true`, treat `app_idea` as the chosen concept verbatim and
  **skip the Discovery and "Propose & query" steps entirely**: fill every proposal field (see the
  table under "Propose & query") from `app_idea` by reasoning alone — no chart or review fetching —
  then jump directly to the App Store review check (which still searches for similar apps), then
  Output. Even when skipping discovery you must still write the research spec.
- `auto_idea` — boolean (default `false`). When `true`, the "Propose & query" step and the App Store
  review check auto-decide instead of calling AskUserQuestion: the skill scores its own generated
  concepts, selects the best, and auto-revises a concept that fails 4.2 or 4.3 — running fully
  hands-off with no user input. Has no effect on selection when `skip_research: true` (the idea is
  already taken verbatim — nothing to select).
- `default_language` — language for every user-facing message.

If `config.md` does not exist, abort with:
`app-harness-research: docs/harness/config.md not found — run the orchestrator to bootstrap first.`

---

## Discovery

> Skip this section when `skip_research: true`.

Goal: ground the proposals in real store data — what ranks in each category, what users of the
leading apps complain about, and where demand is moving.

### 1. Category charts

Pick the categories to scan:
- `app_idea` given → the 1-2 store categories it belongs to.
- `app_idea` blank → 3-4 categories from: Productivity, Utilities, Health & Fitness, Finance,
  Education, Lifestyle (add Food & Drink, Travel, Photo & Video, Reference when the reasoning
  points there).

For each category, fetch the current top-free and top-grossing lists:

- **App Store (preferred, structured JSON)** — WebFetch the iTunes RSS feed with the category's
  genre id:
  `https://itunes.apple.com/us/rss/topfreeapplications/limit=50/genre=<id>/json` and
  `https://itunes.apple.com/us/rss/topgrossingapplications/limit=50/genre=<id>/json`.
  Genre ids: Productivity `6007`, Utilities `6002`, Health & Fitness `6013`, Finance `6015`,
  Education `6017`, Lifestyle `6012`, Food & Drink `6023`, Travel `6003`, Photo & Video `6008`,
  Reference `6006`. Fallback: `https://apps.apple.com/us/charts/iphone/<category>-apps/<id>`.
- **Google Play** — WebFetch `https://play.google.com/store/apps/category/<PLAY_CATEGORY>?hl=en`
  (e.g. `PRODUCTIVITY`, `TOOLS`, `HEALTH_AND_FITNESS`, `FINANCE`, `EDUCATION`, `LIFESTYLE`). The
  page is partly client-rendered; when it yields too few titles, fall back to WebSearch.
- **WebSearch** (fallback and cross-check):
  - `top <category> apps 2026 site:appfigures.com OR site:sensortower.com OR site:appmagic.rocks`
  - `best <category> apps 2026 iPhone Android`

For each category extract at least 10 titles and their **sub-niche** (habit tracker, budget
planner, unit converter, flashcards, meal planner, …). Note which sub-niches repeat across both
stores — that is demand.

### 2. Competitor mapping + review mining

For the sub-niche most aligned with `app_idea` (if provided), or the top 2 sub-niches by chart
frequency, pick **3-5 representative competitors**:

1. **Store data** — WebFetch the iTunes Search API:
   `https://itunes.apple.com/search?term=<url-encoded niche>&entity=software&country=us&limit=10`.
   Record `trackId`, `trackName`, `averageUserRating`, `userRatingCount`, `price`,
   `primaryGenreName`, and skim `description` for the feature list. For Play, WebFetch
   `https://play.google.com/store/apps/details?id=<package>&hl=en` (rating, installs tier).
2. **Review mining (1–3★ = unmet needs)** — WebFetch
   `https://itunes.apple.com/us/rss/customerreviews/page=1/id=<trackId>/sortby=mostrecent/json`
   (pages 1-3). Keep only entries whose `im:rating` is 1, 2 or 3; read 20-50 per competitor. The
   Play details page shows a few recent reviews — include its low-star ones.
3. **Cluster the complaints** into recurring unmet needs and count them, e.g. "basic export locked
   behind a subscription (14)", "ads after every action (9)", "data lost after update (6)",
   "requires an account for a local feature (5)", "no offline mode (4)". The top 3-5 clusters are
   the raw material for differentiators.

Record per competitor: title, rating + ratings count, primary flows, strength, top complaints.

Delegate steps 1–2 (protocol §8): one `general-purpose` agent with `model: haiku` per competitor,
all in parallel, each returning the store data above plus its low-star complaints as counts with
short verbatim quotes (≤ 15 words). Do step 3 yourself across all of them, and re-fetch one URL per
agent to check its numbers before they enter the spec.

### 3. Trend signals

WebSearch `<category> app trends 2026`, `mobile app category growth 2026`, and
`<sub-niche> app downloads 2026`. Extract 2-3 specific, sourced signals (e.g. "privacy-first,
offline finance trackers gaining share", "on-device AI features in productivity apps") to inform
the proposals.

---

## Propose & query

Synthesise your Discovery findings (and `app_idea` if provided) into exactly **2-3 concrete app
concept proposals**. Each proposal must include:

| Field | Description |
|---|---|
| Title | Working title (≤ 30 characters — the store name limit on both stores) |
| Tagline | One sentence (≤ 15 words) stating the value to the user |
| Target user & job-to-be-done | Who, and the JTBD: "When <situation>, I want to <motivation>, so I can <outcome>." |
| Primary user flows | 2-4 flows, each one line: trigger → steps → result that is saved |
| Differentiator | What it does that the mapped competitors don't — ideally answering a mined 1–3★ complaint |
| Why native Flutter | Why this belongs on the device: offline use, local persistence, device features (camera, sensors, haptics, local files) |
| Monetisation hook | Which AdMob formats fit naturally (banner / native / interstitial / app-open / rewarded, and where) and the IAP potential (remove ads, pro unlock, subscription) |
| Suggested store category | App Store category + Google Play category (plan finalises the ids) |

Present the proposals in a numbered list that is easy to read.

Then branch on `auto_idea`:

### If `auto_idea: false` (default) — ask the user

Use **AskUserQuestion** to ask the user to pick one or refine:

```
Which concept would you like to build?
Reply with the number (1, 2, or 3), or describe a variation.
If you are happy with one as-is, just type its number.
```

Wait for the user's response. If the user types a number, set the chosen concept to that proposal.
If the user describes a variation, merge their input with the closest base proposal and confirm
the merged concept with a follow-up AskUserQuestion before proceeding:

```
Got it. I'll build: <merged concept summary>.
Is this correct? (yes / describe further)
```

Repeat until the user confirms.

### If `auto_idea: true` — auto-score and select (no user input)

Do **not** call AskUserQuestion. Score each of the 2-3 proposals against these weighted criteria
and present a short scoring table:

| Criterion | Weight |
|---|---|
| Market fit (chart demand, review volume, trend signals) | 30% |
| Differentiation / 4.3 safety | 25% |
| 4.2 depth (meaningful native flows with persistence) | 15% |
| Monetisation fit (natural ad placements, IAP potential) | 15% |
| MVP feasibility (local-first, buildable in one pipeline run) | 15% |

Score each criterion 0–10, multiply by its weight, and sum to a weighted total per proposal. Render
the table (one row per proposal, one column per criterion, plus a Total column), then **select the
proposal with the highest total** as the chosen concept. Print the choice and a one-line rationale,
e.g. `Auto-selected: <title> (total 8.4/10) — strongest market fit, fixes the top competitor complaint.`
Then proceed to the App Store review check. Do not query the user.

---

## App Store review check (4.2 + 4.3)

Two App Review guidelines reject the most new utility apps (see `docs/app-gotchas.md`, *Store
rejections*). Before writing the spec, the chosen concept must pass **both** checks.

### 4.3 — Spam / copycats

1. Extract the job-to-be-done and the primary user flows from the chosen concept.
2. Find the 3 most similar existing apps: the iTunes Search API
   (`https://itunes.apple.com/search?term=<JTBD keywords>&entity=software&country=us&limit=10`)
   and WebSearch `"<JTBD keywords>" app App Store OR Google Play 2026`.
3. For each similar app, note: title, primary flows, distinctive features.
4. Apply the copycat test: a concept is a **copycat** if it shares the same job-to-be-done AND the
   same primary flows AND offers no distinctive feature. Saturated niches (flashlight, calculator,
   QR scanner, generic to-do list, unit converter, wallpapers, soundboard, horoscope, plain timer)
   need an especially concrete distinctive feature. A concept is **safe** if it has at least one of:
   - A workflow or feature absent from all top-3 matches, named concretely
   - A specific underserved audience with flows tailored to it (not just a reskin)
   - A direct fix for a recurring 1–3★ complaint found in review mining
   - A device capability used meaningfully that the matches lack (fully offline, on-device
     processing of camera/sensor/local-file input)

### 4.2 — Minimum Functionality

A concept **passes** when it offers **at least 2 meaningful native flows with persistence**:
- each flow lets the user create, change, or produce something that is saved on the device and is
  still there after an app restart;
- the flows work without a website — the app is not a WebView/website wrapper, a link collection,
  or static content that could be a web page or an e-book;
- it is more than a single static screen, and network-backed content (if any) stays useful offline
  (cached).

### Resolve failures

If the concept fails 4.3 or 4.2, do not proceed. Branch on `auto_idea`:

**If `auto_idea: false` (default)** — use AskUserQuestion to ask:
```
The chosen concept may be rejected by App Review:
- 4.3 (copycat): too similar to <similar app> — <what overlaps>
- 4.2 (minimum functionality): <which requirement is missing>
Please describe how you want to differentiate or deepen it, or pick a different concept.
```
(Show only the lines that failed.) Then re-run both checks on the revised concept.

**If `auto_idea: true`** — do **not** call AskUserQuestion. Auto-revise the concept: for a 4.3
failure apply one differentiator from the "safe" list above (prefer fixing a mined complaint); for
a 4.2 failure add a persisted native flow (e.g. history with notes, favourites, stats computed from
saved records, local export). Re-run both checks. Retry up to 2 attempts. If the concept still
fails after 2 attempts, fall back to the next-highest-scored proposal from Propose & query and run
both checks on it. With `skip_research: true` there is only one concept and no fallback: after 2
failed revisions set `state.md` to `status: paused`, `pause_reason: manual_action` and log the
reason to `pipeline-log.md`. Record the outcome (which revision was applied, or that a fallback was
used).

Record the result in the research spec (see Output).

---

## Output

### 1. Write the research spec

Create `docs/harness/specs/<YYYY-MM-DD>-research.md` (use today's UTC date). Use the following
structure (the plan phase reads these exact field names):

```markdown
# Research Spec — <app_name>

## Chosen Concept

**Title:** <working title>
**Tagline:** <one sentence>
**Target user & job-to-be-done:** <who> — When <situation>, I want to <motivation>, so I can <outcome>.
**Primary user flows:**
1. <flow 1: trigger → steps → saved result>
2. <flow 2>
**Differentiator:** <unique hook; which competitor complaint it answers>
**Why native Flutter:** <offline / persistence / device features>
**Monetisation hook:** <AdMob formats + where they fit; IAP potential>
**Suggested store category:** App Store <category> / Google Play <category>
**Selection:** <user-selected | auto-selected (auto_idea) — with the weighted total | skip_research (app_idea verbatim)>

## Market Rationale

<2-4 sentences summarising the chart/trend data that supports this choice.
Reference the top competitors and the trend signals discovered.>

## Competitor Summary

| Title | Rating (count) | Primary flows | Strength | Top 1–3★ complaints |
|---|---|---|---|---|
| <title> | <4.6 (12k)> | <flows> | <strength> | <complaints> |

## Unmet Needs (review mining)

| Need | Mentions | Addressed by concept? |
|---|---|---|
| <cluster> | <count> | <yes — how / no> |

## Trend Signals

- <signal> — <source>

## App Store Review Check (4.2 + 4.3)

**Result:** PASS / PASS (revised)
**4.3 — similar apps checked:** <title 1>, <title 2>, <title 3>
**4.3 — differentiating features:** <the features that prevent a copycat rejection>
**4.2 — native flows with persistence:** <flow → what is saved and survives a restart>
**Revision notes:** <what was changed to pass, or "none">

## Skip-Research Note

<!-- If skip_research was true, write: "Discovery skipped — app_idea accepted verbatim." -->
<!-- Otherwise delete this section. -->
```

When `skip_research: true`, fill Competitor Summary from the similar apps found by the 4.3 check
and write "n/a — discovery skipped" under Unmet Needs and Trend Signals.

### 2. Update `config.md`

Set `app_idea` to the final confirmed concept tagline (overwrite the original raw idea). This
ensures downstream skills (plan, design, contract) read the refined concept, not the raw prompt.

Use `Edit` to make a targeted update — do not rewrite the entire file.

### 3. Update `state.md`

Update `docs/harness/state.md` per the schema in `docs/harness-protocol.md` §2:

```yaml
status: running
current_phase: research
next_role: plan
updated_at: "<ISO-8601 UTC now>"
```

Leave all other keys unchanged. Use `Edit` for a targeted update.

### 4. Append to `pipeline-log.md`

Append one row to `docs/harness/pipeline-log.md` per the schema in `docs/harness-protocol.md` §6:

```
| <ISO-8601 UTC now> | complete | research | <N> competitors analysed; concept: <working title>; 4.2/4.3 PASS |
```

If `skip_research` was true, use:

```
| <ISO-8601 UTC now> | complete | research | skip_research=true; concept accepted verbatim; 4.2/4.3 PASS |
```

---

## Error handling

- If WebSearch or WebFetch fails during Discovery (blocked feed, client-rendered page, rate limit),
  log a warning and proceed with whatever data was retrieved. Do not abort — partial market data is
  better than none. Note the gap under Market Rationale.
- If the user declines all proposals and provides no viable alternative after 3 rounds of
  AskUserQuestion, set `state.md` to `status: paused`, `pause_reason: manual_action`, and write
  a note to `pipeline-log.md` explaining that the user could not settle on a concept.
- If `docs/harness/specs/` does not exist, create it before writing the spec file.
