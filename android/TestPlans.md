# Test Plans

Mirrors the iOS test taxonomy (`iOS/MyAIAgent/TestPlans/*.xctestplan`) and
the HeartChart Android setup. Every unit test carries one **purpose** tag
(via its suite class) and one **area** tag (via its nested class).

## Tags

| Purpose tag  | Meaning                                                     |
|--------------|-------------------------------------------------------------|
| `smoke`      | Critical-path checks. If any fail, stop and fix first.      |
| `sanity`     | Contract checks on tool schemas, CRM, error mapping, prompt.|
| `regression` | Pinned edge cases (SSE blank-line delimiters, unknown stream events, partial tool-input JSON, outbox resume, cancellation) that must never come back. |

Area tags: `agent`, `parsing`, `tools`, `persistence`.

## Plans

```sh
./gradlew :app:testDebugUnitTest                        # FullTests
./gradlew :app:testDebugUnitTest -PincludeTags=smoke    # SmokeTests
./gradlew :app:testDebugUnitTest -PincludeTags=parsing  # by area
```

Unit tests drive `AgentEngine` through the `ModelProvider` seam with a
scripted fake — no network, no emulator. Live streaming against the real
API requires a device/emulator build with `ANTHROPIC_API_KEY` configured.
