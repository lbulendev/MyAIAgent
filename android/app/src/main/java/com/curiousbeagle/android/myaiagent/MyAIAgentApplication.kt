package com.curiousbeagle.android.myaiagent

import android.app.Application
import com.curiousbeagle.android.myaiagent.agent.AgentEngine
import com.curiousbeagle.android.myaiagent.agent.AgentOutbox
import com.curiousbeagle.android.myaiagent.model.CrmStore
import com.curiousbeagle.android.myaiagent.model.Lead
import com.curiousbeagle.android.myaiagent.net.ClaudeProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File

class MyAIAgentApplication : Application() {

    /** App-scoped dependencies; small enough that manual wiring beats a DI framework. */
    lateinit var store: CrmStore
        private set

    lateinit var outbox: AgentOutbox
        private set

    // App-scoped so streams survive configuration changes (HeartChart pattern).
    private val engineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val engines = mutableMapOf<String, AgentEngine>()

    val apiKey: String get() = BuildConfig.ANTHROPIC_API_KEY

    override fun onCreate() {
        super.onCreate()
        store = CrmStore()
        outbox = AgentOutbox(File(filesDir, "agent_sessions"))
    }

    /** One engine per lead, kept for the app's lifetime so rotation never drops a stream. */
    fun engineFor(lead: Lead): AgentEngine = engines.getOrPut(lead.id) {
        AgentEngine(
            lead = lead,
            provider = ClaudeProvider(apiKey),
            store = store,
            outbox = outbox,
            scope = engineScope,
        )
    }
}
