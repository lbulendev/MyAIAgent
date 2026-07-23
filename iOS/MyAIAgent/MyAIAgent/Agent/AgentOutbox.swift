//
//  AgentOutbox.swift
//  MyAIAgent
//

import Foundation

/// Per-lead session persistence: the wire conversation, the visible
/// transcript, and whether a run was in flight when the app last wrote.
/// One JSON file per lead in Application Support — right-sized for a demo,
/// and initialized with a custom directory so tests get isolated storage.
nonisolated struct AgentOutbox {
    nonisolated struct SessionSnapshot: Codable, Equatable {
        var conversation: [WireMessage]
        var transcript: [ChatMessage]
        /// True from run start until the run completes or fails. A snapshot
        /// loaded with this set means the app died (or lost the network)
        /// mid-run — the UI offers Resume, which replays the saved
        /// conversation from the last durable boundary.
        var interrupted: Bool
    }

    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("AgentSessions", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func fileURL(for leadID: UUID) -> URL {
        directory.appendingPathComponent("\(leadID.uuidString).json")
    }

    func save(_ snapshot: SessionSnapshot, for leadID: UUID) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL(for: leadID), options: .atomic)
    }

    func load(for leadID: UUID) -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: leadID)) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    func clear(for leadID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: leadID))
    }
}
