import Testing

@testable import AloudUI

@Suite struct FolderCardTests {
    /// The number and the noun agree: a folder with one note in it is not "1 documents".
    @Test func theCountAgreesWithItsNoun() {
        #expect(FolderCard.status(count: 0) == "Empty folder")
        #expect(FolderCard.status(count: 1) == "1 document")
        #expect(FolderCard.status(count: 2) == "2 documents")
        #expect(FolderCard.status(count: 30) == "30 documents")
    }
}
