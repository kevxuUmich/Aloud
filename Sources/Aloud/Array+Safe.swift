extension Array {
    /// An index that may be past the end, which is what a player's sentence index is
    /// between a load and the script it belongs to.
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
