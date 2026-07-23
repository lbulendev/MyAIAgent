package com.curiousbeagle.android.myaiagent.model

import java.io.IOException

/**
 * The client-side agent state machine, mirroring iOS `AgentState`. Every
 * phase of a turn is explicit so the UI can narrate what the agent is doing
 * and tests can pin transitions.
 */
sealed interface AgentState {
    /** No run in flight; ready for input. */
    data object Idle : AgentState

    /** Request sent; waiting for the first streamed event. */
    data object Thinking : AgentState

    /** Streaming assistant text into the transcript. */
    data object Streaming : AgentState

    /** Executing a tool the model called. */
    data class ExecutingTool(val name: String) : AgentState

    /** The last run failed; [error] carries the user-facing category. */
    data class Failed(val error: AgentError) : AgentState
}

/**
 * User-facing error categories. Raw error text never reaches the UI —
 * every thrown error maps into one of these (same pattern as HeartChart
 * and the iOS side).
 */
enum class AgentError {
    OFFLINE, SERVER, GENERIC;

    companion object {
        fun categorize(throwable: Throwable): AgentError = when (throwable) {
            is AgentFailure -> throwable.error
            is IOException -> OFFLINE
            else -> GENERIC
        }
    }
}

/** Thrown internally to carry an already-categorized failure. */
class AgentFailure(val error: AgentError) : Exception("agent failure: $error")
