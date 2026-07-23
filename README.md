# MyAIAgent

An **agentic AI worker** demo for mobile: the app plays the role of an AI
employee for a small local business (the fictional Beagle Bike Shop),
working inbound customer leads end to end — conversing with the customer,
looking up records, booking appointments, and closing out the lead — with
every agentic mechanic implemented natively on the client.

- **`iOS/`** — Swift 6 / SwiftUI, streaming the Claude Messages API over
  raw SSE (no SDK)
- **`android/`** — Kotlin / Jetpack Compose mirror: same design, same seams, same test taxonomy (OkHttp SSE, sealed `AgentState` + StateFlow, mirrored JUnit 5 suites)

## What it demonstrates

- **Low-latency streaming** — assistant replies stream token by token into
  the transcript over Server-Sent Events
- **Client-side tool orchestration** — the model calls `lookup_customer`,
  `book_appointment`, and `mark_lead_handled`; the app executes them
  against a mock CRM and feeds results back in a multi-step loop until the
  turn completes
- **Agentic state management** — an explicit state machine
  (`idle → thinking → streaming → executingTool → …`) drives the UI, so
  the user always sees what the worker is doing
- **Offline resume** — every run persists an outbox snapshot; a run
  interrupted by a network drop, cancel, or app death restores as
  resumable and replays from the last durable boundary
- **Honest failure UX** — errors map to offline/server/generic categories
  with a red banner and Retry; raw error text never reaches the screen
- **Testability by design** — a `ModelProvider` seam at the network
  boundary means the whole agent loop is unit-tested with a scripted fake,
  tagged `smoke` / `sanity` / `regression`, no network required — 27 tests
  on iOS (Swift Testing), 26 on Android (JUnit 5), mirrored test-for-test
- **Dual-native discipline** — the same feature shipped twice, natively:
  shared wire format, shared snapshot format, shared localization keyspace,
  and a pinned regression suite on each side for the platform-specific
  transport quirks (URLSession swallows SSE blank lines; Okio preserves
  them)

## Architecture

```
iOS (Swift 6 / SwiftUI)                android (Kotlin / Compose)
Views/       chat, inbox, banners      ui/     chat, inbox, banners
Agent/       AgentEngine, ToolRegistry agent/  AgentEngine, ToolRegistry
             AgentOutbox                       AgentOutbox
Networking/  SSEParser, ClaudeProvider net/    SseParser, ClaudeProvider
Models/      Lead, AgentState, CRM     model/  Lead, AgentState, CRM
```

## Setup

Both apps read `ANTHROPIC_API_KEY` at build time and show setup
instructions instead of running when it's missing. Never commit a key.

**iOS:** copy `iOS/MyAIAgent/Secrets.xcconfig.template` to
`iOS/MyAIAgent/Secrets.xcconfig`. The default resolves the key from the
environment (launch Xcode from a terminal, e.g. `xed iOS/MyAIAgent`);
paste the literal instead for Dock-launched Xcode. Then open
`MyAIAgent.xcodeproj` and run.

**Android:** add `ANTHROPIC_API_KEY=sk-ant-...` to `android/local.properties`
(git-ignored), or export it in the environment. Then open `android/` in
Android Studio and run.

## Tests

```sh
cd iOS/MyAIAgent && xcodebuild test -project MyAIAgent.xcodeproj \
  -scheme MyAIAgent -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:MyAIAgentTests
```

```sh
cd android && ./gradlew :app:testDebugUnitTest   # -PincludeTags=smoke for the smoke plan
```

Purpose tags: `smoke` (critical path), `sanity` (contract checks),
`regression` (pinned edge cases — SSE chunking, unknown stream events,
partial tool-input JSON, outbox resume, cancellation).
