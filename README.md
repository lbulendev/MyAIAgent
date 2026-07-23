# MyAIAgent

An **agentic AI worker** demo for mobile: the app plays the role of an AI
employee for a small local business (the fictional Beagle Bike Shop),
working inbound customer leads end to end — conversing with the customer,
looking up records, booking appointments, and closing out the lead — with
every agentic mechanic implemented natively on the client.

- **`iOS/`** — Swift 6 / SwiftUI, streaming the Claude Messages API over
  raw SSE (no SDK)
- **`android/`** — Kotlin / Jetpack Compose mirror (in progress)

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
  boundary means the whole agent loop is unit-tested with a scripted fake:
  24 tests tagged `smoke` / `sanity` / `regression`, no network required

## Architecture (iOS)

```
Views/        SwiftUI: lead inbox, chat transcript, status chip, banners
Agent/        AgentEngine (state machine + loop), ToolRegistry, AgentOutbox
Networking/   SSEParser -> AnthropicStreamPayload -> ClaudeProvider
Models/       Lead, ChatMessage, AgentState, CRMStore (mock CRM)
```

## Setup

1. Copy `iOS/MyAIAgent/Secrets.xcconfig.template` to
   `iOS/MyAIAgent/Secrets.xcconfig` and set `ANTHROPIC_API_KEY` (either via
   the environment for command-line builds, or paste the literal for
   Dock-launched Xcode). The file is git-ignored; the app shows setup
   instructions instead of running when the key is missing.
2. Open `iOS/MyAIAgent/MyAIAgent.xcodeproj` and run.

## Tests

```sh
cd iOS/MyAIAgent && xcodebuild test -project MyAIAgent.xcodeproj \
  -scheme MyAIAgent -destination "platform=iOS Simulator,name=iPhone 17" \
  -only-testing:MyAIAgentTests
```

Purpose tags: `smoke` (critical path), `sanity` (contract checks),
`regression` (pinned edge cases — SSE chunking, unknown stream events,
partial tool-input JSON, outbox resume, cancellation).
