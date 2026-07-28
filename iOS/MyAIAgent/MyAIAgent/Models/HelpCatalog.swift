//
//  HelpCatalog.swift
//  MyAIAgent
//

import Foundation

/// The bundled self-help catalog (ADR 0001): one canonical JSON document,
/// byte-identical across platforms, shipped as an app resource. It is the
/// single source of truth for capability discovery — the service menu,
/// availability badges, offline suggestions, and the `find_help_article`
/// tool all render from these entries.
///
/// Decode is tolerant by design (the `AnthropicStreamPayload` precedent):
/// unknown entry kinds are skipped and unknown fields are ignored, so
/// content can evolve ahead of shipped clients.
nonisolated struct HelpCatalog: Equatable {
    let version: Int
    let entries: [Entry]

    nonisolated struct Entry: Identifiable, Hashable {
        enum Kind: String, Codable, Hashable {
            case helpArticle = "help_article"
            case service
        }

        /// What the entry needs in order to be usable right now.
        enum Requirement: Hashable {
            /// Fully usable offline — the content is on the device.
            case none
            /// Needs a network connection (live services, video sessions).
            case online
        }

        let kind: Kind
        let id: String
        let title: String
        let summary: String
        let keywords: [String]
        let steps: [String]
        let requirement: Requirement

        /// Whether the entry is usable given current connectivity.
        func isAvailable(online: Bool) -> Bool {
            requirement == .none || online
        }
    }
}

nonisolated extension HelpCatalog.Entry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, id, title, summary, keywords, steps, requires
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
        // A requirement this client doesn't understand must never be
        // presented as available offline — unknown values decode as .online.
        switch try container.decodeIfPresent(String.self, forKey: .requires) {
        case nil, "none": requirement = .none
        case "online": requirement = .online
        default: requirement = .online
        }
    }
}

nonisolated extension HelpCatalog: Decodable {
    private enum CodingKeys: String, CodingKey { case version, entries }

    /// Wrapper that turns an undecodable entry (e.g. an unknown kind) into
    /// nil instead of failing the whole catalog.
    private struct TolerantEntry: Decodable {
        let entry: Entry?
        init(from decoder: any Decoder) {
            entry = try? Entry(from: decoder)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        entries = try container.decode([TolerantEntry].self, forKey: .entries).compactMap(\.entry)
    }
}

// MARK: Loading

nonisolated extension HelpCatalog {
    static func load(from url: URL) throws -> HelpCatalog {
        try JSONDecoder().decode(HelpCatalog.self, from: Data(contentsOf: url))
    }

    /// The catalog shipped in the app bundle. A missing or corrupt resource
    /// is a build error, not a runtime condition — assert, but return an
    /// empty catalog so the UI degrades instead of crashing.
    static let bundled: HelpCatalog = {
        guard let url = Bundle.main.url(forResource: "HelpCatalog", withExtension: "json"),
              let catalog = try? load(from: url) else {
            assertionFailure("HelpCatalog.json is missing or invalid in the app bundle")
            return HelpCatalog(version: 0, entries: [])
        }
        return catalog
    }()
}

// MARK: Retrieval

nonisolated extension HelpCatalog {
    var articles: [Entry] { entries.filter { $0.kind == .helpArticle } }
    var services: [Entry] { entries.filter { $0.kind == .service } }

    /// On-device keyword/tag scoring (ADR 0001: right-sized retrieval — no
    /// embeddings). Deterministic: score descending, catalog order breaks ties.
    func matches(for query: String) -> [Entry] {
        let queryTokens = Self.tokens(in: query)
        guard !queryTokens.isEmpty else { return [] }

        let scored: [(score: Int, index: Int, entry: Entry)] = entries.enumerated().compactMap { index, entry in
            let keywordSet = Set(entry.keywords.map { $0.lowercased() })
            let titleTokens = Set(Self.tokens(in: entry.title))
            let summaryTokens = Set(Self.tokens(in: entry.summary))
            var score = 0
            for token in queryTokens {
                if keywordSet.contains(token) { score += 3 }
                if titleTokens.contains(token) { score += 2 }
                if summaryTokens.contains(token) { score += 1 }
            }
            return score > 0 ? (score, index, entry) : nil
        }

        return scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.entry)
    }

    /// Offline-usable articles matching a lead's message — what the chat
    /// suggests when the AI assistant is unreachable.
    func offlineSuggestions(for query: String, limit: Int = 2) -> [Entry] {
        Array(matches(for: query).filter { $0.kind == .helpArticle && $0.requirement == .none }.prefix(limit))
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
