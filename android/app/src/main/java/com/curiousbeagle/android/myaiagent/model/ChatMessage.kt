package com.curiousbeagle.android.myaiagent.model

import java.util.UUID
import kotlinx.serialization.Serializable

/**
 * One entry in the on-screen transcript. Separate from the wire-format
 * conversation the agent sends to the model — this is what the user sees.
 * Mirrors iOS `ChatMessage`.
 */
@Serializable
data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val kind: Kind,
    val text: String,
) {
    enum class Kind {
        /** Text from the customer (the lead's message or a typed follow-up). */
        CUSTOMER,

        /** Text from the AI worker, streamed token by token. */
        AGENT,

        /** A note about a tool the agent ran ("Booked appointment A-1042"). */
        TOOL_ACTIVITY,
    }
}
