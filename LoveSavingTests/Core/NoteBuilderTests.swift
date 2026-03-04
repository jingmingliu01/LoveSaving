import XCTest
@testable import LoveSaving

final class NoteBuilderTests: XCTestCase {
    func testDefaultNoteUsesAddressWhenProvided() {
        let note = NoteBuilder.defaultNote(occurredAt: Date(timeIntervalSince1970: 0), addressText: "Seattle")
        XCTAssertTrue(note.hasSuffix(" at Seattle"))
    }

    func testDefaultNoteFallsBackForBlankAddress() {
        let note = NoteBuilder.defaultNote(occurredAt: Date(timeIntervalSince1970: 0), addressText: "   ")
        XCTAssertTrue(note.hasSuffix(" at current location"))
    }
}
