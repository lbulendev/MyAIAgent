package com.curiousbeagle.android.myaiagent

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.curiousbeagle.android.myaiagent.ui.AgentChatRoute
import com.curiousbeagle.android.myaiagent.ui.KeyMissingScreen
import com.curiousbeagle.android.myaiagent.ui.LeadsScreen
import com.curiousbeagle.android.myaiagent.ui.theme.MyAIAgentTheme
import kotlinx.serialization.Serializable

// Type-safe routes carry ids, not payloads.
@Serializable
object LeadsRoute

@Serializable
data class ChatRoute(val leadId: String)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as MyAIAgentApplication

        setContent {
            MyAIAgentTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    // Fail fast with instructions when no API key was injected
                    // at build time — never a crash, never a hardcoded key.
                    if (app.apiKey.isEmpty()) {
                        KeyMissingScreen()
                    } else {
                        val navController = rememberNavController()
                        NavHost(navController = navController, startDestination = LeadsRoute) {
                            composable<LeadsRoute> {
                                val leads by app.store.leads.collectAsStateWithLifecycle()
                                LeadsScreen(
                                    leads = leads,
                                    onLeadClick = { lead -> navController.navigate(ChatRoute(lead.id)) },
                                )
                            }
                            composable<ChatRoute> { backStackEntry ->
                                val route = backStackEntry.toRoute<ChatRoute>()
                                val lead = app.store.lead(route.leadId) ?: return@composable
                                AgentChatRoute(engine = app.engineFor(lead))
                            }
                        }
                    }
                }
            }
        }
    }
}
