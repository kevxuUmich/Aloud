import Foundation
import Testing

@testable import Vault

@Suite struct PathsTests {
    @Test func theRootItselfIsInside() {
        #expect(Paths.isInside("/Users/k/Notes", root: "/Users/k/Notes"))
    }
    @Test func aChildIsInside() {
        #expect(Paths.isInside("/Users/k/Notes/deep/a.md", root: "/Users/k/Notes"))
    }
    @Test func aSiblingSharingAPrefixIsNot() {
        #expect(!Paths.isInside("/Users/k/NotesArchive/x", root: "/Users/k/Notes"))
        #expect(!Paths.isInside("/Users/k/NotesArchive", root: "/Users/k/Notes"))
    }
    @Test func aTrailingSlashOnTheRootDoesNotChangeTheAnswer() {
        #expect(Paths.isInside("/Users/k/Notes", root: "/Users/k/Notes/"))
        #expect(!Paths.isInside("/Users/k/NotesArchive", root: "/Users/k/Notes/"))
    }
    @Test func anUnrelatedPathIsNot() {
        #expect(!Paths.isInside("/Users/k/Other", root: "/Users/k/Notes"))
    }
}
