# ADR 0002: Multi-tenant franchise support (tenant chooser, per-tenant catalogs, constrained ordering)

- **Status:** Proposed
- **Date:** 2026-07-28
- **Deciders:** Larry Bulen
- **Feature request:** see the *Multi-tenant franchise* issue in this repo's tracker
- **Builds on:** [ADR 0001 — Offline self-help tier](0001-offline-self-help-tier.md)

## Context

MyAIAgent is single-tenant: the AI worker serves Beagle Bike Shop, and the
business identity is implicit in the code (system prompt, tools, sample
data). We want the same app to demonstrate the agent as a *platform*: at
launch, the user picks which business the worker serves — Beagle Bike Shop
or **Bulldog Burgers**, a fictional quick-service franchise (a deliberate
stand-in; real trademarks stay out of this public demo repo, matching the
fictional-business convention set by Beagle Bike Shop).

The burger tenant exercises the ADR 0001 tiering with new content and a
new transaction: the menu and a weekly special are browsable fully
offline, and — online — the agent can place an order with a limited,
enumerated set of customizations (e.g. no pickles, no onions, no mayo).

## Decision drivers

- One codebase, two businesses: the difference must live in data, not in
  forked code paths, or the dual-native mirror discipline doubles in cost.
- The chooser must be honest: it is business selection for a demo, not
  authentication — but it should sit exactly where real auth would.
- Ordering must be safe and deterministic: the model must not be able to
  invent menu items or customizations the kitchen can't honor.
- The ADR 0001 invariants carry over unchanged: offline is a tier, content
  is bundled canonical JSON with tolerant decode, capability discovery is
  data-driven UI.

## Decisions

### 1. A tenant is configuration, not a code fork

A `TenantProfile` value describes each business: id, display name, theme
tokens, agent system prompt, tool set, catalog resource name, and sample
leads. The composition root loads the selected profile and injects it;
`AgentEngine`, the CRM store, the self-help tier, and the service menu are
tenant-agnostic and read everything business-specific from the profile.

**Rejected:** per-tenant build flavors / app targets — two binaries, two
test runs per platform, and the demo point (one platform, N businesses,
switchable live) is lost.
**Rejected:** scattered `if bikeShop / if burgers` branches — every new
tenant would touch every layer; with profiles, a third tenant is a data
file plus catalog.

### 2. The two-button chooser is a mock session, not authentication

Launch shows a chooser with one button per tenant. The selection persists
as lightweight session state (UserDefaults / DataStore — the repo's
small-persistence convention), a "switch business" action returns to the
chooser, and no credentials are ever collected — extending the existing
chat guardrail (no card details in chat) to passwords as well.

The chooser deliberately occupies the seam where real authentication
would slot in: per-franchise OAuth/SSO would replace the buttons and
resolve to the same `TenantProfile`, leaving everything downstream
untouched. **Upgrade trigger, stated now:** real multi-user or
multi-location demand (per-employee identity, franchise back office).

**Rejected:** faking a username/password screen — teaches nothing, risks
looking like real (bad) auth, and invites storing fake secrets.

### 3. The per-tenant catalog generalizes the ADR 0001 content tier

One catalog schema serves both tenants; entries are typed
(`help_article`, `menu_item`, `service`) and keep ADR 0001's `requires`
field and tolerant decode. Bulldog Burgers ships its menu and the weekly
special as bundled offline entries; the bike shop keeps its repair
guides. The service-menu screen, badges, and chips (ADR 0001 Decision 7)
render from whichever catalog the tenant profile names.

**Noted for the record:** a *weekly* special is content that by
definition changes faster than app releases. v1 bundles it anyway (the
demo's special is fictional and stable), but this is the concrete case
that fires ADR 0001 Decision 2's upgrade trigger — the manifest + hash
content-pack mechanism sketched there is how the special would stay
fresh in a real deployment.

### 4. Tools are tenant-scoped through the profile

`ToolRegistry` is built from the tenant profile: shared core tools
(`mark_lead_handled`, `send_payment_link`) plus vertical tools — bike:
`lookup_customer`, `book_appointment`, `find_help_article`; burgers:
`find_menu_item`, `place_order`. The model is never offered a tool the
tenant doesn't have, so the agent cannot try to book a bike tune-up at a
burger counter. Tool results keep the existing contract (one user
message, `is_error: true` on failure).

### 5. Order customization is an enumerated allowlist, not free text

Each `menu_item` declares its allowed modifiers (e.g. removable:
`pickles`, `onions`, `mayo`). `place_order` validates item ids and
modifiers against the catalog; anything outside the allowlist returns
`is_error: true` and the model corrects itself in-conversation. There are
no free-text special instructions in v1.

Rationale: the order is a bounded contract the (mock) kitchen can always
honor, validation is client-side and deterministic in tests, and
conversation content cannot inject arbitrary instructions into an order
record. **Upgrade trigger:** real demand for free-form notes would add a
clearly-labeled, length-capped note field passed through as data — never
interpreted as instructions.

### 6. Ordering is an online-tier action in v1

Browsing the menu and weekly special is offline (that's the point);
*placing* an order requires the online agent, consistent with ADR 0001's
split — transactional actions (booking, payment, ordering) are the online
tier, and the offline UI says so honestly rather than erroring.
**Upgrade trigger, stated now:** offline order capture would reuse the
store-and-forward outbox pattern (`AgentOutbox`) to queue orders for
replay on reconnect; nothing in v1 blocks it.

## Consequences

**Positive**

- The portfolio story upgrades from "an agent for a bike shop" to "an
  agent platform configured per business" — adding a third vertical is a
  profile + catalog, no engine changes.
- ADR 0001's architecture demonstrably pays off unchanged in a second
  vertical (same tiering, same catalog machinery, same discovery UI).
- Ordering safety (allowlisted modifiers, tenant-scoped tools) is a
  concrete, testable answer to "how do you keep an LLM's actions bounded?"

**Negative / accepted costs**

- The test matrix gains a tenant dimension (chooser, per-tenant tools,
  per-tenant catalogs), mirrored on both platforms.
- Per-tenant theming adds UI surface to keep consistent.
- The bundled weekly special goes stale in a real deployment (accepted;
  trigger and mechanism stated in Decision 3 / ADR 0001).

## Out of scope for v1

Real authentication, real payments or POS integration, order status
tracking / delivery, free-text order notes, per-franchise remote config,
more than two tenants.
