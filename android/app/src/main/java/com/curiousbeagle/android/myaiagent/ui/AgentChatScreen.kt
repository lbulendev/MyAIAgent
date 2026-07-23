package com.curiousbeagle.android.myaiagent.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.curiousbeagle.android.myaiagent.R
import com.curiousbeagle.android.myaiagent.agent.AgentEngine
import com.curiousbeagle.android.myaiagent.model.AgentError
import com.curiousbeagle.android.myaiagent.model.AgentState
import com.curiousbeagle.android.myaiagent.model.ChatMessage
import com.curiousbeagle.android.myaiagent.model.Lead
import com.curiousbeagle.android.myaiagent.ui.theme.MyAIAgentTheme

/** Stateful wrapper: collects the engine's flows and forwards intents. */
@Composable
fun AgentChatRoute(engine: AgentEngine, modifier: Modifier = Modifier) {
    val transcript by engine.transcript.collectAsStateWithLifecycle()
    val state by engine.state.collectAsStateWithLifecycle()
    val canResume by engine.canResume.collectAsStateWithLifecycle()

    LaunchedEffect(engine) { engine.startIfNeeded() }

    AgentChatScreen(
        title = engine.lead.customerName,
        transcript = transcript,
        state = state,
        canResume = canResume,
        onSend = { engine.send(it) },
        onCancel = engine::cancel,
        onRetry = engine::retry,
        onResume = engine::resume,
        modifier = modifier,
    )
}

/** Stateless conversation screen — previewable without an engine. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentChatScreen(
    title: String,
    transcript: List<ChatMessage>,
    state: AgentState,
    canResume: Boolean,
    onSend: (String) -> Boolean,
    onCancel: () -> Unit,
    onRetry: () -> Unit,
    onResume: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var draft by remember { mutableStateOf("") }
    val isRunning = state is AgentState.Thinking || state is AgentState.Streaming || state is AgentState.ExecutingTool

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = { TopAppBar(title = { Text(title) }) },
        bottomBar = {
            Composer(
                draft = draft,
                onDraftChange = { draft = it },
                isRunning = isRunning,
                onSend = {
                    // Clear the draft only if the engine accepted it — a send
                    // while the agent is running must not drop the text.
                    if (onSend(draft)) {
                        draft = ""
                    }
                },
                onCancel = onCancel,
            )
        },
    ) { innerPadding ->
        Column(modifier = Modifier.padding(innerPadding)) {
            if (canResume) {
                ResumeBanner(onResume = onResume)
            }
            (state as? AgentState.Failed)?.let { failed ->
                ErrorBanner(error = failed.error, onRetry = onRetry)
            }
            TranscriptView(
                messages = transcript,
                state = state,
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Composable
fun TranscriptView(messages: List<ChatMessage>, state: AgentState, modifier: Modifier = Modifier) {
    val listState = rememberLazyListState()
    LaunchedEffect(messages.lastOrNull()?.text) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.lastIndex)
    }
    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items(messages, key = { it.id }) { message ->
            MessageBubble(message = message)
        }
        item { AgentStatusChip(state = state) }
    }
}

@Composable
fun MessageBubble(message: ChatMessage, modifier: Modifier = Modifier) {
    when (message.kind) {
        ChatMessage.Kind.CUSTOMER -> Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
            Text(
                message.text,
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.primaryContainer, RoundedCornerShape(14.dp))
                    .padding(12.dp),
            )
        }
        ChatMessage.Kind.AGENT -> Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.CenterStart) {
            Text(
                message.text.ifEmpty { "…" },
                modifier = Modifier
                    .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(14.dp))
                    .padding(12.dp),
            )
        }
        ChatMessage.Kind.TOOL_ACTIVITY -> Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Text(
                "⚙ ${message.text}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Narrates the agent state machine so the user sees what the worker is doing. */
@Composable
fun AgentStatusChip(state: AgentState, modifier: Modifier = Modifier) {
    val label = when (state) {
        AgentState.Thinking -> stringResource(R.string.agent_state_thinking)
        AgentState.Streaming -> stringResource(R.string.agent_state_streaming)
        is AgentState.ExecutingTool -> stringResource(R.string.agent_state_tool, state.name)
        AgentState.Idle, is AgentState.Failed -> null
    } ?: return
    Row(
        modifier = modifier
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(modifier = Modifier.width(14.dp), strokeWidth = 2.dp)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ResumeBanner(onResume: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .background(MaterialTheme.colorScheme.tertiaryContainer, RoundedCornerShape(12.dp))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            stringResource(R.string.resume_banner),
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = onResume) {
            Text(stringResource(R.string.resume_button), fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun Composer(
    draft: String,
    onDraftChange: (String) -> Unit,
    isRunning: Boolean,
    onSend: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            // Edge-to-edge: keep the composer above the system navigation
            // bar (3-button bars overlap it otherwise — seen on a Galaxy
            // A05) and above the keyboard when it opens.
            .navigationBarsPadding()
            .imePadding()
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        OutlinedTextField(
            value = draft,
            onValueChange = onDraftChange,
            placeholder = { Text(stringResource(R.string.chat_input_placeholder)) },
            modifier = Modifier.weight(1f),
        )
        if (isRunning) {
            IconButton(onClick = onCancel) {
                Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.cancel_button))
            }
        } else {
            Button(onClick = onSend, enabled = draft.isNotBlank()) {
                Text(stringResource(R.string.send_button))
            }
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun TranscriptPreview() {
    MyAIAgentTheme {
        TranscriptView(
            messages = listOf(
                ChatMessage(kind = ChatMessage.Kind.CUSTOMER, text = Lead.sample.message),
                ChatMessage(kind = ChatMessage.Kind.TOOL_ACTIVITY, text = "Looked up Dana Reyes"),
                ChatMessage(kind = ChatMessage.Kind.AGENT, text = "Hi Dana! We can get your Trek in for a derailleur tune-up."),
            ),
            state = AgentState.ExecutingTool("book_appointment"),
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun ChatScreenErrorPreview() {
    MyAIAgentTheme {
        AgentChatScreen(
            title = "Dana Reyes",
            transcript = listOf(ChatMessage(kind = ChatMessage.Kind.CUSTOMER, text = Lead.sample.message)),
            state = AgentState.Failed(AgentError.OFFLINE),
            canResume = true,
            onSend = { false }, onCancel = {}, onRetry = {}, onResume = {},
        )
    }
}
