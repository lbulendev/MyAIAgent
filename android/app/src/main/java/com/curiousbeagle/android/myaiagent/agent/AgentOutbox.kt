package com.curiousbeagle.android.myaiagent.agent

import com.curiousbeagle.android.myaiagent.model.ChatMessage
import com.curiousbeagle.android.myaiagent.net.WireMessage
import com.curiousbeagle.android.myaiagent.net.wireJson
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.File

/**
 * Per-lead session persistence: the wire conversation, the visible
 * transcript, and whether a run was in flight when last written. One JSON
 * file per lead — right-sized for a demo, and constructed with an
 * injectable directory so tests get isolated storage. Mirrors iOS
 * `AgentOutbox` exactly (the shared design deliberately uses the same
 * snapshot shape on both platforms).
 */
class AgentOutbox(private val directory: File) {

    @Serializable
    data class SessionSnapshot(
        val conversation: List<WireMessage>,
        val transcript: List<ChatMessage>,
        /**
         * True from run start until the run completes or fails. A snapshot
         * loaded with this set means the app died (or lost the network)
         * mid-run — the UI offers Resume, which replays the saved
         * conversation from the last durable boundary.
         */
        val interrupted: Boolean,
    )

    init {
        directory.mkdirs()
    }

    private fun fileFor(leadId: String) = File(directory, "$leadId.json")

    fun save(snapshot: SessionSnapshot, leadId: String) {
        runCatching { fileFor(leadId).writeText(wireJson.encodeToString(snapshot)) }
    }

    fun load(leadId: String): SessionSnapshot? = runCatching {
        wireJson.decodeFromString<SessionSnapshot>(fileFor(leadId).readText())
    }.getOrNull()

    fun clear(leadId: String) {
        fileFor(leadId).delete()
    }
}
