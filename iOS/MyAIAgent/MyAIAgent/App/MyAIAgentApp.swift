//
//  MyAIAgentApp.swift
//  MyAIAgent
//

import SwiftUI

@main
struct MyAIAgentApp: App {
    @State private var store = CRMStore()

    var body: some Scene {
        WindowGroup {
            // Fail fast when no API key was injected at build time — with
            // instructions instead of a crash, so tests and previews still run.
            if let apiKey = ClaudeProvider.bundledAPIKey() {
                ContentView(provider: ClaudeProvider(apiKey: apiKey))
                    .environment(store)
            } else {
                KeyMissingView()
            }
        }
    }
}
