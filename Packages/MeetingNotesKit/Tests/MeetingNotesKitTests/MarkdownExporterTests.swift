import Foundation
import XCTest
@testable import MeetingNotesKit

final class MarkdownExporterTests: XCTestCase {
    private func makeDocument() -> MarkdownExporter.Document {
        MarkdownExporter.Document(
            title: "Weekly Sync",
            date: Date(timeIntervalSince1970: 1_760_000_000),
            duration: 754,
            attendees: ["Ana", "Ben"],
            summary: MeetingSummary(
                title: "Weekly Sync",
                summary: "The team went through the roadmap and agreed on the launch plan.",
                keyPoints: ["Roadmap is on track", "Two bugs still open"],
                decisions: ["Ship the beta on Friday"],
                actionItems: [ActionItem(text: "Send the release notes", owner: "Ana", due: "Friday")],
                followUpQuestions: ["Who owns the analytics work?"]
            ),
            scratchpad: "Remember to follow up with the designer.",
            transcript: "Ana opened the meeting and asked about the roadmap."
        )
    }

    func testMarkdownContainsEverySection() {
        let markdown = MarkdownExporter.markdown(for: makeDocument())
        XCTAssertTrue(markdown.hasPrefix("# Weekly Sync"))
        XCTAssertTrue(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("## Key points"))
        XCTAssertTrue(markdown.contains("## Decisions"))
        XCTAssertTrue(markdown.contains("## Action items"))
        XCTAssertTrue(markdown.contains("## Open questions"))
        XCTAssertTrue(markdown.contains("## My notes"))
        XCTAssertTrue(markdown.contains("## Transcript"))
    }

    func testMarkdownListsActionItemsAsCheckboxes() {
        let markdown = MarkdownExporter.markdown(for: makeDocument())
        XCTAssertTrue(markdown.contains("- [ ] Send the release notes (owner: Ana, due: Friday)"))
    }

    func testMarkdownWithoutSummaryStillExportsNotesAndTranscript() {
        var document = makeDocument()
        document.summary = nil
        let markdown = MarkdownExporter.markdown(for: document)
        XCTAssertFalse(markdown.contains("## Summary"))
        XCTAssertTrue(markdown.contains("Remember to follow up with the designer."))
        XCTAssertTrue(markdown.contains("Ana opened the meeting"))
    }

    func testFileNameUsesDateAndSlug() {
        let name = MarkdownExporter.fileName(for: makeDocument())
        XCTAssertTrue(name.hasSuffix("-weekly-sync.md"))
        XCTAssertTrue(name.hasPrefix("2025-"))
    }

    func testSlugFallsBackForEmptyTitles() {
        XCTAssertEqual(MarkdownExporter.slug(for: "   "), "meeting")
        XCTAssertEqual(MarkdownExporter.slug(for: "Q3 / Planning!"), "q3-planning")
    }

    func testDurationText() {
        XCTAssertEqual(MarkdownExporter.durationText(45), "45 s")
        XCTAssertEqual(MarkdownExporter.durationText(90), "1 min 30 s")
        XCTAssertEqual(MarkdownExporter.durationText(3_600), "60 min 0 s")
    }
}
