# MyAIAgent

Agentic-AI demo pair: an AI worker for a fictional local business ("Beagle
Bike Shop") that handles inbound customer leads end to end — streaming
replies, client-side tool orchestration against a mock CRM, an explicit
agent state machine, and offline resume. `iOS/MyAIAgent/` (Swift 6, SwiftUI,
Claude Messages API over SSE) is built; `android/` is the Kotlin/Compose
mirror (template only so far). Global mobile conventions in
~/.claude/CLAUDE.md apply; specifics below.

## Build & test

iOS — deployment target 26.0 (Larry's iPhone 13 runs 26.5.x); prefer the
26.5 simulator (same destination as HeartChart; the 27.0 sim wedges on
diagnostics):

```sh
cd iOS/MyAIAgent && xcodebuild test -project MyAIAgent.xcodeproj \
  -scheme MyAIAgent -destination "id=6C8E1CF5-5CBE-45B4-9453-0E5588BD274F" \
  -only-testing:MyAIAgentTests
# Smoke only (CLI): -only-testing:MyAIAgentTests/SmokeTests
```

- KNOWN TOOLCHAIN QUIRK (Xcode 27 beta): `-testPlan SmokeTests` fails with
  "test plan could not be read" for tag-filtered plans — on this project AND
  on HeartChart's identical plan. The plans work in the Xcode GUI; from the
  CLI use the `-only-testing` suite filter above. `-testPlan FullTests`
  works fine.

## Secrets — NO publicly available API keys

- The Anthropic API key follows the TheMovieDBSwift pattern exactly:
  git-ignored `Secrets.xcconfig` (`ANTHROPIC_API_KEY = $(ANTHROPIC_API_KEY)`,
  or a pasted literal for Dock-launched Xcode) → `Support/Info.plist`
  (`AnthropicAPIKey`) → Bundle. The app fails fast at launch into
  `KeyMissingView` (instructions, not a crash) when the key is empty — so
  tests and previews run keyless.
- `Secrets.xcconfig` is git-ignored at the repo root; the committed
  `Secrets.xcconfig.template` documents setup. Never commit a real key.

## Project notes

- Modern pbxproj with synchronized folder groups — moving/adding files on
  disk is enough. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; pure value
  types AND THEIR EXTENSIONS must be explicitly `nonisolated` (an extension
  does not inherit the type's nonisolation — `Lead.sample` bit this).
- Layers: `Networking/` owns the wire (SSEParser → AnthropicStreamPayload →
  ClaudeProvider maps to provider-neutral `StreamEvent`s); `Agent/` owns the
  loop (AgentEngine state machine, ToolRegistry dispatch, AgentOutbox
  persistence); `Models/` are nonisolated values plus the @MainActor
  CRMStore; `Views/` take plain values where possible.
- `ModelProvider` is the testable seam at the network boundary
  (ClaudeProvider = production, FakeModelProvider = tests,
  PreviewModelProvider = previews). Model: `claude-opus-4-8`,
  max_tokens 4096, streaming SSE, client tools — no SDK, raw URLSession.
- RESUME INVARIANT: the wire conversation only ever ends on a *user*
  message while a snapshot is marked interrupted (assistant blocks are
  appended only after a stream completes). Replaying a saved conversation
  is therefore always a valid request. Don't break this when reordering
  the loop.
- Tool results all return in ONE user message per API contract; a failed
  tool returns `is_error: true`, never a dropped result. Unknown stream
  event types are `.ignored` by design — new API events must not break
  old clients (pinned by regression tests).
- Samples/outbox: one JSON file per lead in Application Support;
  tests inject a temp directory. UserDefaults is unused so far.
- Localization: snake_case keyspace shared with the future Android port
  (en, en-US, es-US, en-CA, fr-CA). The `agent_state_tool %@` key can't use
  `String(localized:defaultValue:)` — interpolated keys need the plain
  `String(localized:)` form with the value living in the catalog.
- The Android mirror should follow the HeartChart port playbook: same
  seams (Transport interface + fake), same tag taxonomy, mirrored tests,
  OkHttp SSE, sealed AgentState + StateFlow, DataStore outbox, and ALWAYS
  rethrow CancellationException before catch(Exception) in the agent loop.
