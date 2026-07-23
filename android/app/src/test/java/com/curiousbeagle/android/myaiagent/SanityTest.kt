package com.curiousbeagle.android.myaiagent

import com.curiousbeagle.android.myaiagent.agent.AgentEngine
import com.curiousbeagle.android.myaiagent.agent.ToolRegistry
import com.curiousbeagle.android.myaiagent.model.AgentError
import com.curiousbeagle.android.myaiagent.model.AgentFailure
import com.curiousbeagle.android.myaiagent.model.CrmStore
import com.curiousbeagle.android.myaiagent.model.Lead
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import java.net.UnknownHostException

/**
 * Contract checks on scaffolding, mirroring the iOS SanityTests: tool
 * schemas, CRM behavior, error mapping, and the system prompt. Failures
 * usually mean drift, not bugs.
 */
@Tag("sanity")
class SanityTest {

    @Nested
    @Tag("tools")
    inner class ToolDefinitions {

        @Test
        fun `the registry exposes the three worker tools with unique names`() {
            val names = ToolRegistry.definitions.map { it.name }
            assertEquals(listOf("lookup_customer", "book_appointment", "mark_lead_handled"), names)
            assertEquals(names.size, names.toSet().size)
        }

        @Test
        fun `every tool schema is an object with a required array`() {
            for (definition in ToolRegistry.definitions) {
                assertEquals(
                    "object",
                    definition.inputSchema["type"]?.toString()?.trim('"'),
                    definition.name,
                )
                assertNotNull(definition.inputSchema["required"], "${definition.name} has no required fields")
            }
        }
    }

    @Nested
    @Tag("tools")
    inner class Crm {

        @Test
        fun `customer lookup is case-insensitive and partial-tolerant`() {
            val store = CrmStore()
            assertNotNull(store.lookupCustomer("dana reyes"))
            assertNotNull(store.lookupCustomer("Dana"))
            assertNull(store.lookupCustomer("Nobody Realman"))
        }

        @Test
        fun `booked appointments get sequential confirmation ids`() {
            val store = CrmStore()
            val first = store.bookAppointment("A", "tune-up", "Thursday")
            val second = store.bookAppointment("B", "flat fix", "Friday")
            assertEquals("A-1042", first.id)
            assertEquals("A-1043", second.id)
            assertEquals(2, store.appointments.value.size)
        }

        @Test
        fun `marking a lead handled updates its status`() {
            val lead = Lead.sample
            val store = CrmStore(listOf(lead))
            store.markLeadHandled(lead.id)
            assertEquals(Lead.Status.HANDLED, store.leads.value.first().status)
        }
    }

    @Nested
    @Tag("agent")
    inner class ErrorMapping {

        @Test
        fun `connectivity failures map to the offline category`() {
            assertEquals(AgentError.OFFLINE, AgentError.categorize(UnknownHostException("api.anthropic.com")))
            assertEquals(AgentError.OFFLINE, AgentError.categorize(java.net.SocketTimeoutException()))
        }

        @Test
        fun `other errors fall through to server or generic - never raw text`() {
            assertEquals(AgentError.SERVER, AgentError.categorize(AgentFailure(AgentError.SERVER)))
            assertEquals(AgentError.GENERIC, AgentError.categorize(RuntimeException("mystery")))
        }
    }

    @Nested
    @Tag("agent")
    inner class Prompt {

        @Test
        fun `the system prompt names the lead and pins the tool rules`() {
            val prompt = AgentEngine.systemPrompt(Lead.sample)
            assertTrue(prompt.contains("Dana Reyes"))
            assertTrue(prompt.contains("lookup_customer"))
            assertTrue(prompt.contains("mark_lead_handled"))
        }
    }
}
