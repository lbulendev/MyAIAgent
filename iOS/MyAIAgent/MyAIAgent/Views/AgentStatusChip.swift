//
//  AgentStatusChip.swift
//  MyAIAgent
//

import SwiftUI

/// Narrates the agent state machine in the transcript so the user can see
/// what the worker is doing: thinking, streaming, or running a tool.
struct AgentStatusChip: View {
    let state: AgentState

    var body: some View {
        if let label {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.fill.quaternary, in: Capsule())
        }
    }

    private var label: String? {
        switch state {
        case .thinking:
            String(localized: "agent_state_thinking", defaultValue: "Thinking…")
        case .streaming:
            String(localized: "agent_state_streaming", defaultValue: "Replying…")
        case .executingTool(let name):
            // Interpolated keys can't take defaultValue: — the English value
            // lives in the catalog under "agent_state_tool %@".
            String(localized: "agent_state_tool \(name)")
        case .idle, .failed:
            nil
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        AgentStatusChip(state: .thinking)
        AgentStatusChip(state: .streaming)
        AgentStatusChip(state: .executingTool(name: "book_appointment"))
    }
    .padding()
}
#endif
