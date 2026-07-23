package com.curiousbeagle.android.myaiagent.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.curiousbeagle.android.myaiagent.R
import com.curiousbeagle.android.myaiagent.model.Lead
import com.curiousbeagle.android.myaiagent.ui.theme.MyAIAgentTheme

/** The lead inbox — stateless; the caller supplies leads and handles clicks. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LeadsScreen(
    leads: List<Lead>,
    onLeadClick: (Lead) -> Unit,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = { TopAppBar(title = { Text(stringResource(R.string.leads_title)) }) },
    ) { innerPadding ->
        LazyColumn(modifier = Modifier.padding(innerPadding)) {
            items(leads, key = { it.id }) { lead ->
                LeadRow(lead = lead, modifier = Modifier.clickable { onLeadClick(lead) })
                HorizontalDivider()
            }
        }
    }
}

@Composable
fun LeadRow(lead: Lead, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(lead.customerName, style = MaterialTheme.typography.titleMedium)
            StatusBadge(status = lead.status)
        }
        Text(
            lead.message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
fun StatusBadge(status: Lead.Status, modifier: Modifier = Modifier) {
    val (label, color) = when (status) {
        Lead.Status.NEW -> stringResource(R.string.lead_status_new) to Color(0xFF1E6FD9)
        Lead.Status.IN_PROGRESS -> stringResource(R.string.lead_status_in_progress) to Color(0xFFB26A00)
        Lead.Status.HANDLED -> stringResource(R.string.lead_status_handled) to Color(0xFF2E7D32)
    }
    Text(
        text = label,
        style = MaterialTheme.typography.labelSmall,
        fontWeight = FontWeight.SemiBold,
        color = color,
        modifier = modifier
            .background(color.copy(alpha = 0.15f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 3.dp),
    )
}

@Preview(showBackground = true)
@Composable
private fun LeadsScreenPreview() {
    MyAIAgentTheme {
        LeadsScreen(leads = Lead.samples, onLeadClick = {})
    }
}

@Preview(showBackground = true, uiMode = android.content.res.Configuration.UI_MODE_NIGHT_YES)
@Composable
private fun LeadsScreenDarkPreview() {
    MyAIAgentTheme {
        LeadsScreen(leads = Lead.samples, onLeadClick = {})
    }
}

@Preview(showBackground = true, fontScale = 2f)
@Composable
private fun LeadsScreenXlTypePreview() {
    MyAIAgentTheme {
        LeadsScreen(leads = Lead.samples, onLeadClick = {})
    }
}
