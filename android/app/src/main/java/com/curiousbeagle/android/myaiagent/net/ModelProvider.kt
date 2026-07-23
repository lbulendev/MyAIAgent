package com.curiousbeagle.android.myaiagent.net

import kotlinx.coroutines.flow.Flow

/**
 * Events the agent engine consumes — provider-neutral, mirroring iOS
 * `StreamEvent`, so the engine is testable with a fake and a different
 * backend could plug in behind the same seam.
 */
sealed interface StreamEvent {
    data object TextStarted : StreamEvent
    data class TextDelta(val text: String) : StreamEvent
    data class ToolUseStarted(val id: String, val name: String) : StreamEvent
    data class ToolInputDelta(val id: String, val partialJson: String) : StreamEvent
    data class ToolUseFinished(val id: String) : StreamEvent
    data class Finished(val stopReason: StopReason) : StreamEvent

    sealed interface StopReason {
        data object EndTurn : StopReason
        data object ToolUse : StopReason
        data object MaxTokens : StopReason
        data class Other(val raw: String) : StopReason
    }
}

/**
 * The network boundary seam — the `SensorTransport` analog. `ClaudeProvider`
 * is the production implementation; tests use `FakeModelProvider` with
 * scripted events.
 */
fun interface ModelProvider {
    fun stream(
        system: String,
        tools: List<ToolDefinition>,
        messages: List<WireMessage>,
    ): Flow<StreamEvent>
}
