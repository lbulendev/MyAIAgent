# MyAIAgent

Agentic-AI demo pair: an AI worker for a fictional local business ("Beagle
Bike Shop") that handles inbound customer leads end to end — streaming
replies, client-side tool orchestration against a mock CRM, an explicit
agent state machine, and offline resume. Two native apps sharing one
design: `iOS/MyAIAgent/` (Swift 6, SwiftUI, Claude Messages API over SSE)
and `android/` (Kotlin/Compose mirror with the same seams and mirrored
tests). Global mobile conventions in ~/.claude/CLAUDE.md apply; specifics
below.

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

Android (no system Java — use the Studio JBR; compileSdk 37 because the
androidx versions require it, minSdk 26):

```sh
cd android && JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
  ./gradlew :app:testDebugUnitTest          # FullTests
  # -PincludeTags=smoke                     # SmokeTests plan (TestPlans.md)
```

## Secrets — NO publicly available API keys

- The Anthropic API key follows the TheMovieDBSwift pattern on both sides.
  iOS: git-ignored `Secrets.xcconfig` (`ANTHROPIC_API_KEY =
  $(ANTHROPIC_API_KEY)`, resolved from the env — launch Xcode via `xed`
  from a terminal, quitting any Dock-launched instance first — or a pasted
  literal) → `Support/Info.plist` (`AnthropicAPIKey`) → Bundle. Android:
  git-ignored `local.properties` `ANTHROPIC_API_KEY=` with an env-var
  fallback → BuildConfig. Both apps fail fast at launch into a
  KeyMissing screen (instructions, not a crash), so tests and previews
  run keyless. The key is exported in Larry's ~/.zshrc.
- Never commit a real key. `Secrets.xcconfig` and `local.properties` are
  git-ignored; the committed `Secrets.xcconfig.template` documents setup.

## Project notes — shared design

- Layer mirror (iOS name / Android name): SSEParser+SSELineSplitter /
  SseParser; AnthropicStreamPayload (tolerant decode — unknown event types
  are Ignored by design, pinned by regression tests on both sides);
  ModelProvider seam (ClaudeProvider = production, FakeModelProvider =
  tests); AgentEngine (state machine + stream→tool→continue loop);
  ToolRegistry (5 tools vs the mock CRM + help catalog); ConnectivityMonitor
  seam (NWPathMonitor prod / scripted stub, ADR 0001); HelpCatalog (bundled
  canonical JSON, tolerant decode, keyword retrieval); AgentOutbox (one JSON snapshot
  file per lead, injectable directory — deliberately the same file-based
  shape on both platforms rather than DataStore, so the snapshot format
  and tests mirror).
- Model: `claude-opus-4-8`, max_tokens 4096, streaming SSE, client tools —
  no SDK; raw URLSession (iOS) / OkHttp (Android).
- RESUME INVARIANT (both platforms): the wire conversation only ever ends
  on a *user* message while a snapshot is marked interrupted. Replaying a
  saved conversation is therefore always a valid request.
- Tool results all return in ONE user message per API contract; failed
  tools return `is_error: true`, never a dropped result.
- SSE HARD LESSON (pinned by regression tests on both sides): blank lines
  delimit SSE events. iOS `URLSession.AsyncBytes.lines` SWALLOWS them
  (use SSELineSplitter); OkHttp `readUtf8Line()` preserves them (test
  pins that assumption). An empty completed turn throws SERVER — never a
  silent idle.
- Localization: snake_case keyspace shared across platforms (en, en-US,
  es-US, en-CA, fr-CA). iOS `String(localized:)` + xcstrings; Android
  strings.xml per locale, apostrophes escaped (`s\'est` — unescaped
  French apostrophes fail resource compilation). The `agent_state_tool`
  key takes the tool name as its format arg.

## iOS-specific

- SIMULATOR QUIRK: a long-lived NWPathMonitor often never delivers the
  `satisfied` update after the network returns (offline sticks forever).
  A FRESH monitor's initial path report is reliable — ConnectivityMonitor
  runs a probe watchdog while offline for exactly this reason. Expect an
  analogous reconnect-detection check on the Android mirror.

- Modern pbxproj with synchronized folder groups; `SWIFT_DEFAULT_ACTOR_ISOLATION
  = MainActor` — pure value types AND THEIR EXTENSIONS must be explicitly
  `nonisolated` (an extension does not inherit the type's nonisolation).

## Android-specific

- AGP 9.3 with built-in Kotlin; kotlinx.serialization plugin for wire
  types (sealed `WireContentBlock` with `classDiscriminator = "type"`)
  and type-safe Navigation Compose routes (routes carry leadId, not
  payloads).
- AgentEngine is a plain class with an injected CoroutineScope (the
  HeartChart monitor pattern), app-scoped in MyAIAgentApplication so
  streams survive rotation; UI collects its StateFlows.
- ALWAYS rethrow CancellationException before `catch (e: Exception)` in
  the agent loop — the cancel path records resumable state, then rethrows.
- TEST GOTCHA (coroutines 1.10.2): `advanceUntilIdle()` does NOT drive
  jobs launched in runTest's `backgroundScope` — inject the TestScope
  itself (`this`) as the engine scope instead. The Hang-based cancel test
  cancels explicitly so no jobs leak.
- JUnit 5 with smoke/sanity/regression `@Tag`s + `-PincludeTags` (see
  android/TestPlans.md); suites mirror the iOS ones test-for-test.
