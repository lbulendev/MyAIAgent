//
//  TestTags.swift
//  MyAIAgentTests
//

import Testing

// Tag taxonomy, mirroring HeartChart and TheMovieDBSwift: purpose tags say
// WHEN a test should run; area tags say WHAT it covers. Every test carries
// one purpose tag (via its suite) and one area tag, so test plans can
// filter either way.
extension Tag {
    // MARK: Purpose

    /// Critical-path checks: if any of these fail the build is not worth
    /// testing further. Fast, no edge cases.
    @Tag static var smoke: Self

    /// Contract checks on helpers and defaults: tool schemas, sample data,
    /// error mapping. Failures usually mean scaffolding drift.
    @Tag static var sanity: Self

    /// Pinned edge cases that must never come back: SSE chunking, unknown
    /// stream events, outbox resume, cancellation.
    @Tag static var regression: Self

    // MARK: Area

    @Tag static var agent: Self
    @Tag static var parsing: Self
    @Tag static var tools: Self
    @Tag static var persistence: Self
    @Tag static var catalog: Self
}
