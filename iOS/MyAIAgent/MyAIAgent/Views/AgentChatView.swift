//
//  AgentChatView.swift
//  MyAIAgent
//

import SwiftUI

/// The conversation for one lead: streamed agent replies, tool activity
/// notes, the agent status chip, and the follow-up composer.
struct AgentChatView: View {
    @State private var engine: AgentEngine
    @State private var draft = ""
    private let connectivity: any ConnectivityMonitoring

    init(
        lead: Lead,
        provider: any ModelProvider,
        store: CRMStore,
        outbox: AgentOutbox = AgentOutbox(),
        connectivity: any ConnectivityMonitoring,
        catalog: HelpCatalog = .bundled
    ) {
        _engine = State(initialValue: AgentEngine(
            lead: lead,
            provider: provider,
            store: store,
            outbox: outbox,
            catalog: catalog
        ))
        self.connectivity = connectivity
    }

    var body: some View {
        VStack(spacing: 0) {
            // Resuming needs the network — only invite it when it can work.
            if engine.canResume && connectivity.isOnline {
                resumeBanner
            }
            if case .failed(let error) = engine.state {
                ErrorBanner(error: error) { engine.retry() }
                    .padding(.top, 8)
            }
            if !connectivity.isOnline {
                offlineNotice
            }

            TranscriptView(messages: engine.transcript, state: engine.state)

            composer
        }
        .navigationTitle(engine.lead.customerName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if connectivity.isOnline {
                engine.startIfNeeded()
            } else {
                engine.startOfflineIfNeeded()
            }
        }
        .onChange(of: connectivity.isOnline) { _, online in
            // Losing the network mid-run must not leave the user watching a
            // dead stream: cancel now (which records a resumable snapshot)
            // so the offline responder can take over the conversation.
            if !online { engine.cancel() }
        }
    }

    private var offlineNotice: some View {
        Label(
            String(
                localized: "offline_chat_notice",
                defaultValue: "You're offline. Ask here for instant shop guides — the AI assistant follows up once you're back online."
            ),
            systemImage: "wifi.slash"
        )
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.gray.opacity(0.15))
    }

    private var resumeBanner: some View {
        HStack(spacing: 12) {
            Label(
                String(localized: "resume_banner", defaultValue: "This conversation was interrupted."),
                systemImage: "arrow.clockwise.circle"
            )
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(String(localized: "resume_button", defaultValue: "Resume")) {
                engine.resume()
            }
            .font(.subheadline.weight(.bold))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top])
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(
                String(localized: "chat_input_placeholder", defaultValue: "Reply as the customer…"),
                text: $draft,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit(sendDraft)

            if isRunning {
                Button {
                    engine.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel(String(localized: "cancel_button", defaultValue: "Cancel"))
            } else {
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(String(localized: "send_button", defaultValue: "Send"))
            }
        }
        .padding()
    }

    private var isRunning: Bool {
        switch engine.state {
        case .thinking, .streaming, .executingTool: true
        case .idle, .failed: false
        }
    }

    private func sendDraft() {
        // Clear the draft only if the engine accepted it — a keyboard-return
        // send while the agent is running must not silently drop the text.
        let accepted = connectivity.isOnline ? engine.send(draft) : engine.sendWhileOffline(draft)
        if accepted {
            draft = ""
        }
    }
}

/// The scrolling transcript — plain values, so previews need no engine.
struct TranscriptView: View {
    let messages: [ChatMessage]
    let state: AgentState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    AgentStatusChip(state: state)
                }
                .padding()
            }
            .onChange(of: messages.last?.text) {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        switch message.kind {
        case .customer:
            Text(message.text)
                .padding(12)
                .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .agent:
            Text(message.text.isEmpty ? "…" : message.text)
                .padding(12)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .toolActivity:
            Label(message.text, systemImage: "gearshape.2")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        case .offlineHelp:
            // Visibly NOT the AI worker: labeled, distinct styling. The
            // responder is a local guide lookup, and the UI must say so.
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    String(localized: "offline_help_label", defaultValue: "Offline help"),
                    systemImage: "wifi.slash"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                Text(message.text)
            }
            .padding(12)
            .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.gray.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        AgentChatView(
            lead: .sample,
            provider: PreviewModelProvider(),
            store: CRMStore(),
            outbox: AgentOutbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID())")),
            connectivity: StubConnectivityMonitor()
        )
    }
}

#Preview("Offline") {
    NavigationStack {
        AgentChatView(
            lead: .sample,
            provider: PreviewModelProvider(),
            store: CRMStore(),
            outbox: AgentOutbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID())")),
            connectivity: StubConnectivityMonitor(isOnline: false)
        )
    }
}

#Preview("Transcript states") {
    TranscriptView(
        messages: [
            ChatMessage(kind: .customer, text: Lead.sample.message),
            ChatMessage(kind: .toolActivity, text: "Looked up Dana Reyes"),
            ChatMessage(kind: .agent, text: "Hi Dana! We can get your Trek in for a derailleur tune-up."),
        ],
        state: .executingTool(name: "book_appointment")
    )
}

#Preview("iPad") {
    NavigationStack {
        AgentChatView(
            lead: .sample,
            provider: PreviewModelProvider(),
            store: CRMStore(),
            outbox: AgentOutbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID())")),
            connectivity: StubConnectivityMonitor()
        )
    }
}
#endif
