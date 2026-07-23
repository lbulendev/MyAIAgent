package com.curiousbeagle.android.myaiagent

import com.curiousbeagle.android.myaiagent.FakeModelProvider.ScriptedTurn
import com.curiousbeagle.android.myaiagent.model.AgentState
import com.curiousbeagle.android.myaiagent.model.ChatMessage
import com.curiousbeagle.android.myaiagent.net.WireContentBlock
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test

/**
 * Critical path only, mirroring the iOS SmokeTests: a lead opens, the agent
 * streams a reply, and a tool round-trip completes. If anything here fails,
 * stop and fix before reading other results.
 */
@Tag("smoke")
class SmokeTest {

    @Nested
    @Tag("agent")
    inner class AgentRun {

        @Test
        fun `a streamed reply lands in the transcript and the agent goes idle`() = runTest {
            val provider = FakeModelProvider(listOf(ScriptedTurn.textTurn("Happy to help with that tune-up!")))
            val (engine, _, _) = makeEngine(this, provider)

            engine.startIfNeeded()
            advanceUntilIdle()

            assertEquals(AgentState.Idle, engine.state.value)
            assertEquals(
                listOf(ChatMessage.Kind.CUSTOMER, ChatMessage.Kind.AGENT),
                engine.transcript.value.map { it.kind },
            )
            assertEquals("Happy to help with that tune-up!", engine.transcript.value.last().text)
        }

        @Test
        fun `a tool call round-trips - results go back and the next turn streams`() = runTest {
            val provider = FakeModelProvider(
                listOf(
                    ScriptedTurn.toolTurn("tu_1", "lookup_customer", """{"name": "Dana Reyes"}"""),
                    ScriptedTurn.textTurn("Found you, Dana — Thursday works."),
                )
            )
            val (engine, _, _) = makeEngine(this, provider)

            engine.startIfNeeded()
            advanceUntilIdle()

            // Second request must carry the tool result in a single user message.
            assertEquals(2, provider.recordedRequests.size)
            val lastMessage = provider.recordedRequests[1].last()
            assertEquals("user", lastMessage.role)
            assertTrue(lastMessage.content.any { it is WireContentBlock.ToolResult && it.toolUseId == "tu_1" && !it.isError })
            // The transcript narrates the tool activity between the turns.
            assertEquals(
                listOf(ChatMessage.Kind.CUSTOMER, ChatMessage.Kind.TOOL_ACTIVITY, ChatMessage.Kind.AGENT),
                engine.transcript.value.map { it.kind },
            )
        }
    }
}
