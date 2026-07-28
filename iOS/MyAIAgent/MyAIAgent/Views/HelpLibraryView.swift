//
//  HelpLibraryView.swift
//  MyAIAgent
//

import SwiftUI

/// The service menu (ADR 0001, Decision 7): every service and guide the shop
/// offers, with live availability. Rendered entirely from the bundled
/// catalog — capability discovery never depends on the model or the network.
struct HelpLibraryView: View {
    let catalog: HelpCatalog
    let isOnline: Bool

    var body: some View {
        List {
            Section(String(localized: "help_section_services", defaultValue: "Services")) {
                ForEach(catalog.services) { service in
                    HelpEntryRow(entry: service, isOnline: isOnline)
                }
            }
            Section(String(localized: "help_section_guides", defaultValue: "Self-help guides")) {
                ForEach(catalog.articles) { article in
                    NavigationLink(value: article) {
                        HelpEntryRow(entry: article, isOnline: isOnline)
                    }
                }
            }
        }
        .navigationTitle(String(localized: "help_title", defaultValue: "How can we help?"))
    }
}

/// One catalog entry: title, summary, and its availability badge. Rows that
/// need a connection grey out when offline — they never silently disappear.
struct HelpEntryRow: View {
    let entry: HelpCatalog.Entry
    let isOnline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.title)
                    .font(.headline)
                Spacer()
                AvailabilityBadge(requirement: entry.requirement, isOnline: isOnline)
            }
            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .opacity(entry.isAvailable(online: isOnline) ? 1 : 0.5)
    }
}

struct AvailabilityBadge: View {
    let requirement: HelpCatalog.Entry.Requirement
    let isOnline: Bool

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch requirement {
        case .none:
            String(localized: "help_badge_offline", defaultValue: "Available offline")
        case .online where isOnline:
            String(localized: "help_badge_online_only", defaultValue: "Online only")
        case .online:
            String(localized: "help_badge_needs_connection", defaultValue: "Needs connection")
        }
    }

    private var color: Color {
        switch requirement {
        case .none: .green
        case .online: isOnline ? .blue : .gray
        }
    }
}

/// One self-help article: numbered, shop-approved steps.
struct HelpArticleView: View {
    let article: HelpCatalog.Entry

    var body: some View {
        List {
            Section {
                Text(article.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(Array(article.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.tint)
                        Text(step)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Label(
                    String(localized: "help_badge_offline", defaultValue: "Available offline"),
                    systemImage: "arrow.down.circle"
                )
            }
        }
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Offline state in the chat: the AI assistant honestly needs a connection,
/// and matched guides are offered as the productive path (ADR 0001 — offline
/// is a mode, not a dead end).
struct OfflineHelpBanner: View {
    let suggestions: [HelpCatalog.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "wifi.slash")
                .font(.subheadline)
            ForEach(suggestions) { article in
                NavigationLink(value: article) {
                    HStack {
                        Image(systemName: "book")
                        Text(article.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding([.horizontal, .top])
    }

    private var message: String {
        if suggestions.isEmpty {
            String(
                localized: "offline_chat_banner_no_matches",
                defaultValue: "The AI assistant needs a connection. Self-help guides are available in the help library."
            )
        } else {
            String(
                localized: "offline_chat_banner",
                defaultValue: "The AI assistant needs a connection. These guides work offline:"
            )
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HelpLibraryView(catalog: .bundled, isOnline: true)
            .navigationDestination(for: HelpCatalog.Entry.self) { HelpArticleView(article: $0) }
    }
}

#Preview("Offline") {
    NavigationStack {
        HelpLibraryView(catalog: .bundled, isOnline: false)
            .navigationDestination(for: HelpCatalog.Entry.self) { HelpArticleView(article: $0) }
    }
}

#Preview("Article") {
    NavigationStack {
        if let article = HelpCatalog.bundled.articles.first {
            HelpArticleView(article: article)
        }
    }
}

#Preview("Offline banner") {
    VStack {
        OfflineHelpBanner(suggestions: HelpCatalog.bundled.offlineSuggestions(for: "flat tire on my commuter"))
        OfflineHelpBanner(suggestions: [])
    }
}

#Preview("Dark") {
    NavigationStack {
        HelpLibraryView(catalog: .bundled, isOnline: false)
    }
    .preferredColorScheme(.dark)
}
#endif
