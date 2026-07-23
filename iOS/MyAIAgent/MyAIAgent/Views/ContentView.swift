//
//  ContentView.swift
//  MyAIAgent
//

import SwiftUI

/// The lead inbox: inbound customer inquiries the AI worker can take on.
struct ContentView: View {
    let provider: any ModelProvider
    @Environment(CRMStore.self) private var store

    var body: some View {
        NavigationStack {
            List(store.leads) { lead in
                NavigationLink(value: lead) {
                    LeadRow(lead: lead)
                }
            }
            .navigationTitle(String(localized: "leads_title", defaultValue: "Leads"))
            .navigationDestination(for: Lead.self) { lead in
                AgentChatView(lead: lead, provider: provider, store: store)
            }
        }
    }
}

/// One row in the inbox — plain values, no dependencies.
struct LeadRow: View {
    let lead: Lead

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(lead.customerName)
                    .font(.headline)
                Spacer()
                StatusBadge(status: lead.status)
            }
            Text(lead.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: Lead.Status

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case .new: String(localized: "lead_status_new", defaultValue: "New")
        case .inProgress: String(localized: "lead_status_in_progress", defaultValue: "In progress")
        case .handled: String(localized: "lead_status_handled", defaultValue: "Handled")
        }
    }

    private var color: Color {
        switch status {
        case .new: .blue
        case .inProgress: .orange
        case .handled: .green
        }
    }
}

#if DEBUG
#Preview {
    ContentView(provider: PreviewModelProvider())
        .environment(CRMStore())
}

#Preview("Small iPhone") {
    ContentView(provider: PreviewModelProvider())
        .environment(CRMStore())
}

#Preview("Dark") {
    ContentView(provider: PreviewModelProvider())
        .environment(CRMStore())
        .preferredColorScheme(.dark)
}

#Preview("XL type") {
    ContentView(provider: PreviewModelProvider())
        .environment(CRMStore())
        .environment(\.dynamicTypeSize, .accessibility2)
}

/// Scripted provider so previews never touch the network.
nonisolated struct PreviewModelProvider: ModelProvider {
    func stream(
        system: String,
        tools: [ToolDefinition],
        messages: [WireMessage]
    ) -> AsyncThrowingStream<StreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textStarted)
            continuation.yield(.textDelta("Happy to help — we can take a look at that derailleur. Does Thursday morning work?"))
            continuation.yield(.finished(stopReason: .endTurn))
            continuation.finish()
        }
    }
}
#endif
