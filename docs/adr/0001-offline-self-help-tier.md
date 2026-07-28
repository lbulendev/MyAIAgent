# ADR 0001: Offline self-help tier (local knowledge base with agent grounding)

- **Status:** Proposed
- **Date:** 2026-07-28
- **Deciders:** Larry Bulen
- **Feature request:** see the *Self-Help Library* issue in this repo's tracker

## Context

MyAIAgent's support experience is a single tier: a streaming, tool-using AI
worker that requires the network. When the device is offline, the chat
surfaces an error banner with Retry — a dead end. Real customer-communication
products degrade instead: simple, high-frequency questions ("how do I fix a
flat?") can be answered from vetted content that lives on the device, while
diagnosis, booking, and payment legitimately need the online agent.

We want a **self-help article library** that works with zero connectivity,
is visibly marked as offline-capable to the user, and — when online — is
also used by the agent to ground its answers in shop-approved content.

## Decision drivers

- Offline must be a *mode*, not an error: losing the network should route
  the user to useful local content, not a banner.
- Dual-native discipline: one canonical content format consumed by both
  the iOS and Android apps, with mirrored tests (existing repo convention).
- Everything unit-testable without a real network or real connectivity
  changes, through injectable seams (existing `ModelProvider` philosophy).
- v1 stays small: the value is the tiering architecture and the agent
  integration, not content management.

## Decisions

### 1. Connectivity is first-class state, not an error category

A `ConnectivityMonitor` seam (protocol / interface) reports online/offline
as observable state. Production implementations: `NWPathMonitor` (iOS),
`ConnectivityManager` network callbacks (Android). Tests inject a scripted
fake and drive transitions deterministically.

The existing error-category UX (offline/server/generic banner + Retry) is
*extended, not replaced*: a failed run still banners, but the chat's offline
state now also offers matched self-help articles as a productive path.

**Rejected:** inferring offline solely from request failures. That only
detects offline after a failed attempt and cannot power proactive UI (the
offline badge, the pre-emptive self-help routing).

### 2. Content ships in the app bundle as one canonical JSON

Articles live in a single JSON document, byte-identical across platforms
(the same convention as the shared outbox snapshot format), bundled as an
app resource (iOS bundle / Android assets). Content is versioned with the
app; there is no CMS, no download step, no cache invalidation.

**Upgrade trigger, stated now:** if content must change faster than app
releases, move to signed downloadable content packs layered over the
bundled baseline. Nothing in the v1 design blocks that.

**Rejected:** SwiftData/Room-backed content store — an ORM buys nothing
for read-only bundled content and forks the format per platform.
**Rejected:** remote-first with local cache — inverts the feature's point;
the offline tier must not depend on ever having been online.

### 3. Tolerant decode for content evolution

Unknown fields and unknown article kinds are ignored on decode, mirroring
the `AnthropicStreamPayload` precedent, so content can evolve ahead of
shipped clients. Regression tests pin this on both platforms.

### 4. Retrieval is on-device keyword/tag scoring

Matching a lead's message (or a user query) to articles uses simple
tag + keyword scoring. No embeddings, no ML runtime.

**Upgrade trigger:** if the corpus grows beyond a size where curated tags
stay accurate, or matching quality measurably fails, revisit with on-device
semantic search. For ~10 curated articles, keyword scoring is the
right-sized choice and fully deterministic in tests.

### 5. Online, the agent grounds itself in the same content

A new client tool, `find_help_article`, lets the model retrieve an article
(steps included) and attach an article card to the transcript. The agent
answers repair questions from vetted shop content rather than improvising —
one content source serving both tiers. Tool results follow the existing
contract (all results in one user message; failures return `is_error: true`).

### 6. Offline capability is visible to the user

Every article shows an availability badge. To keep the badge honest and
meaningful, the catalog deliberately includes online-only entries (e.g. a
live video fitting session) alongside the offline articles — the badge
distinguishes real tiers rather than decorating everything.

## Consequences

**Positive**

- Offline becomes a designed product tier with a graceful degradation path.
- The agent gains grounding in local, shop-approved truth (RAG-lite) with
  no new backend.
- All new behavior is testable through seams: scripted connectivity,
  scripted model provider, article store loaded from an injectable URL.
- The shared-content-format and tolerant-decode conventions of the repo
  extend naturally; tests mirror test-for-test across platforms.

**Negative / accepted costs**

- Content updates require an app release (accepted for v1; upgrade path
  stated in Decision 2).
- Keyword retrieval can mismatch on phrasing the tags don't cover
  (accepted at this corpus size; upgrade path stated in Decision 4).
- One more explicit state dimension (connectivity) threaded through the
  chat UI, with the test matrix growth that implies.

## Out of scope for v1

Article authoring or editing UI, favorites/bookmarks, downloadable content
packs, semantic search, analytics on article usage.
